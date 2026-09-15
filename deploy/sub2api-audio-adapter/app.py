"""OpenAI-compatible speech endpoints backed by Sub2API and Edge TTS."""

from __future__ import annotations

import base64
import io
import logging
import os
import wave

import edge_tts
import httpx
import miniaudio
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI(title="Sub2API audio adapter")
logger = logging.getLogger(__name__)
SUB2API_URL = os.getenv("SUB2API_URL", "http://sub2api:8080/v1").rstrip("/")
ANTIGRAVITY_URL = os.getenv(
    "ANTIGRAVITY_URL", "https://gpt.isoziyuan.com/antigravity/v1beta"
).rstrip("/")
STT_MODEL = os.getenv("SUB2API_STT_MODEL", "gemini-3-flash")
TTS_VOICE = os.getenv("EDGE_TTS_VOICE", "zh-CN-XiaoxiaoNeural")


def response_text(payload: object) -> str:
    """Extract text from standard and Gemini-compatibility chat response shapes."""

    if isinstance(payload, dict):
        candidates = payload.get("candidates")
        if isinstance(candidates, list) and candidates:
            candidate_content = candidates[0].get("content", {}) if isinstance(candidates[0], dict) else {}
            parts = candidate_content.get("parts", []) if isinstance(candidate_content, dict) else []
            return "".join(part.get("text", "") for part in parts if isinstance(part, dict)).strip()
    try:
        content = payload["choices"][0]["message"]["content"]  # type: ignore[index]
    except (KeyError, IndexError, TypeError):
        return ""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, dict):
        return str(content.get("text") or content.get("content") or "").strip()
    if isinstance(content, list):
        parts: list[str] = []
        for part in content:
            if isinstance(part, str):
                parts.append(part)
            elif isinstance(part, dict):
                value = part.get("text") or part.get("content")
                if isinstance(value, str):
                    parts.append(value)
        return "".join(parts).strip()
    return ""


def bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Bearer API key required")
    return authorization


async def verify_key(authorization: str) -> None:
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(f"{SUB2API_URL}/models", headers={"Authorization": authorization})
    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail="Sub2API authentication failed")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str | None = Form(None),
    language: str | None = Form(None),
    authorization: str | None = Header(None),
) -> dict[str, str]:
    auth = bearer(authorization)
    audio = await file.read()
    if not audio:
        raise HTTPException(status_code=400, detail="Empty audio file")
    if len(audio) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Audio file too large")

    audio_format = "wav"
    if file.filename and "." in file.filename:
        audio_format = file.filename.rsplit(".", 1)[-1].lower()
    prompt = "请准确转写这段音频。只返回转写文字，不要解释。"
    if language:
        prompt += f" 音频语言是 {language}。"
    selected_model = model if model and model.startswith("gemini-") else STT_MODEL
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": prompt},
                    {
                        "inlineData": {
                            "mimeType": f"audio/{audio_format}",
                            "data": base64.b64encode(audio).decode("ascii"),
                        }
                    },
                ],
            }
        ]
    }
    text = ""
    async with httpx.AsyncClient(timeout=90) as client:
        for attempt in range(2):
            response = await client.post(
                f"{ANTIGRAVITY_URL}/models/{selected_model}:generateContent",
                headers={"Authorization": auth},
                json=payload,
            )
            if response.status_code != 200:
                raise HTTPException(status_code=response.status_code, detail=response.text[:500])
            try:
                text = response_text(response.json())
            except ValueError as exc:
                raise HTTPException(status_code=502, detail="Invalid transcription response") from exc
            if text or attempt == 1:
                break
            payload["contents"][0]["parts"][0]["text"] += " 请直接输出听到的文字。"
    if not text:
        # The speech-to-speech client starts with a one-second silent warm-up
        # request. Gemini correctly returns no words for silence; an empty
        # OpenAI-compatible transcription is a successful response here.
        logger.info("STT response contained no text (silence or no speech)")
    return {"text": text}


class SpeechRequest(BaseModel):
    model: str = "edge-tts"
    input: str
    voice: str = TTS_VOICE
    response_format: str = "mp3"
    speed: float = 1.0


@app.post("/v1/audio/speech")
async def speech(request: SpeechRequest, authorization: str | None = Header(None)) -> Response:
    auth = bearer(authorization)
    await verify_key(auth)
    if not request.input.strip():
        raise HTTPException(status_code=400, detail="Input text is empty")
    rate = round((request.speed - 1.0) * 100)
    communicate = edge_tts.Communicate(request.input, request.voice or TTS_VOICE, rate=f"{rate:+d}%")
    audio = bytearray()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            audio.extend(chunk["data"])
    if not audio:
        raise HTTPException(status_code=502, detail="TTS provider returned no audio")
    decoded = miniaudio.decode(
        bytes(audio),
        output_format=miniaudio.SampleFormat.SIGNED16,
        nchannels=1,
        sample_rate=24_000,
    )
    pcm = bytes(decoded.samples)
    if request.response_format == "wav":
        output = io.BytesIO()
        with wave.open(output, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(24_000)
            wav.writeframes(pcm)
        return Response(output.getvalue(), media_type="audio/wav")
    return Response(pcm, media_type="audio/pcm")

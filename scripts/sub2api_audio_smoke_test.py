"""Exercise the deployed cloud audio bridge without printing its API key."""

from __future__ import annotations

import io
import os
import wave
from pathlib import Path

import httpx


def main() -> None:
    base_url = os.getenv("SUB2API_AUDIO_BASE_URL", "https://gpt.isoziyuan.com/v1").rstrip("/")
    key_path = Path(os.getenv("SUB2API_AUDIO_KEY_FILE", Path.home() / ".hermes-cloud-audio" / "api_key"))
    api_key = key_path.read_text(encoding="utf-8").strip()
    headers = {"Authorization": f"Bearer {api_key}"}
    with httpx.Client(timeout=90) as client:
        speech = client.post(
            f"{base_url}/audio/speech",
            headers=headers,
            json={
                "model": "edge-tts",
                "input": "云端语音测试成功。",
                "voice": "zh-CN-XiaoxiaoNeural",
                "response_format": "pcm",
            },
        )
        speech.raise_for_status()
        if len(speech.content) < 1000:
            raise RuntimeError("TTS returned too little audio")

        wav = io.BytesIO()
        with wave.open(wav, "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(24_000)
            output.writeframes(speech.content)
        transcription = client.post(
            f"{base_url}/audio/transcriptions",
            headers=headers,
            files={"file": ("smoke.wav", wav.getvalue(), "audio/wav")},
            data={"model": "gemini-3-flash", "language": "zh"},
        )
        if transcription.is_error:
            raise RuntimeError(
                f"STT request failed with {transcription.status_code}: {transcription.text[:800]}"
            )
        text = transcription.json().get("text", "").strip()
        if not text:
            raise RuntimeError("STT returned an empty transcription")
    print(f"cloud-audio-ok: pcm_bytes={len(speech.content)} transcription_chars={len(text)}")


if __name__ == "__main__":
    main()

"""Exercise the local Hermes realtime bridge with a Chinese text turn."""

from __future__ import annotations

import base64
import json

from websockets.sync.client import connect


def main() -> None:
    with connect("ws://127.0.0.1:8765/v1/realtime") as websocket:
        created = json.loads(websocket.recv(timeout=10))
        if created.get("type") != "session.created":
            raise RuntimeError(f"Unexpected first event: {created}")

        websocket.send(
            json.dumps(
                {
                    "type": "conversation.item.create",
                    "item": {
                        "type": "message",
                        "role": "user",
                        "content": [
                            {
                                "type": "input_text",
                                "text": "只用一句简短中文回答：语音链路测试是否成功？",
                            }
                        ],
                    },
                }
            )
        )
        websocket.send(json.dumps({"type": "response.create"}))

        audio_chars = 0
        audio_payloads: list[str] = []
        transcript = ""
        event_count = 0
        event_types: list[str] = []
        while True:
            event = json.loads(websocket.recv(timeout=120))
            event_count += 1
            event_type = event.get("type", "")
            event_types.append(event_type)
            if event_type in {"response.output_audio.delta", "response.audio.delta"}:
                payload = event.get("delta", "")
                audio_payloads.append(payload)
                audio_chars += len(payload)
            elif event_type in {"response.output_audio_transcript.done", "response.audio_transcript.done"}:
                transcript = event.get("transcript", "")
            elif event_type == "response.done":
                status = event["response"]["status"]
                break

        # Feed the spoken answer back as microphone audio. Server VAD should
        # close the turn after the trailing silence, then ASR, Hermes, and TTS
        # must produce a second completed response.
        for payload in audio_payloads:
            websocket.send(json.dumps({"type": "input_audio_buffer.append", "audio": payload}))
        silence = base64.b64encode(bytes(24_000 * 2)).decode("ascii")
        websocket.send(json.dumps({"type": "input_audio_buffer.append", "audio": silence}))

        recognized = ""
        roundtrip_audio_chars = 0
        roundtrip_status = None
        while roundtrip_status is None:
            event = json.loads(websocket.recv(timeout=180))
            event_type = event.get("type", "")
            event_types.append(event_type)
            if event_type == "conversation.item.input_audio_transcription.completed":
                recognized = event.get("transcript", "")
            elif event_type in {"response.output_audio.delta", "response.audio.delta"}:
                roundtrip_audio_chars += len(event.get("delta", ""))
            elif event_type == "response.done":
                roundtrip_status = event["response"]["status"]

    result = {
        "status": status,
        "audio_base64_chars": audio_chars,
        "transcript": transcript,
        "event_count": event_count,
        "event_types": event_types,
        "recognized_audio": recognized,
        "roundtrip_status": roundtrip_status,
        "roundtrip_audio_base64_chars": roundtrip_audio_chars,
    }
    print(json.dumps(result, ensure_ascii=False))
    if (
        status != "completed"
        or audio_chars == 0
        or not transcript
        or not recognized
        or roundtrip_status != "completed"
        or roundtrip_audio_chars == 0
    ):
        raise RuntimeError(f"Hermes voice smoke test failed: {result}")


if __name__ == "__main__":
    main()

# 2026-09-15

- Forked `huggingface/speech-to-speech` to `yys9253462-gif/speech-to-speech`.
- Added a `--hermes` preset for Chinese Qwen3-ASR, Hermes Chat Completions, and local speech output.
- Enabled and authenticated the local Hermes API server on `127.0.0.1:8642`.
- Added a Windows CPU fallback to ChatTTS because Qwen3-TTS has no usable CPU backend on Windows.
- Fixed ChatTTS 0.2.x one-dimensional streaming waveform handling.
- Verified a loopback voice round trip through ASR, Hermes, and TTS.

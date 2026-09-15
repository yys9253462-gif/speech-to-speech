# Project memory

- Development branch: `feature/live-voice-agent`.
- Hermes API: `http://127.0.0.1:8642/v1`, model `hermes-agent`.
- Secrets remain in the Hermes environment and must never be committed.
- ChatTTS downloads runtime weights into `asset/`, which is ignored by Git.
- Run `scripts/hermes_smoke_test.py` against a running `serve --hermes` process for a full synthetic audio loopback check.

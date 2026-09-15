"""Create a personal Sub2API key through the public management API."""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

import httpx


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"').strip("'")
    return values


def main() -> None:
    env = load_env(Path(os.getenv("SUB2API_ENV", "/opt/sub2api/.env")))
    base_url = os.getenv("SUB2API_PUBLIC_URL", "https://gpt.isoziyuan.com")
    login = httpx.post(
        f"{base_url}/api/v1/auth/login",
        json={"email": env["ADMIN_EMAIL"], "password": env["ADMIN_PASSWORD"]},
        timeout=30,
    )
    login.raise_for_status()
    token = login.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}", "Idempotency-Key": str(uuid.uuid4())}

    group_id = int(os.getenv("SUB2API_GROUP_ID", "7"))
    created = httpx.post(
        f"{base_url}/api/v1/keys",
        headers=headers,
        json={"name": f"Hermes Cloud Audio {group_id}", "group_id": group_id},
        timeout=30,
    )
    created.raise_for_status()
    key_file = Path(os.getenv("SUB2API_KEY_FILE", "/root/.config/hermes-cloud-audio/api_key"))
    key_file.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    key_file.write_text(created.json()["data"]["key"] + "\n", encoding="utf-8")
    key_file.chmod(0o600)
    print("created")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"provision failed: {exc}", file=sys.stderr)
        raise

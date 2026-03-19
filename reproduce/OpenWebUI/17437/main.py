from __future__ import annotations

import json
import mimetypes
import subprocess
import sys
import time
from pathlib import Path

import requests

# CONFIG

BASE_URL = "http://localhost:3000"

USER_EMAIL = "user@example.org"
USER_PASSWORD = "userpassword"

UPLOAD_FILE_PATH = "./lorem_file.docx"

CONTAINER_NAME = "open-webui"
CONTAINER_DATA_DIR = "/app/backend/data"

WAIT_SECONDS = 8
PROCESS_FILE = False


# API HELPERS

def login(email: str, password: str) -> str:
    url = f"{BASE_URL.rstrip('/')}/api/v1/auths/signin"

    resp = requests.post(
        url,
        json={"email": email, "password": password},
        timeout=30,
    )

    if resp.status_code != 200:
        print(f"Login failed for {email}: {resp.status_code}")
        print(resp.text)
        sys.exit(1)

    data = resp.json()
    token = data.get("token") or data.get("access_token")
    if not token:
        print("Token not found in login response")
        print(data)
        sys.exit(1)

    return token


def upload_file(token: str, file_path: Path) -> dict:
    url = f"{BASE_URL.rstrip('/')}/api/v1/files/"
    params = {
        "process": str(PROCESS_FILE).lower(),
        "process_in_background": "false",
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    mime_type, _ = mimetypes.guess_type(str(file_path))
    if not mime_type:
        mime_type = "application/octet-stream"

    with file_path.open("rb") as f:
        files = {"file": (file_path.name, f, mime_type)}
        resp = requests.post(
            url,
            headers=headers,
            params=params,
            files=files,
            timeout=120,
        )

    resp.raise_for_status()
    return resp.json()


# CONTAINER HELPERS

def run_in_container_python(code: str) -> str:
    cmd = ["docker", "exec", CONTAINER_NAME, "python3", "-c", code]
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("Container command failed:")
        print(result.stderr)
        sys.exit(1)

    return result.stdout.strip()


def list_stored_files() -> list[str]:
    code = rf"""
import json, os

root = {CONTAINER_DATA_DIR!r}
results = []

if os.path.exists(root):
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            low = path.lower()
            if "/uploads/" in low or low.endswith("webui.db"):
                results.append(path)

results.sort()
print(json.dumps(results))
"""
    out = run_in_container_python(code)
    return json.loads(out) if out else []


# MAIN

def main() -> None:
    upload_path = Path(UPLOAD_FILE_PATH).resolve()

    if not upload_path.exists():
        print(f"Upload file does not exist: {upload_path}")
        sys.exit(1)

    print("[1/3] Login as user")
    user_token = login(USER_EMAIL, USER_PASSWORD)
    print(" User login successful")

    print("\n[2/3] Upload lorem_file.docx as user")
    result = upload_file(user_token, upload_path)
    print("Upload response:")
    print(result)

    print(f"\n[3/3] Wait and inspect data storage")
    time.sleep(WAIT_SECONDS)

    files = list_stored_files()

    print("\nAccessible stored files inside data:")
    if files:
        for path in files:
            print(f"  {path}")
    else:
        print("  No upload files or database file found.")

    print("\nDone.")


if __name__ == "__main__":
    main()

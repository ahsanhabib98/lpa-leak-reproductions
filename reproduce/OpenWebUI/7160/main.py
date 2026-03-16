#!/usr/bin/env python3

import json
import subprocess
import sys
import time
from pathlib import Path

import requests

BASE_URL = "http://localhost:3000"
LDAP_CONTAINER = "ldap"
OPENWEBUI_CONTAINER = "open-webui"

LDAP_ADMIN_DN = "cn=admin,dc=example,dc=org"
LDAP_ADMIN_PASSWORD = "admin"

LDAP_USER_UID = "ldapuser"
LDAP_USER_EMAIL = "ldapuser@example.org"
LDAP_USER_PASSWORD = "ldap_password"
LDAP_USER_DN = f"uid={LDAP_USER_UID},ou=users,dc=example,dc=org"


def run(cmd, check=True):
    print(f"\n$ {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr)
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result


def wait_for_ldap(timeout=60):
    print("\nWaiting for LDAP...")
    start = time.time()
    while time.time() - start < timeout:
        result = subprocess.run(
            [
                "docker",
                "exec",
                LDAP_CONTAINER,
                "ldapwhoami",
                "-x",
                "-D",
                LDAP_ADMIN_DN,
                "-w",
                LDAP_ADMIN_PASSWORD,
            ],
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            print("LDAP is reachable.")
            return
        time.sleep(2)
    raise RuntimeError("LDAP did not become reachable in time")


def wait_for_openwebui(timeout=120):
    print("\nWaiting for Open WebUI...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(BASE_URL, timeout=5)
            if r.status_code in (200, 404):
                print("Open WebUI is reachable.")
                return
        except requests.RequestException:
            pass
        time.sleep(2)
    raise RuntimeError("Open WebUI did not become reachable in time")


def ensure_ou_exists():
    ldif = """dn: ou=users,dc=example,dc=org
objectClass: organizationalUnit
ou: users
"""
    Path("ou.ldif").write_text(ldif, encoding="utf-8")
    run(["docker", "cp", "ou.ldif", f"{LDAP_CONTAINER}:/ou.ldif"])

    result = subprocess.run(
        [
            "docker",
            "exec",
            LDAP_CONTAINER,
            "ldapadd",
            "-x",
            "-D",
            LDAP_ADMIN_DN,
            "-w",
            LDAP_ADMIN_PASSWORD,
            "-f",
            "/ou.ldif",
        ],
        text=True,
        capture_output=True,
    )
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr)

    if result.returncode != 0 and "Already exists" not in (result.stdout + result.stderr):
        raise RuntimeError("Failed to create ou=users")


def ensure_ldap_user():
    user_ldif = f"""dn: {LDAP_USER_DN}
objectClass: inetOrgPerson
cn: LDAP User
sn: User
uid: {LDAP_USER_UID}
mail: {LDAP_USER_EMAIL}
userPassword: {LDAP_USER_PASSWORD}
"""
    Path("user.ldif").write_text(user_ldif, encoding="utf-8")
    run(["docker", "cp", "user.ldif", f"{LDAP_CONTAINER}:/user.ldif"])

    result = subprocess.run(
        [
            "docker",
            "exec",
            LDAP_CONTAINER,
            "ldapadd",
            "-x",
            "-D",
            LDAP_ADMIN_DN,
            "-w",
            LDAP_ADMIN_PASSWORD,
            "-f",
            "/user.ldif",
        ],
        text=True,
        capture_output=True,
    )
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr)

    if result.returncode == 0:
        return

    if "Already exists" in (result.stdout + result.stderr):
        fix_ldif = f"""dn: {LDAP_USER_DN}
changetype: modify
replace: userPassword
userPassword: {LDAP_USER_PASSWORD}
"""
        Path("fix_password.ldif").write_text(fix_ldif, encoding="utf-8")
        run(["docker", "cp", "fix_password.ldif", f"{LDAP_CONTAINER}:/fix_password.ldif"])
        run(
            [
                "docker",
                "exec",
                LDAP_CONTAINER,
                "ldapmodify",
                "-x",
                "-D",
                LDAP_ADMIN_DN,
                "-w",
                LDAP_ADMIN_PASSWORD,
                "-f",
                "/fix_password.ldif",
            ]
        )
    else:
        raise RuntimeError("Failed to create LDAP user")


def verify_ldap_user():
    run(
        [
            "docker",
            "exec",
            LDAP_CONTAINER,
            "ldapwhoami",
            "-x",
            "-D",
            LDAP_USER_DN,
            "-w",
            LDAP_USER_PASSWORD,
        ]
    )


def login_openwebui_via_ldap():
    payload = {
        "user": LDAP_USER_UID,
        "password": LDAP_USER_PASSWORD,
    }

    r = requests.post(f"{BASE_URL}/api/v1/auths/ldap", json=payload, timeout=30)

    print("\n=== LDAP LOGIN RESPONSE ===")
    print("status:", r.status_code)
    print(r.text)

    if r.status_code != 200:
        raise RuntimeError("Open WebUI LDAP login failed")

    return r.json()


def inspect_db():
    py = f"""
import sqlite3
conn = sqlite3.connect('/app/backend/data/webui.db')
conn.row_factory = sqlite3.Row
cur = conn.cursor()

print("=== USER ROW ===")
for row in cur.execute("SELECT * FROM user WHERE email=?", ('{LDAP_USER_EMAIL}',)):
    print(dict(row))

print("=== AUTH ROW ===")
for row in cur.execute("SELECT * FROM auth WHERE email=?", ('{LDAP_USER_EMAIL}',)):
    print(dict(row))

conn.close()
"""
    run(["docker", "exec", OPENWEBUI_CONTAINER, "python3", "-c", py])


def main():
    wait_for_ldap()
    wait_for_openwebui()
    ensure_ou_exists()
    ensure_ldap_user()
    verify_ldap_user()

    login_data = login_openwebui_via_ldap()
    print("\n=== PARSED LOGIN JSON ===")
    print(json.dumps(login_data, indent=2))

    inspect_db()

    print("\nDone.")
    print("If AUTH ROW shows ldapuser@example.org with a non-empty password value, the issue is reproduced.")


if __name__ == "__main__":
    main()

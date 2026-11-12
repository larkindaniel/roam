#!/usr/bin/env python3
"""Create the App Review demo account on the hosted roam-beta project.

Creates one pre-confirmed email/password user through the Auth admin API (so no email
delivery is needed), then signs in as that user and creates its profile with the same RPC
the app uses. The password is generated here and written only to ignored .env.review.
Re-running reuses the saved credentials and skips steps already done. No fixtures or seed data.
"""
import json
import os
import secrets
import string
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "xnjzuotytfzyppubjcfi"
URL = f"https://{PROJECT}.supabase.co"
EMAIL = "dxxxx441+appreview@gmail.com"
NAME, HANDLE = "App Review", "appreview"
SAVED = ROOT / ".env.review"


def env_file(path):
    values = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip()
    return values


def call(url, payload=None, headers=None, method=None):
    req = urllib.request.Request(url, data=json.dumps(payload).encode() if payload is not None else None,
                                 method=method or ("POST" if payload is not None else "GET"),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


beta = env_file(ROOT / ".env.beta")
if beta.get("SUPABASE_PROJECT_REF") != PROJECT:
    raise SystemExit("The target must be the approved roam-beta project.")
status, keys = call(f"https://api.supabase.com/v1/projects/{PROJECT}/api-keys?reveal=true",
                    headers={"Authorization": "Bearer " + beta["SUPABASE_ACCESS_TOKEN"]})
if status != 200:
    raise SystemExit(f"Could not read project API keys (HTTP {status}).")
def pick(kind, prefix):
    for k in keys:
        if k.get("type") == kind and (k.get("api_key") or "").startswith(prefix):
            return k["api_key"]
    for k in keys:
        if k.get("name") == ("service_role" if kind == "secret" else "anon"):
            return k["api_key"]
    raise SystemExit(f"No {kind} key found.")
service = pick("secret", "sb_secret_")
public = pick("publishable", "sb_publishable_")

saved = env_file(SAVED)
password = saved.get("ROAM_REVIEW_PASSWORD")
if not password:
    alphabet = string.ascii_letters + string.digits
    password = "Roam-" + "".join(secrets.choice(alphabet) for _ in range(16))
    SAVED.write_text(f"# App Review demo account on roam-beta. Never commit.\nROAM_REVIEW_EMAIL={EMAIL}\nROAM_REVIEW_PASSWORD={password}\n")
    os.chmod(SAVED, 0o600)

admin = {"apikey": service, "Authorization": "Bearer " + service}
status, body = call(f"{URL}/auth/v1/admin/users", {"email": EMAIL, "password": password, "email_confirm": True}, admin)
if status in (200, 201):
    print("Created the review user.")
elif status == 422 or "already" in json.dumps(body):
    print("Review user already exists.")
else:
    raise SystemExit(f"Admin create failed (HTTP {status}): {body}")

status, session = call(f"{URL}/auth/v1/token?grant_type=password", {"email": EMAIL, "password": password}, {"apikey": public})
if status != 200:
    raise SystemExit(f"Sign-in failed (HTTP {status}): {session.get('error_description') or session.get('msg')}")
user = {"apikey": public, "Authorization": "Bearer " + session["access_token"]}
status, profile = call(f"{URL}/rest/v1/rpc/my_profile", {}, user)
if status == 200 and profile:
    print("Profile already set up.")
else:
    status, body = call(f"{URL}/rest/v1/rpc/create_profile", {"p_display_name": NAME, "p_handle": HANDLE}, user)
    if status != 200:
        raise SystemExit(f"create_profile failed (HTTP {status}): {body}")
    print(f"Created profile @{HANDLE}.")
print(f"Sign-in verified for {EMAIL}. Password saved in .env.review.")

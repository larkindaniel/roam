#!/usr/bin/env python3
"""Reproducible, test-only fixture setup for the disposable LOCAL Roam database.

- Creates fictional accounts through the local Auth admin API (service-role key read from the
  git-ignored scripts/.fixture-env; never printed, never shipped in the app or seed).
- Builds profiles, settings and friendships through the same RPCs the app uses, signed in as each user.
- Loads fictional places, public memories and private notes with SQL as the local `postgres` role.

Refuses to run against anything but a loopback API URL. Usage: scripts/fixtures/setup.py
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PASSWORD = "roam-fixture-pass"

USERS = [
    # id, email, handle, display name, bio, home city (name, region, code, country, lat, lon)
    ("00000010-0000-4000-8000-000000000001", "maya@roam.test", "mayaroams", "Maya Chen",
     "Collecting quiet trails, harbour cafés and late jazz sets.", ("Lisbon", "Lisboa", "PT", "Portugal", 38.7223, -9.1393)),
    ("00000010-0000-4000-8000-000000000002", "theo@roam.test", "theowanders", "Theo Park", "Slow travel, fast noodles.", None),
    ("00000010-0000-4000-8000-000000000003", "priya@roam.test", "priyaplans", "Priya Nair", "Spreadsheets for every itinerary.", None),
    ("00000010-0000-4000-8000-000000000004", "jonas@roam.test", "jonashikes", "Jonas Weber", "Ridge lines and mountain huts.", None),
    ("00000010-0000-4000-8000-000000000005", "lena@roam.test", "lenaeats", "Lena Ortiz", "", None),
    ("00000010-0000-4000-8000-000000000006", "sam@roam.test", "samexplores", "Sam Rivera", "Weekend explorer.", None),
]

# (first, second, accepted): the first asks, and the second accepts when accepted is True.
FRIENDS = [("maya", "theo", True), ("maya", "jonas", False), ("lena", "maya", False), ("sam", "maya", True)]


def load_env():
    path = os.path.join(ROOT, "scripts", ".fixture-env")
    if not os.path.exists(path):
        subprocess.run([os.path.join(ROOT, "scripts", "configure-local.sh")], check=True, stdout=subprocess.DEVNULL)
    env = {}
    with open(path) as handle:
        for line in handle:
            if "=" in line and not line.startswith("#"):
                key, value = line.strip().split("=", 1)
                env[key] = value
    host = urlparse(env["ROAM_API_URL"]).hostname
    if host not in ("127.0.0.1", "localhost"):
        sys.exit(f"Refusing to run fixtures against non-local API host {host}")
    return env


def request(env, method, path, body=None, token=None, admin=False):
    url = env["ROAM_API_URL"] + path
    headers = {"Content-Type": "application/json",
               "apikey": env["ROAM_SERVICE_ROLE_KEY"] if admin else env["ROAM_PUBLISHABLE_KEY"]}
    if admin:
        headers["Authorization"] = "Bearer " + env["ROAM_SERVICE_ROLE_KEY"]
    elif token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            text = response.read().decode()
            return response.status, (json.loads(text) if text else None)
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        try:
            return error.code, json.loads(text)
        except json.JSONDecodeError:
            return error.code, text


def ensure_user(env, user_id, email):
    status, body = request(env, "POST", "/auth/v1/admin/users", {
        "id": user_id, "email": email, "password": PASSWORD, "email_confirm": True,
        "user_metadata": {"roam_fixture": True}}, admin=True)
    if status in (200, 201):
        return "created"
    if status == 422 or (isinstance(body, dict) and "already" in json.dumps(body)):
        return "exists"
    sys.exit(f"Could not create fixture user {email}: HTTP {status} {body}")


def sign_in(env, email):
    status, body = request(env, "POST", "/auth/v1/token?grant_type=password", {"email": email, "password": PASSWORD})
    if status != 200:
        sys.exit(f"Fixture sign-in failed for {email}: HTTP {status}")
    return body["access_token"]


def rpc(env, token, name, params):
    status, body = request(env, "POST", f"/rest/v1/rpc/{name}", params, token=token)
    if status >= 300:
        sys.exit(f"RPC {name} failed: HTTP {status} {body}")
    return body


def run_sql(path):
    with open(path, "rb") as handle:
        result = subprocess.run(["docker", "exec", "-i", "supabase_db_roam", "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
                                stdin=handle, capture_output=True)
    if result.returncode != 0:
        sys.exit(f"Fixture SQL failed ({os.path.basename(path)}):\n{result.stderr.decode()}")


def main():
    env = load_env()
    tokens = {}
    for user_id, email, handle, name, bio, home in USERS:
        state = ensure_user(env, user_id, email)
        token = sign_in(env, email)
        tokens[handle[:4] if handle != "jonashikes" else "jona"] = token
        tokens[email.split("@")[0]] = token
        rpc(env, token, "create_profile", {"p_display_name": name, "p_handle": handle})
        home_json = None
        if home:
            home_json = {"name": home[0], "region": home[1], "countryCode": home[2], "countryName": home[3],
                         "latitude": home[4], "longitude": home[5], "radiusMeters": 15000}
        rpc(env, token, "update_profile", {"p_display_name": name, "p_handle": handle, "p_bio": bio,
                                           "p_home_city": home_json, "p_avatar_path": None})
        rpc(env, token, "set_setup_checkpoint", {"p_checkpoint": "complete"})
        rpc(env, token, "mark_been_intro_seen", {})
        print(f"  {email:<18} {state}")
    ids = {u[1].split("@")[0]: u[0] for u in USERS}
    for first, second, accepted in FRIENDS:
        rpc(env, tokens[first], "friend_action", {"p_user_id": ids[second], "p_action": "request"})
        if accepted:
            rpc(env, tokens[second], "friend_action", {"p_user_id": ids[first], "p_action": "accept"})
    run_sql(os.path.join(ROOT, "supabase", "fixtures", "fixture-data.sql"))
    print(f"Fixture accounts ready (password in scripts/fixtures/setup.py), {len(FRIENDS)} friend links, places and memories loaded.")


if __name__ == "__main__":
    main()

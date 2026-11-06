#!/usr/bin/env python3
"""Tests for scripts/account-deletion.py.

Unit tests use a fake transport and need nothing running. The live test (ROAM_LIVE_DELETION=1)
creates a disposable member on the LOCAL stack, gives it a profile and a stored photo, requests
deletion with a fresh sign-in, runs the worker and checks the auth user, profile, Storage objects
and sessions are gone. It touches no fixture or real account and prints no secrets.

    python3 -I scripts/tests/test_account_deletion.py
    ROAM_LIVE_DELETION=1 python3 -I scripts/tests/test_account_deletion.py
"""
import importlib.util
import json
import os
import subprocess
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("account_deletion", ROOT / "scripts" / "account-deletion.py")
account_deletion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(account_deletion)


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class FakeServer:
    """Answers the deletion and cleanup RPCs like the local stack would."""

    def __init__(self, jobs, process_states, refresh_state="completed", fail_process=False):
        self.jobs = jobs
        self.process_states = list(process_states)
        self.refresh_state = refresh_state
        self.fail_process = fail_process
        self.calls = []

    def __call__(self, request, timeout):
        path = urllib.parse.urlparse(request.full_url).path
        payload = json.loads(request.data) if request.data else None
        name = path.rsplit("/", 1)[-1]
        self.calls.append((name, payload))
        if name == "claim_account_deletions":
            return FakeResponse(200, json.dumps(self.jobs).encode())
        if name == "process_account_deletion":
            if self.fail_process:
                raise urllib.error.HTTPError(request.full_url, 500, "error", {}, None)
            return FakeResponse(200, json.dumps({"state": self.process_states.pop(0)}).encode())
        if name in ("fail_account_deletion", "finish_media_cleanup"):
            return FakeResponse(200, b"true")
        if name == "refresh_account_deletion":
            return FakeResponse(200, json.dumps({"state": self.refresh_state}).encode())
        if name == "sweep_media_orphans":
            return FakeResponse(200, b'{"registered": 0, "unregistered": 0}')
        if name == "claim_media_cleanup":
            return FakeResponse(200, json.dumps([{"id": 9, "bucket": "avatars", "path": "u/a.jpg", "attempt": 1}]).encode())
        if path.startswith("/storage/v1/object/"):
            return FakeResponse(200, b"[]")
        raise AssertionError("unexpected request " + path)

    def named(self, name):
        return [payload for call, payload in self.calls if call == name]


class AccountDeletionUnitTests(unittest.TestCase):
    def test_processes_then_cleans_storage_then_completes(self):
        server = FakeServer([{"id": "j1", "userID": "u", "appleRevocation": "not_applicable"}], ["processing"])
        summary = account_deletion.AccountDeletion("http://127.0.0.1:54321", "key", worker="w1", transport=server).once()
        self.assertEqual(summary["completed"], 1)
        self.assertEqual(summary["stillProcessing"], 0)
        order = [call for call, _ in server.calls]
        self.assertLess(order.index("process_account_deletion"), order.index("claim_media_cleanup"))
        self.assertLess(order.index("claim_media_cleanup"), order.index("refresh_account_deletion"),
                        "a job completes only after its Storage objects were cleaned")
        self.assertEqual(server.named("process_account_deletion")[0]["p_worker"], "w1", "only the leaseholder processes")

    def test_apple_jobs_record_missing_revocation_configuration(self):
        server = FakeServer([{"id": "j2", "userID": "u", "appleRevocation": "pending"}], ["completed"])
        account_deletion.AccountDeletion("http://127.0.0.1:54321", "key", transport=server).once()
        self.assertEqual(server.named("process_account_deletion")[0]["p_apple_revocation"], "not_configured",
                         "no Apple credentials exist locally, so nothing claims a revocation")

    def test_a_failed_attempt_is_released_for_retry_without_details(self):
        server = FakeServer([{"id": "j3", "userID": "u", "appleRevocation": "not_applicable"}], [], fail_process=True)
        summary = account_deletion.AccountDeletion("http://127.0.0.1:54321", "key", worker="w3", transport=server).once()
        self.assertEqual(summary["failed"], 1)
        failure = server.named("fail_account_deletion")[0]
        self.assertEqual(failure["p_worker"], "w3")
        self.assertEqual(failure["p_error"], "Deletion attempt failed; retrying.")
        self.assertEqual(server.named("refresh_account_deletion"), [])

    def test_storage_still_present_keeps_the_job_processing(self):
        server = FakeServer([{"id": "j4", "userID": "u", "appleRevocation": "not_applicable"}], ["processing"], refresh_state="processing")
        summary = account_deletion.AccountDeletion("http://127.0.0.1:54321", "key", transport=server).once()
        self.assertEqual(summary["completed"], 0)
        self.assertEqual(summary["stillProcessing"], 1)


def fixture_env():
    values = {}
    for line in (ROOT / "scripts" / ".fixture-env").read_text().splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def psql(sql):
    result = subprocess.run(["docker", "exec", "supabase_db_roam", "psql", "-U", "postgres", "-d", "postgres", "-At", "-c", sql],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


def call(url, method="GET", body=None, headers=None):
    request = urllib.request.Request(url, method=method, data=None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode()),
                                     headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = response.read()
            return response.status, json.loads(data) if data and data[:1] in (b"{", b"[") else data
    except urllib.error.HTTPError as error:
        return error.code, None


@unittest.skipUnless(os.environ.get("ROAM_LIVE_DELETION") == "1", "live deletion needs the local stack and ROAM_LIVE_DELETION=1")
class LiveAccountDeletionTest(unittest.TestCase):
    def test_a_disposable_member_is_fully_deleted(self):
        env = fixture_env()
        url, key = account_deletion.media_cleanup.configuration()
        publishable = env["ROAM_PUBLISHABLE_KEY"]
        admin = {"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"}
        email, password = f"delete-{uuid.uuid4().hex[:10]}@roam.test", "disposable-pass-123"
        status, user = call(url + "/auth/v1/admin/users", "POST", {"email": email, "password": password, "email_confirm": True}, admin)
        self.assertEqual(status, 200)
        user_id = user["id"]
        status, session = call(url + "/auth/v1/token?grant_type=password", "POST", {"email": email, "password": password},
                               {"apikey": publishable, "Content-Type": "application/json"})
        self.assertEqual(status, 200)
        member = {"apikey": publishable, "Authorization": "Bearer " + session["access_token"], "Content-Type": "application/json"}
        status, _ = call(url + "/rest/v1/rpc/create_profile", "POST", {"p_display_name": "Leaving Member",
                                                                        "p_handle": "leave_" + uuid.uuid4().hex[:8]}, member)
        self.assertEqual(status, 200)
        photo = f"{user_id}/{uuid.uuid4()}.jpg"
        status, _ = call(url + "/storage/v1/object/avatars/" + photo, "POST", b"\xff\xd8leaving\xff\xd9",
                         {**member, "Content-Type": "image/jpeg"})
        self.assertEqual(status, 200)

        status, requested = call(url + "/rest/v1/rpc/request_account_deletion", "POST", {}, member)
        self.assertEqual(status, 200)
        self.assertEqual(requested["state"], "pending")
        status, _ = call(url + "/auth/v1/token?grant_type=refresh_token", "POST", {"refresh_token": session["refresh_token"]},
                         {"apikey": publishable, "Content-Type": "application/json"})
        self.assertNotEqual(status, 200, "sessions are revoked when deletion is requested")

        summary = None
        for _ in range(5):
            summary = account_deletion.AccountDeletion(url, key).once()
            if psql(f"select state from app_private.account_deletion_jobs where user_id='{user_id}'") == "completed":
                break
        print(json.dumps(summary))
        self.assertEqual(psql(f"select state||'/'||storage_cleanup||'/'||apple_revocation from app_private.account_deletion_jobs where user_id='{user_id}'"),
                         "completed/completed/not_applicable")
        status, _ = call(url + f"/auth/v1/admin/users/{user_id}", headers=admin)
        self.assertEqual(status, 404, "the auth user is deleted")
        self.assertEqual(psql(f"select count(*) from public.profiles where id='{user_id}'"), "0")
        self.assertEqual(psql(f"select count(*) from storage.objects where name like '{user_id}/%'"), "0", "their stored photo is deleted")
        status, final = call(url + "/rest/v1/rpc/account_deletion_status", "POST", {}, member)
        self.assertEqual(status, 200)
        self.assertEqual(final["state"], "completed", "the requesting token can read the honest final state")
        status, _ = call(url + "/rest/v1/rpc/create_profile", "POST", {"p_display_name": "Back", "p_handle": "back_" + uuid.uuid4().hex[:8]}, member)
        self.assertNotEqual(status, 200, "a stale token cannot recreate the profile")
        self.assertEqual(psql(f"select count(*) from public.profiles where id='{user_id}'"), "0")


if __name__ == "__main__":
    unittest.main(verbosity=2)

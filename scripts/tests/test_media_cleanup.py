#!/usr/bin/env python3
"""Tests for scripts/media-cleanup.py.

Unit tests use a fake transport and need nothing running. The live test (ROAM_LIVE_CLEANUP=1)
uploads a real orphan object to the LOCAL stack, ages it past 24 hours in the disposable local
database, runs one cleanup pass and checks the object and its job are gone. Prints no secrets.

    python3 -I scripts/tests/test_media_cleanup.py
    ROAM_LIVE_CLEANUP=1 python3 -I scripts/tests/test_media_cleanup.py
"""
import importlib.util
import json
import os
import subprocess
import sys
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("media_cleanup", ROOT / "scripts" / "media-cleanup.py")
media_cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media_cleanup)


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
    """Answers the cleanup RPCs and Storage deletes like the local stack would."""

    def __init__(self, jobs, storage_outcomes, rpc_status=200):
        self.jobs = jobs
        self.storage_outcomes = list(storage_outcomes)
        self.rpc_status = rpc_status
        self.finished = []
        self.deleted = []

    def __call__(self, request, timeout):
        path = urllib.parse.urlparse(request.full_url).path
        payload = json.loads(request.data) if request.data else None
        if path.startswith("/rest/v1/rpc/") and self.rpc_status != 200:
            raise urllib.error.HTTPError(request.full_url, self.rpc_status, "error", {}, None)
        if path.endswith("/rpc/sweep_media_orphans"):
            return FakeResponse(200, b'{"registered": 1, "unregistered": 1}')
        if path.endswith("/rpc/claim_media_cleanup"):
            return FakeResponse(200, json.dumps(self.jobs).encode())
        if path.endswith("/rpc/finish_media_cleanup"):
            self.finished.append(payload)
            return FakeResponse(200, b"true")
        if path.startswith("/storage/v1/object/"):
            self.deleted.append((path, payload))
            outcome = self.storage_outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            if outcome >= 400:
                raise urllib.error.HTTPError(request.full_url, outcome, "error", {}, None)
            return FakeResponse(outcome, b"[]")
        raise AssertionError("unexpected request " + path)


JOBS = [{"id": 1, "bucket": "visit-media", "path": "u/a.jpg", "attempt": 1},
        {"id": 2, "bucket": "avatars", "path": "u/b.jpg", "attempt": 3}]


class CleanupUnitTests(unittest.TestCase):
    def test_deleted_and_already_missing_objects_are_acknowledged(self):
        server = FakeServer(JOBS, [200, 404])
        summary = media_cleanup.Cleanup("http://127.0.0.1:54321", "key", worker="w1", transport=server).once()
        self.assertEqual(summary["completed"], 2)
        self.assertEqual(summary["failed"], 0)
        self.assertEqual([f["p_error"] for f in server.finished], [None, None], "a 404 retry is a completed cleanup")
        self.assertEqual([f["p_worker"] for f in server.finished], ["w1", "w1"], "only the leasing worker finishes jobs")
        self.assertEqual(server.deleted[0], ("/storage/v1/object/visit-media", {"prefixes": ["u/a.jpg"]}))

    def test_storage_failures_are_recorded_for_backoff_not_lost(self):
        server = FakeServer(JOBS, [503, urllib.error.URLError("down")])
        summary = media_cleanup.Cleanup("http://127.0.0.1:54321", "key", worker="w1", transport=server).once()
        self.assertEqual(summary["failed"], 2)
        self.assertEqual(server.finished[0]["p_error"], "Storage delete HTTP 503")
        self.assertIn("retry", server.finished[1]["p_error"])

    def test_rpc_failure_stops_the_pass_without_deleting(self):
        server = FakeServer(JOBS, [200, 200], rpc_status=500)
        with self.assertRaises(RuntimeError):
            media_cleanup.Cleanup("http://127.0.0.1:54321", "key", transport=server).once()
        self.assertEqual(server.deleted, [])

    def test_refuses_anything_but_the_local_loopback_stack(self):
        with mock.patch.dict(os.environ, {"ROAM_API_URL": "https://example.supabase.co", "ROAM_SERVICE_ROLE_KEY": "x"}):
            with self.assertRaises(RuntimeError):
                media_cleanup.configuration()


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


@unittest.skipUnless(os.environ.get("ROAM_LIVE_CLEANUP") == "1", "live cleanup needs the local stack and ROAM_LIVE_CLEANUP=1")
class LiveCleanupTest(unittest.TestCase):
    def test_expired_orphan_object_is_really_deleted_from_storage(self):
        env = fixture_env()
        url, key = media_cleanup.configuration()
        publishable = env["ROAM_PUBLISHABLE_KEY"]
        sign_in = urllib.request.Request(url + "/auth/v1/token?grant_type=password", method="POST",
                                         data=json.dumps({"email": "maya@roam.test", "password": "roam-fixture-pass"}).encode(),
                                         headers={"apikey": publishable, "Content-Type": "application/json"})
        with urllib.request.urlopen(sign_in, timeout=20) as response:
            session = json.loads(response.read())
        token, user = session["access_token"], session["user"]["id"]
        name = f"{user}/{uuid.uuid4()}.jpg"
        upload = urllib.request.Request(url + "/storage/v1/object/visit-media/" + name, method="POST", data=b"\xff\xd8orphan\xff\xd9",
                                        headers={"apikey": publishable, "Authorization": "Bearer " + token, "Content-Type": "image/jpeg"})
        with urllib.request.urlopen(upload, timeout=20) as response:
            self.assertEqual(response.status, 200)
        self.assertEqual(psql(f"select count(*) from storage.objects where bucket_id='visit-media' and name='{name}'"), "1")
        # Only this disposable object is aged; 24 hours cannot be waited out in a test.
        psql(f"update storage.objects set created_at=now()-interval '25 hours' where bucket_id='visit-media' and name='{name}'")
        summary = None
        for _ in range(5):
            summary = media_cleanup.Cleanup(url, key).once()
            if psql(f"select count(*) from app_private.storage_cleanup where object_path='{name}' and done_at is not null") == "1":
                break
        print(json.dumps(summary))
        self.assertEqual(psql(f"select reason from app_private.storage_cleanup where object_path='{name}'"), "unregistered_upload")
        self.assertEqual(psql(f"select count(*) from app_private.storage_cleanup where object_path='{name}' and done_at is not null"), "1")
        self.assertEqual(psql(f"select count(*) from storage.objects where bucket_id='visit-media' and name='{name}'"), "0")
        download = urllib.request.Request(url + "/storage/v1/object/authenticated/visit-media/" + name,
                                          headers={"apikey": publishable, "Authorization": "Bearer " + token})
        with self.assertRaises(urllib.error.HTTPError):
            urllib.request.urlopen(download, timeout=20)


if __name__ == "__main__":
    unittest.main(verbosity=2)

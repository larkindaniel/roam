#!/usr/bin/env python3
"""Local server-owned media cleanup: durable leases, retry backoff and actual Storage deletes.

Credentials are read from the ignored fixture environment or process environment, never printed.
Usage: python3 scripts/media-cleanup.py --once | --watch --interval 60
"""
import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def configuration():
    values = {}
    path = Path(__file__).resolve().parent / ".fixture-env"
    if path.exists():
        for line in path.read_text().splitlines():
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    values.update(os.environ)
    url = values.get("ROAM_API_URL", "")
    key = values.get("ROAM_SERVICE_ROLE_KEY", "")
    parsed = urllib.parse.urlparse(url)
    local = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    hosted = (values.get("ROAM_WORKER_ENV") == "hosted"
              and url.rstrip("/") == "https://xnjzuotytfzyppubjcfi.supabase.co")
    if not (local or hosted):
        raise RuntimeError("Cleanup requires the local backend or the explicitly selected Roam hosted project.")
    if hosted and not os.environ.get("ROAM_SERVICE_ROLE_KEY"):
        raise RuntimeError("The hosted worker requires its service key from the process environment.")
    if not key:
        raise RuntimeError("Run scripts/configure-local.sh to provision the ignored server environment.")
    return url.rstrip("/"), key


class Cleanup:
    def __init__(self, url, key, worker=None, transport=None):
        self.url, self.key = url, key
        self.worker = worker or str(uuid.uuid4())
        self.transport = transport or urllib.request.urlopen

    def request(self, route, payload, method="POST"):
        request = urllib.request.Request(self.url + route, data=json.dumps(payload).encode(), method=method,
            headers={"apikey": self.key, "Authorization": "Bearer " + self.key, "Content-Type": "application/json"})
        try:
            with self.transport(request, timeout=20) as response:
                data = response.read()
                return response.status, json.loads(data) if data else None
        except urllib.error.HTTPError as error:
            # Error bodies may include operational details; do not log them or credentials.
            return error.code, None

    def rpc(self, name, payload):
        status, result = self.request("/rest/v1/rpc/" + name, payload)
        if not 200 <= status < 300:
            raise RuntimeError("Cleanup RPC failed with HTTP " + str(status))
        return result

    def once(self):
        sweep = self.rpc("sweep_media_orphans", {})
        jobs = self.rpc("claim_media_cleanup", {"p_worker": self.worker, "p_limit": 50})
        completed = failed = 0
        for job in jobs:
            message = None
            try:
                status, _ = self.request("/storage/v1/object/" + urllib.parse.quote(job["bucket"], safe=""), {"prefixes": [job["path"]]}, "DELETE")
                # An already-removed object is a successful idempotent cleanup retry.
                if not 200 <= status < 300 and status != 404:
                    message = "Storage delete HTTP " + str(status)
            except (urllib.error.URLError, TimeoutError, OSError):
                message = "Storage transport failed; retry required."
            acknowledged = self.rpc("finish_media_cleanup", {"p_job": job["id"], "p_worker": self.worker, "p_error": message})
            if acknowledged and message is None:
                completed += 1
            elif acknowledged:
                failed += 1
        return {"expired": sweep, "claimed": len(jobs), "completed": completed, "failed": failed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=int, default=60)
    args = parser.parse_args()
    if args.interval < 1:
        parser.error("interval must be positive")
    worker = Cleanup(*configuration())
    while True:
        print(json.dumps(worker.once()), flush=True)
        if not args.watch:
            return
        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, urllib.error.URLError, OSError) as error:
        raise SystemExit(str(error))

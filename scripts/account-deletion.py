#!/usr/bin/env python3
"""Local server-owned account deletion worker (R13).

One pass claims leased deletion jobs, deletes each member's relational data and auth user
(`process_account_deletion`), runs the Storage cleanup worker over the member's queued objects and
then marks each job completed once its Storage folders are empty (`refresh_account_deletion`).
A failed job is released with backoff and retried by a later pass.

Apple token revocation needs Apple server credentials and the member's Apple refresh token; this
local build has neither, so Apple accounts record `not_configured` (a release blocker), never a
claimed revocation. Credentials are read from the ignored fixture environment or the process
environment and are never printed.

Usage: python3 scripts/account-deletion.py --once | --watch --interval 60
"""
import argparse
import importlib.util
import json
import time
import urllib.error
import uuid
from pathlib import Path

_spec = importlib.util.spec_from_file_location("media_cleanup", Path(__file__).resolve().parent / "media-cleanup.py")
media_cleanup = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(media_cleanup)


class AccountDeletion:
    def __init__(self, url, key, worker=None, transport=None):
        self.worker = worker or str(uuid.uuid4())
        self.cleanup = media_cleanup.Cleanup(url, key, worker=self.worker, transport=transport)

    def rpc(self, name, payload):
        return self.cleanup.rpc(name, payload)

    @staticmethod
    def apple_revocation(job):
        # The Edge function may already have revoked Apple access. Never downgrade its result.
        state = job.get("appleRevocation")
        return state if state in {"not_applicable", "completed", "failed"} else "not_configured"

    def once(self):
        jobs = self.rpc("claim_account_deletions", {"p_worker": self.worker, "p_limit": 10})
        processed = failed = completed = 0
        waiting = []
        for job in jobs:
            try:
                status = self.rpc("process_account_deletion", {"p_job": job["id"], "p_worker": self.worker,
                                                               "p_apple_revocation": self.apple_revocation(job)})
            except (RuntimeError, urllib.error.URLError, OSError):
                # Database error details may name the member; record only that the attempt failed.
                self.rpc("fail_account_deletion", {"p_job": job["id"], "p_worker": self.worker, "p_error": "Deletion attempt failed; retrying."})
                failed += 1
                continue
            processed += 1
            if status.get("state") == "completed":
                completed += 1
            else:
                waiting.append(job["id"])
        storage = None
        still_processing = 0
        if waiting:
            storage = self.cleanup.once()
            for job_id in waiting:
                if self.rpc("refresh_account_deletion", {"p_job": job_id}).get("state") == "completed":
                    completed += 1
                else:
                    still_processing += 1
        return {"claimed": len(jobs), "processed": processed, "completed": completed, "failed": failed,
                "stillProcessing": still_processing, "storage": storage}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=int, default=60)
    args = parser.parse_args()
    if args.interval < 1:
        parser.error("interval must be positive")
    worker = AccountDeletion(*media_cleanup.configuration())
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

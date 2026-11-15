#!/usr/bin/env python3
"""Adds fictional people to the disposable LOCAL database: some have asked to be Kieran's friend, and one hasn't, so Add
friends has requests to accept and someone to add. Run after demo.py. Safe to run again. Local use only."""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("roam_fixture_setup", os.path.join(HERE, "setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

KIERAN = "00000011-0000-4000-8000-000000000001"
# (id, email, handle, name, asks Kieran to be friends)
PEOPLE = [
    ("00000012-0000-4000-8000-000000000001", "maya@roam.test", "mayaokafor", "Maya Okafor", True),
    ("00000012-0000-4000-8000-000000000002", "theo@roam.test", "theolind", "Theo Lindqvist", True),
    ("00000012-0000-4000-8000-000000000003", "priya@roam.test", "priyaraman", "Priya Raman", True),
    ("00000012-0000-4000-8000-000000000004", "sam@roam.test", "samcastillo", "Sam Castillo", False),
]


def main():
    env = setup.load_env()
    for user_id, email, handle, name, asks in PEOPLE:
        setup.ensure_user(env, user_id, email)
        token = setup.sign_in(env, email)
        status, _ = setup.request(env, "POST", "/rest/v1/rpc/create_profile", {"p_display_name": name, "p_handle": handle}, token=token)
        if status < 300:
            setup.rpc(env, token, "set_setup_checkpoint", {"p_checkpoint": "complete"})
            setup.rpc(env, token, "mark_been_intro_seen", {})
        if asks:
            # Already asked, or already friends, is fine on a rerun.
            setup.request(env, "POST", "/rest/v1/rpc/friend_action", {"p_user_id": KIERAN, "p_action": "request"}, token=token)
    print(f"{sum(p[4] for p in PEOPLE)} friend requests for Kieran, and {sum(not p[4] for p in PEOPLE)} person to add.")


if __name__ == "__main__":
    main()

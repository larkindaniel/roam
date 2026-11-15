#!/usr/bin/env python3
"""A brand-new, empty account in the disposable LOCAL database, for walking through the new-user flow: signed up, but
no profile, friends or logs yet. Running it again wipes that account and starts it fresh. Local use only.

    python3 scripts/fixtures/new_user.py

Sign in with new@roam.test and the fixture password in setup.py.
"""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("roam_fixture_setup", os.path.join(HERE, "setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

USER_ID = "00000013-0000-4000-8000-000000000001"
EMAIL = "new@roam.test"


def main():
    env = setup.load_env()
    # Start over: deleting the sign-in removes everything the account made.
    setup.request(env, "DELETE", f"/auth/v1/admin/users/{USER_ID}", admin=True)
    setup.ensure_user(env, USER_ID, EMAIL)
    print(f"Empty account ready: {EMAIL} (password in scripts/fixtures/setup.py).")


if __name__ == "__main__":
    main()

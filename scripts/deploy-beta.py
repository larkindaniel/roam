#!/usr/bin/env python3
"""Deploy the named Roam beta through Supabase's Management API, without a DB password.

Uses the explicitly approved project-scoped token in ignored .env.beta. Migration SQL and
its original CLI-compatible history entry commit together. No fixtures or seeds are deployed.
"""
import argparse
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "xnjzuotytfzyppubjcfi"


def environment():
    values = {}
    path = ROOT / ".env.beta"
    if path.exists():
        for line in path.read_text().splitlines():
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    values.update(os.environ)
    if values.get("SUPABASE_PROJECT_REF") != PROJECT:
        raise RuntimeError("The deployment target must be the approved roam-beta project.")
    if not values.get("SUPABASE_ACCESS_TOKEN"):
        raise RuntimeError("Missing project-scoped deployment token in .env.beta.")
    return values


def request(route, payload=None, method=None):
    values = environment()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT}{route}",
        data=json.dumps(payload).encode() if payload is not None else None,
        method=method or ("POST" if payload is not None else "GET"),
        headers={"Authorization": "Bearer " + values["SUPABASE_ACCESS_TOKEN"],
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        # Database messages are useful for migration failures; never print credentials.
        body = error.read().decode(errors="replace")
        body = body.replace(values["SUPABASE_ACCESS_TOKEN"], "[redacted]")
        raise RuntimeError(f"Management API HTTP {error.code}: {body[:1200]}") from None


def query(sql, read_only=False):
    return request("/database/query", {"query": sql, "read_only": read_only})


def migrations(apply=False):
    history_exists = query("select to_regclass('supabase_migrations.schema_migrations') is not null as present", True)[0]["present"]
    history = query("select version from supabase_migrations.schema_migrations order by version", True) if history_exists else []
    applied = {item["version"] for item in history}
    paths = sorted((ROOT / "supabase/migrations").glob("*.sql"))
    local = {p.name.split("_", 1)[0] for p in paths}
    if applied - local:
        raise RuntimeError("Remote history includes migrations absent locally; reconcile before deploying.")
    for path in paths:
        version, name = path.stem.split("_", 1)
        if version in applied:
            continue
        if not apply:
            print("Pending:", path.name)
            continue
        sql = path.read_text()
        # A private history table matches the CLI's version/name/statements structure.
        # Dollar quoting records the exact original SQL without modifying its content.
        marker = "$roam_migration_source$"
        if marker in sql:
            raise RuntimeError("Unexpected history quote marker in migration.")
        transaction = f"""begin;
select pg_advisory_xact_lock(hashtext('roam-beta-migrations'));
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key, statements text[], name text
);
{sql}
insert into supabase_migrations.schema_migrations(version, statements, name)
values ('{version}', array[{marker}{sql}{marker}], '{name}');
commit;"""
        query(transaction)
        print("Applied:", path.name, flush=True)
    print("Migration history checked.")


def configure_auth():
    request("/config/auth", {
        "site_url": "roam://auth-callback",
        "uri_allow_list": "roam://auth-callback,roam://auth-callback/recovery",
        "disable_signup": False,
        "mailer_autoconfirm": False,
        "password_min_length": 12,
        "mailer_otp_length": 6,
        "mailer_otp_exp": 3600,
        "external_apple_enabled": True,
        "external_apple_client_id": "com.daniellarkin.roam",
        "external_apple_skip_nonce_check": False,
        "mailer_subjects_confirmation": "Confirm your Roam account",
        "mailer_templates_confirmation_content": (ROOT / "supabase/templates/confirmation.html").read_text(),
        "mailer_subjects_recovery": "Reset your Roam password",
        "mailer_templates_recovery_content": (ROOT / "supabase/templates/recovery.html").read_text(),
    }, "PATCH")
    print("Configured beta Auth redirects, Apple audience, password policy and email templates.")


def check():
    config = (ROOT / "Config/Beta.xcconfig").read_text()
    key = next(line.split("=", 1)[1].strip() for line in config.splitlines()
               if line.startswith("ROAM_SUPABASE_PUBLISHABLE_KEY"))
    req = urllib.request.Request(f"https://{PROJECT}.supabase.co/rest/v1/rpc/roam_health",
        data=b"{}", headers={"apikey": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        print("Public health:", response.read().decode())
    for sql in (
        "select id, public, file_size_limit from storage.buckets order by id",
        "select count(*) as migrations from supabase_migrations.schema_migrations",
    ):
        print(json.dumps(query(sql, True)))
    auth = request("/config/auth")
    print(json.dumps({key: auth.get(key) for key in (
        "site_url", "uri_allow_list", "password_min_length", "mailer_otp_length",
        "external_apple_enabled", "external_apple_client_id", "external_apple_skip_nonce_check",
    )}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "migrate", "configure-auth", "check"])
    args = parser.parse_args()
    try:
        if args.action in ("plan", "migrate"):
            migrations(args.action == "migrate")
        elif args.action == "configure-auth":
            configure_auth()
        else:
            check()
    except (RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(str(error))

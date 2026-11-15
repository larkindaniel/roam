#!/usr/bin/env python3
"""Deploy the named Roam beta through Supabase's Management API, without a DB password.

Uses the explicitly approved project-scoped token in ignored .env.beta. Migration SQL and
its original CLI-compatible history entry commit together. No fixtures or seeds are deployed.

    python3 -I scripts/deploy-beta.py plan        # migrations not yet on the beta, and functions there now
    python3 -I scripts/deploy-beta.py migrate     # apply them
    python3 -I scripts/deploy-beta.py functions   # deploy every edge function in supabase/functions
    python3 -I scripts/deploy-beta.py check       # health, buckets, migrations, Auth and functions
    python3 -I scripts/deploy-beta.py deploy      # migrate, then functions, then check

Edge function secrets (GITHUB_TOKEN, GOOGLE_PLACES_KEY, ...) are set in the dashboard, never here.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
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


def local_functions():
    """Every edge function in the repo: a folder in supabase/functions with an index.ts."""
    return sorted(p.name for p in (ROOT / "supabase/functions").iterdir() if (p / "index.ts").exists())


def remote_functions():
    return {item["slug"]: item for item in request("/functions") or []}


def deploy_functions(names=None):
    """Deploys edge functions with the Supabase CLI, bundled on Supabase's side (no Docker needed)."""
    values = environment()
    cli = shutil.which("supabase") or str(Path.home() / ".local/bin/supabase")
    if not Path(cli).exists() and not shutil.which(cli):
        raise RuntimeError("The Supabase CLI isn't installed (brew install supabase/tap/supabase).")
    env = dict(os.environ, SUPABASE_ACCESS_TOKEN=values["SUPABASE_ACCESS_TOKEN"])
    for name in names or local_functions():
        result = subprocess.run([cli, "functions", "deploy", name, "--project-ref", PROJECT, "--use-api"],
                                cwd=ROOT, env=env, capture_output=True, text=True)
        output = (result.stdout + result.stderr).replace(values["SUPABASE_ACCESS_TOKEN"], "[redacted]")
        if result.returncode != 0:
            raise RuntimeError(f"Deploying {name} failed:\n{output[-1200:]}")
        print("Deployed:", name, flush=True)
    print("Functions deployed. Their secrets are set in the dashboard (Edge Functions -> Secrets).")


def print_functions():
    remote = remote_functions()
    for name in local_functions():
        item = remote.get(name)
        print(f"Function {name}: " + (f"version {item.get('version')}, {item.get('status')}" if item else "not deployed"))


def publishable_key():
    config = ROOT / "Config/Beta.xcconfig"
    if config.exists():
        return next(line.split("=", 1)[1].strip() for line in config.read_text().splitlines()
                    if line.startswith("ROAM_SUPABASE_PUBLISHABLE_KEY"))
    # Without the app's beta config, ask the project for its public client key.
    keys = request("/api-keys") or []
    key = next((k.get("api_key") for k in keys if k.get("type") == "publishable" or k.get("name") == "anon"), None)
    if not key:
        raise RuntimeError("Couldn't find the beta's publishable key (Config/Beta.xcconfig or the API).")
    return key


def check():
    key = publishable_key()
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
    print_functions()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=["plan", "migrate", "functions", "configure-auth", "check", "deploy"])
    parser.add_argument("names", nargs="*", help="functions: just these (default: all of them)")
    args = parser.parse_args()
    try:
        if args.action == "plan":
            migrations(False)
            print_functions()
        elif args.action == "migrate":
            migrations(True)
        elif args.action == "functions":
            deploy_functions(args.names)
        elif args.action == "configure-auth":
            configure_auth()
        elif args.action == "deploy":
            migrations(True)
            deploy_functions()
            check()
        else:
            check()
    except (RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(str(error))

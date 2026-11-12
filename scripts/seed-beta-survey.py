#!/usr/bin/env python3
"""Puts the recommendation survey (supabase/fixtures/beta-survey.json) on the hosted roam-beta project.

Each respondent becomes a member with their first name and bio. They can't sign in: the account has no password and an
undeliverable address under roam.invalid, so no email is stored. Their places are resolved through Apple Maps
exactly as the app does (scripts/fixtures/mapkit_lookup.swift, then the app's own resolve_place), so a seeded place is
the same place a tester finds in search. Every seeded member is made friends with the four team accounts.

    python3 -I scripts/seed-beta-survey.py lookup   # Apple Maps lookups, cached in supabase/fixtures/beta-survey-places.json
    python3 -I scripts/seed-beta-survey.py plan     # what would be written, and the SQL, without touching the project
    python3 -I scripts/seed-beta-survey.py apply    # create the members and their places; safe to run again
    python3 -I scripts/seed-beta-survey.py remove   # delete every seeded member and everything they own

Places and cities stay when members are removed: they're shared with anyone else who logged them.
"""
import datetime
import json
import random
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "xnjzuotytfzyppubjcfi"
URL = f"https://{PROJECT}.supabase.co"
SURVEY = ROOT / "supabase/fixtures/beta-survey.json"
PLACES = ROOT / "supabase/fixtures/beta-survey-places.json"
LOOKUP = ROOT / "scripts/fixtures/mapkit_lookup.swift"
TEAM_HANDLES = ("daniellarkin", "kieran", "nihal", "dhyan")
SEED_DOMAIN = "seed.roam.invalid"
NAMESPACE = uuid.UUID("5c3b0a52-6f0e-4d7b-9a51-2f1c0d6e8b11")
# Visits fall before the survey (October 6, 2026), so the dates stay put whenever this runs.
LAST_DAY = datetime.date(2026, 9, 27)
MAX_KM = 150


def uid(*parts):
    return str(uuid.uuid5(NAMESPACE, "|".join(parts)))


def spot_key(person, city, spot):
    return f"{person['key']}|{city['city']}|{spot['q']}"


def load_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


# Lookup ----------------------------------------------------------------------------------------------------------------

def run_lookup(queries):
    if not queries:
        return {}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(queries, handle)
    with open(handle.name) as stdin:
        out = subprocess.run(["swift", str(LOOKUP)], stdin=stdin, capture_output=True, text=True, check=True)
    Path(handle.name).unlink()
    for line in out.stderr.splitlines():
        if "|" in line or line.startswith("city:"):
            print("  " + line)
    return json.loads(out.stdout)


def lookup():
    survey = load_json(SURVEY)
    cache = load_json(PLACES, {"spots": {}, "cities": {}})
    city_names = set()
    for person in survey["respondents"]:
        city_names.update(person.get("homes", []) + person.get("visitedCities", []))
    missing = sorted(name for name in city_names if not cache["cities"].get(name))
    found = run_lookup([{"id": "city:" + name, "q": name, "city": name, "kind": "city"} for name in missing])
    for name in missing:
        cache["cities"][name] = found.get("city:" + name)
    # Each spot tries its search text, then its alternatives, until one is found near the city it was listed under and isn't
    # a known wrong match ("exclude").
    pending = {}
    for person in survey["respondents"]:
        for city in person["cities"]:
            for spot in city["spots"]:
                key = spot_key(person, city, spot)
                if not cache["spots"].get(key):
                    pending[key] = (spot, city)
    for attempt in range(4):
        queries = []
        for key, (spot, city) in pending.items():
            terms = [spot["q"]] + spot.get("alts", [])
            if attempt < len(terms):
                queries.append({"id": key, "q": terms[attempt], "city": spot.get("near", city["city"])})
        if not queries:
            break
        found = run_lookup(queries)
        for query in queries:
            match = found.get(query["id"])
            spot = pending[query["id"]][0]
            if match and match.pop("distanceKm", 0) <= MAX_KM and match["name"] not in spot.get("exclude", []):
                cache["spots"][query["id"]] = {"query": query["q"], "candidate": match}
                pending.pop(query["id"])
    for key in pending:
        cache["spots"][key] = None
    PLACES.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print(f"{sum(1 for v in cache['spots'].values() if v)} spots found, {len(pending)} not found:")
    for key in sorted(pending):
        print("  " + key)


# SQL -------------------------------------------------------------------------------------------------------------------

def q(value):
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def jq(value):
    return q(json.dumps(value, ensure_ascii=False)) + "::jsonb"


def fallback_category(candidate):
    """For places Apple gives no type: the same keyword guesses as the local demo seed."""
    text = f"{candidate.get('providerCategory') or ''} {candidate['name']}".lower()
    words = (
        ("stays", ("hotel", "lodge", "hostel")),
        ("nightlife", ("bar", "pub", "tavern", "rivoli", "cobblestone", "nightlife")),
        ("food_drink", ("restaurant", "cafe", "café", "coffee", "bakery", "pastr", "tea", "diner", "donut", "doughnut", "gelato",
                        "ice cream", "chocolate", "food", "kebab", "shawarma", "pizza", "soup", "thai", "sub", "noodle", "sweets")),
        ("culture", ("museum", "gallery", "temple", "church", "memorial", "monument", "art", "cemetery", "kirkeg", "bookst", "bookshop",
                     "landmark", "-ji", "-in", "-an", "castle")),
        ("outdoors", ("park", "garden", "have", "hiking", "trail", "peak", "pico", "beach", "praia", "strand", "island", "pulau",
                      "valley", "drive", "lake", "lago", "falls", "catarat", "conservancy", "waterfall", "pond", "farm", "walk", "cliff", "point")),
    )
    for category, keys in words:
        if any(k in text for k in keys):
            return category
    return "activities"


def destination(cache, name):
    found = cache["cities"].get(name)
    if not found:
        raise SystemExit(f"No Apple Maps city for {name!r}; run lookup again or fix beta-survey.json.")
    return found


def build(survey, cache):
    """Returns the SQL and a short summary. Every id is derived from the survey, so running it again changes nothing."""
    people, spots, trips, cities_visited = [], [], [], []
    for person in survey["respondents"]:
        member = uid("member", person["key"])
        rng = random.Random(person["key"])
        homes = set(person.get("homes", []))
        people.append(dict(id=member, handle=person["key"], name=person["name"], bio=person["bio"],
                           homes=[destination(cache, h) for h in person.get("homes", [])]))
        # Trips run back from late September 2026, one per city (or per group of cities that share a "trip").
        day = LAST_DAY - datetime.timedelta(days=rng.randint(0, 30))
        groups = {}
        for city in person["cities"]:
            if city["city"] not in homes:
                groups.setdefault(city.get("trip", city["city"].split(",")[0].strip()), []).append(city["city"])
        trip_of, trip_days = {}, {}
        for name, members in groups.items():
            length = rng.randint(3, 8)
            end, start = day, day - datetime.timedelta(days=length - 1)
            trip = uid("trip", person["key"], name)
            trips.append(dict(id=trip, owner=member, name=name, start=start, end=end))
            for c in members:
                trip_of[c], trip_days[c] = trip, (start, end)
            day = start - datetime.timedelta(days=rng.randint(25, 110))
        for visited in person.get("visitedCities", []):
            day = day - datetime.timedelta(days=rng.randint(30, 120))
            cities_visited.append(dict(owner=member, city=destination(cache, visited), date=day))
        for city in person["cities"]:
            for spot in city["spots"]:
                found = cache["spots"].get(spot_key(person, city, spot))
                if not found:
                    continue
                if city["city"] in trip_of:
                    start, end = trip_days[city["city"]]
                    date = start + datetime.timedelta(days=rng.randint(0, (end - start).days))
                else:
                    date = LAST_DAY - datetime.timedelta(days=rng.randint(0, 330))
                candidate = found["candidate"]
                spots.append(dict(owner=member, key=spot_key(person, city, spot), candidate=candidate,
                                  fallback=candidate.get("suggestedCategory") or fallback_category(candidate),
                                  rating=spot.get("rating"), note=spot.get("note", ""), date=date,
                                  trip=trip_of.get(city["city"]), visit=uid("visit", spot_key(person, city, spot)),
                                  rating_id=uid("rating", spot_key(person, city, spot))))
    rows = ["begin;",
            "create temp table seed_people(id uuid, handle text, name text, bio text, homes jsonb) on commit drop;",
            "create temp table seed_spots(owner uuid, key text, candidate jsonb, fallback text, rating numeric, note text, visit_date date,"
            " trip uuid, visit uuid, rating_id uuid, experience uuid, category public.experience_category) on commit drop;"]
    for p in people:
        rows.append(f"insert into seed_people values ({q(p['id'])}, {q(p['handle'])}, {q(p['name'])}, {q(p['bio'])}, {jq(p['homes'])});")
    for s in spots:
        rows.append(f"insert into seed_spots values ({q(s['owner'])}, {q(s['key'])}, {jq(s['candidate'])}, {q(s['fallback'])}, "
                    f"{s['rating'] if s['rating'] is not None else 'null'}, {q(s['note'])}, {q(s['date'].isoformat())}, {q(s['trip'])}, "
                    f"{q(s['visit'])}, {q(s['rating_id'])}, null, null);")
    # Profiles, homes and places go through the app's own RPCs, acting as each member.
    rows.append("""do $$
declare p record; s record; h jsonb;
begin
  for p in select * from seed_people loop
    perform set_config('request.jwt.claims', json_build_object('sub', p.id, 'role', 'authenticated')::text, true);
    perform public.create_profile(p.name, p.handle);
    update public.profiles set bio = p.bio, setup_checkpoint = 'complete', has_seen_been_intro = true where id = p.id;
    for h in select value from jsonb_array_elements(p.homes) loop
      perform public.set_home_city(h, true);
    end loop;
  end loop;
  for s in select * from seed_spots loop
    perform set_config('request.jwt.claims', json_build_object('sub', s.owner, 'role', 'authenticated')::text, true);
    update seed_spots set experience = (public.resolve_place(s.candidate) ->> 'id')::uuid where key = s.key;
  end loop;
  perform set_config('request.jwt.claims', '', true);
end $$;""")
    rows.append("""update public.experiences e set category = s.fallback::public.experience_category
from seed_spots s where e.id = s.experience and e.category is null;
update seed_spots s set category = e.category from public.experiences e where e.id = s.experience;
-- Two survey entries can land on the same place; keep each member's first.
delete from seed_spots a using seed_spots b where a.owner = b.owner and a.experience = b.experience and a.key > b.key;""")
    for c in cities_visited:
        d = c["city"]
        rows.append(f"""insert into public.visited_cities (owner_id, city_id, start_date, end_date)
values ({q(c['owner'])}, app_private.upsert_city({q(d.get('countryCode'))}, {q(d.get('countryName'))}, {q(d.get('region'))}, {q(d['name'])}, {d['latitude']}, {d['longitude']}),
 {q(c['date'].isoformat())}, {q(c['date'].isoformat())}) on conflict do nothing;""")
    for t in trips:
        rows.append(f"insert into public.trips (id, owner_id, name, status, start_date, end_date) values ({q(t['id'])}, {q(t['owner'])}, "
                    f"{q(t['name'])}, 'past', {q(t['start'].isoformat())}, {q(t['end'].isoformat())}) on conflict do nothing;")
    # A trip's cities are the ones its places are in, most places first: the same cities the app groups them by.
    # Apple can spell one city's region two ways, which makes two cities of the same name: a trip keeps one of them.
    rows.append("""insert into public.trip_cities (trip_id, city_id, position)
select trip, city_id, (row_number() over (partition by trip order by places desc, first_visit) - 1)::int
from (select distinct on (s.trip, c.name) s.trip, c.id city_id, count(*) over (partition by s.trip, c.name) places,
             min(s.visit_date) over (partition by s.trip, c.name) first_visit
      from seed_spots s join public.experiences e on e.id = s.experience join public.places p on p.id = e.place_id
      join public.cities c on c.id = p.city_id
      where s.trip is not null
      order by s.trip, c.name, (select count(*) from seed_spots x join public.experiences xe on xe.id = x.experience
                                join public.places xp on xp.id = xe.place_id where x.trip = s.trip and xp.city_id = c.id) desc) t
on conflict do nothing;
delete from public.trips t where t.id in (select trip from seed_spots) and not exists (select 1 from public.trip_cities c where c.trip_id = t.id);""")
    # Visits are public and dated, so they show on friends' Friends tabs, ordered by when they happened.
    rows.append("""insert into public.visits (id, owner_id, experience_id, visit_date, date_precision, public_note, audience, trip_id, source_operation_id, created_at, updated_at)
select visit, owner, experience, visit_date, 'day', coalesce(note, ''), 'public', trip, visit, visit_date + time '18:00', visit_date + time '18:00'
from seed_spots on conflict (id) do nothing;
-- Scores keep the survey's 1-10; ranks follow them within each member's category, as in the local demo seed.
with rated as (
  select s.*, case when rating >= 7 then 'liked' when rating >= 4 then 'fine' else 'disliked' end::public.sentiment sentiment
  from seed_spots s where rating is not null
), ranked as (
  select r.*, rank() over (partition by owner, category order by rating desc) competition,
         dense_rank() over (partition by owner, category, sentiment order by rating desc) - 1 position
  from rated r
)
insert into public.ratings (id, owner_id, experience_id, category, sentiment, group_position, score, rank, audience, first_rated_at, updated_at)
select rating_id, owner, experience, category, sentiment, position, rating, competition, 'public', visit_date + time '18:00', visit_date + time '18:00'
from ranked on conflict (owner_id, experience_id) do nothing;
insert into public.activities (author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, published_at, source_operation_id)
select s.owner, case when r.id is null then 'revisit' else 'rating' end::public.activity_type, s.experience, s.visit, r.id, s.category,
       r.score, r.rank, r.sentiment, s.visit_date + time '18:00', s.visit
from seed_spots s left join public.ratings r on r.id = s.rating_id
on conflict (author_id, source_operation_id) do nothing;""")
    rows.append(f"""select app_private.make_friends(t.id, p.id) from public.profiles t cross join seed_people p
where t.handle in ({', '.join(q(h) for h in TEAM_HANDLES)}) and not app_private.are_friends(t.id, p.id);""")
    rows.append("select (select count(*) from seed_people) members, (select count(*) from seed_spots) places, "
                "(select count(*) from seed_spots where rating is not null) rated;")
    rows.append("commit;")
    summary = dict(members=len(people), places=len(spots), rated=sum(1 for s in spots if s["rating"] is not None),
                   trips=len(trips), visited_cities=len(cities_visited))
    return "\n".join(rows), people, summary


# Hosted project --------------------------------------------------------------------------------------------------------

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
                                 headers={"Content-Type": "application/json", "User-Agent": "roam-seed", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body or b"null")
        except ValueError:
            return e.code, body.decode(errors="replace")


class Project:
    def __init__(self):
        beta = env_file(ROOT / ".env.beta")
        if beta.get("SUPABASE_PROJECT_REF") != PROJECT:
            raise SystemExit("The target must be the approved roam-beta project (.env.beta).")
        self.token = beta["SUPABASE_ACCESS_TOKEN"]
        status, keys = call(f"https://api.supabase.com/v1/projects/{PROJECT}/api-keys?reveal=true", headers=self.management)
        if status != 200:
            raise SystemExit(f"Could not read project API keys (HTTP {status}).")
        secret = next((k["api_key"] for k in keys if k.get("type") == "secret" and (k.get("api_key") or "").startswith("sb_secret_")), None)
        self.service = secret or next(k["api_key"] for k in keys if k.get("name") == "service_role")

    @property
    def management(self):
        return {"Authorization": "Bearer " + self.token}

    @property
    def admin(self):
        return {"apikey": self.service, "Authorization": "Bearer " + self.service}

    def sql(self, text, read_only=False):
        status, body = call(f"https://api.supabase.com/v1/projects/{PROJECT}/database/query", {"query": text, "read_only": read_only},
                            self.management)
        if status not in (200, 201):
            raise SystemExit(f"SQL failed (HTTP {status}): {body}")
        return body

    def ensure_user(self, member):
        email = f"{member['handle']}@{SEED_DOMAIN}"
        status, body = call(f"{URL}/auth/v1/admin/users/{member['id']}", headers=self.admin)
        if status == 200:
            return False
        status, body = call(f"{URL}/auth/v1/admin/users", {"id": member["id"], "email": email, "email_confirm": True,
                                                           "app_metadata": {"roam_seed": "beta-survey"}}, self.admin)
        if status not in (200, 201):
            raise SystemExit(f"Could not create {email} (HTTP {status}): {body}")
        return True


def taken_handles(project, people):
    rows = project.sql("select p.handle from public.profiles p join auth.users u on u.id = p.id "
                       f"where p.handle in ({', '.join(q(p['handle']) for p in people)}) "
                       "and coalesce(u.raw_app_meta_data ->> 'roam_seed', '') <> 'beta-survey'", True)
    return [r["handle"] for r in rows]


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "plan"
    if command == "lookup":
        return lookup()
    survey, cache = load_json(SURVEY), load_json(PLACES)
    if cache is None:
        raise SystemExit("Run lookup first.")
    sql, people, summary = build(survey, cache)
    if command == "plan":
        out = Path(tempfile.gettempdir()) / "roam-beta-survey.sql"
        out.write_text(sql)
        print(json.dumps(summary), f"\nSQL written to {out}")
        return
    project = Project()
    if command == "apply":
        clash = taken_handles(project, people)
        if clash:
            raise SystemExit(f"Real members already use these handles: {', '.join(clash)}. Rename them in beta-survey.json.")
        created = sum(project.ensure_user(member) for member in people)
        print(f"Created {created} sign-in-less accounts ({len(people) - created} already there).")
        print(json.dumps(project.sql(sql)))
    elif command == "remove":
        rows = project.sql("select id from auth.users where raw_app_meta_data ->> 'roam_seed' = 'beta-survey'", True)
        for row in rows:
            status, body = call(f"{URL}/auth/v1/admin/users/{row['id']}", headers=project.admin, method="DELETE")
            if status not in (200, 204):
                raise SystemExit(f"Could not delete {row['id']} (HTTP {status}): {body}")
        print(f"Removed {len(rows)} seeded members and everything they owned.")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()

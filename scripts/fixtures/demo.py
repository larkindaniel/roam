#!/usr/bin/env python3
"""Loads the demo dataset into the disposable LOCAL database. Run it after `supabase db reset --local`, in
place of setup.py: the automated tests need setup.py's accounts instead.

Places, scores and notes come from the real recommendation survey in supabase/fixtures/demo-places.json. The
contributors' names are not stored; their entries are attributed to the four team accounts. Local use only."""
import hashlib
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("roam_fixture_setup", os.path.join(HERE, "setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
ROOT = setup.ROOT

TEAM = [
    ("00000011-0000-4000-8000-000000000001", "kieran@roam.test", "kieranhulsman", "Kieran Hulsman"),
    ("00000011-0000-4000-8000-000000000002", "dhyan@roam.test", "dhyanpatel", "Dhyan Patel"),
    ("00000011-0000-4000-8000-000000000003", "nihal@roam.test", "nihalmenon", "Nihal Menon"),
    ("00000011-0000-4000-8000-000000000004", "daniel@roam.test", "daniellarkin", "Daniel Larkin"),
]
# Kieran is the signed-in demo account, so most entries belong to the friends Kieran sees.
OWNER_CYCLE = [1, 2, 3, 1, 2, 3, 0]
HOME_CITIES = {"Toronto", "Waterloo", "Kitchener", "Whitby", "St. Catharines"}
COUNTRY_CODES = {"Canada": "CA", "USA": "US", "Japan": "JP", "Spain": "ES", "Portugal": "PT", "United Kingdom": "GB", "Costa Rica": "CR",
                 "Iceland": "IS", "Singapore": "SG", "Denmark": "DK", "Colombia": "CO", "Switzerland": "CH", "Austria": "AT", "Ecuador": "EC", "Guatemala": "GT"}


def category(kind, name):
    text = f"{kind or ''} {name}".lower()
    if any(w in text for w in ("hotel", "farmstay", "lodge")): return "stays"
    if any(w in text for w in ("bar", "pub", "tavern", "live music", "rivoli")): return "nightlife"
    if any(w in text for w in ("restaurant", "cafe", "café", "coffee", "bakery", "pastry", "tea", "diner", "donut", "gelato", "ice cream",
                               "chocolate", "food", "kebab", "shawarma")): return "food_drink"
    if any(w in text for w in ("museum", "gallery", "temple", "memorial", "art ", "cemetery", "attraction", "building")): return "culture"
    if any(w in text for w in ("park", "garden", "hiking", "peak", "beach", "island", "scenic", "observation", "farm", "mono", "hackney", "kingston")): return "outdoors"
    return "activities"


def q(value):
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def uid(prefix, *parts):
    digest = hashlib.md5("|".join(parts).encode()).hexdigest()
    return f"{prefix}-{digest[:4]}-4{digest[5:8]}-8{digest[9:12]}-{digest[12:24]}"


def sql_for(data):
    rows, entries, trips = ["begin;"], [], {}
    for city_index, city in enumerate(data["cities"]):
        code = COUNTRY_CODES[city["country"]]
        for spot_index, spot in enumerate(city["spots"]):
            place, experience = uid("00000021", spot["id"]), uid("00000031", spot["id"])
            kind = category(spot["type"], spot["name"])
            rows.append(f"""insert into public.places (id, provider, provider_place_id, name, normalized_name, address, normalized_address, locality, country_code, country_name, city_id, latitude, longitude, provider_category, is_locality, provenance, photo_url, photo_credit)
values ({q(place)}, 'fixture', {q('demo-' + spot['id'])}, {q(spot['name'])}, app_private.normalize_text({q(spot['name'])}), {q(spot['address'])}, nullif(app_private.normalize_text({q(spot['address'])}), ''), {q(city['name'])},
 app_private.upsert_country({q(code)}, {q(city['country'])}), {q(city['country'])}, app_private.upsert_city({q(code)}, {q(city['country'])}, null, {q(city['name'])}, {city['lat']}, {city['lng']}),
 {spot['lat']}, {spot['lng']}, {q(spot['type'])}, false, '{{}}'::jsonb, {q(spot['photo'])}, {q(spot['photoAuthor'])});""")
            rows.append(f"insert into public.experiences (id, place_id, category, category_source) values ({q(experience)}, {q(place)}, '{kind}', 'suggested');")
            owner = TEAM[OWNER_CYCLE[spot["contributor"] % len(OWNER_CYCLE)]][0]
            trip = None
            if city["name"] not in HOME_CITIES:
                trip = uid("00000051", owner, city["slug"])
                trips[trip] = (owner, city["name"])
            entries.append(dict(owner=owner, spot=spot, experience=experience, kind=kind, trip=trip, order=city_index * 40 + spot_index))
    for trip, (owner, name) in trips.items():
        rows.append(f"insert into public.trips (id, owner_id, name, status) values ({q(trip)}, {q(owner)}, {q(name)}, 'past');")
    for entry in entries:
        days = entry["order"] % 200 + 1
        visit = uid("00000041", entry["owner"], entry["spot"]["id"])
        rows.append(f"""insert into public.visits (id, owner_id, experience_id, visit_date, date_precision, public_note, audience, trip_id, source_operation_id, created_at)
values ({q(visit)}, {q(entry['owner'])}, {q(entry['experience'])}, current_date - {days}, 'day', {q(entry['spot']['note'] or '')}, 'public', {q(entry['trip'])}, {q(visit)}, now() - interval '{days} days');""")
    groups = {}
    for entry in entries:
        rating = entry["spot"]["rating"]
        if rating is not None:
            groups.setdefault((entry["owner"], entry["kind"]), []).append(entry)
    for (owner, kind), group in groups.items():
        # Scores keep the survey's numbers; ranks follow them within each person's category.
        group.sort(key=lambda e: -e["spot"]["rating"])
        for rank, entry in enumerate(group, 1):
            rating = entry["spot"]["rating"]
            sentiment = "liked" if rating >= 7 else ("fine" if rating >= 4 else "disliked")
            same = [e for e in group if ("liked" if e["spot"]["rating"] >= 7 else ("fine" if e["spot"]["rating"] >= 4 else "disliked")) == sentiment]
            position = sorted({e["spot"]["rating"] for e in same}, reverse=True).index(rating)
            competition = 1 + sum(1 for e in group if e["spot"]["rating"] > rating)
            visit = uid("00000041", owner, entry["spot"]["id"])
            rating_id = uid("00000061", owner, entry["spot"]["id"])
            rows.append(f"""insert into public.ratings (id, owner_id, experience_id, category, sentiment, group_position, score, rank, audience)
values ({q(rating_id)}, {q(owner)}, {q(entry['experience'])}, '{kind}', '{sentiment}', {position}, {float(rating)}, {competition}, 'public');
insert into public.activities (author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, published_at, source_operation_id)
select owner_id, 'revisit', experience_id, id, {q(rating_id)}, '{kind}', {float(rating)}, {competition}, '{sentiment}', created_at, id from public.visits where id = {q(visit)};""")
    for entry in entries:
        if entry["spot"]["rating"] is None:
            visit = uid("00000041", entry["owner"], entry["spot"]["id"])
            rows.append(f"""insert into public.activities (author_id, type, experience_id, visit_id, category, published_at, source_operation_id)
select owner_id, 'revisit', experience_id, id, '{entry['kind']}', created_at, id from public.visits where id = {q(visit)};""")
    rows.append("commit;")
    return "\n".join(rows)


def plans_sql(data):
    """Gives Kieran upcoming trips and a wishlist in countries they haven't been to. Safe to run twice."""
    kieran = TEAM[0][0]
    spots = {city["name"]: city["spots"] for city in data["cities"]}
    rows = ["begin;"]
    for name, status, start, end in (("Tokyo", "upcoming", 60, 74), ("Lisbon", "planning", None, None)):
        trip = uid("00000052", kieran, name)
        dates = [f"current_date + {day}" if day is not None else "null" for day in (start, end)]
        rows.append(f"insert into public.trips (id, owner_id, name, status, start_date, end_date) values ({q(trip)}, {q(kieran)}, {q(name)}, '{status}', {dates[0]}, {dates[1]}) on conflict do nothing;")
        for position, spot in enumerate(spots[name]):
            rows.append(f"insert into public.trip_places (trip_id, experience_id, position) values ({q(trip)}, {q(uid('00000031', spot['id']))}, {position}) on conflict do nothing;")
    for name in ("Reykjavík", "Copenhagen", "Medellín", "Lausanne"):
        for spot in spots[name]:
            rows.append(f"insert into public.bookmarks (owner_id, experience_id) values ({q(kieran)}, {q(uid('00000031', spot['id']))}) on conflict do nothing;")
    rows.append("commit;")
    return "\n".join(rows)


def main():
    env = setup.load_env()
    tokens = {}
    for user_id, email, handle, name in TEAM:
        setup.ensure_user(env, user_id, email)
        token = setup.sign_in(env, email)
        tokens[user_id] = token
        setup.rpc(env, token, "create_profile", {"p_display_name": name, "p_handle": handle})
        setup.rpc(env, token, "set_setup_checkpoint", {"p_checkpoint": "complete"})
        setup.rpc(env, token, "mark_been_intro_seen", {})
    ids = [member[0] for member in TEAM]
    for index, first in enumerate(ids):
        for second in ids[index + 1:]:
            setup.rpc(env, tokens[first], "friend_action", {"p_user_id": second, "p_action": "request"})
            setup.rpc(env, tokens[second], "friend_action", {"p_user_id": first, "p_action": "accept"})
    with open(os.path.join(ROOT, "supabase", "fixtures", "demo-places.json"), encoding="utf-8") as handle:
        data = json.load(handle)
    sql = sql_for(data) + "\n" + plans_sql(data)
    path = os.path.join(os.environ.get("TMPDIR", "/tmp"), "roam-demo.sql")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(sql)
    setup.run_sql(path)
    os.remove(path)
    print("Demo ready. Sign in as kieran@roam.test (password in scripts/fixtures/setup.py).")


if __name__ == "__main__":
    main()

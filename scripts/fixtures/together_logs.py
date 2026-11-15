#!/usr/bin/env python3
"""Friends who went somewhere together, in the disposable LOCAL database: Dhyan, Daniel and Nihal each log a few of the
same places and tag each other with "With", so the Friends tab merges them into one card. Run after demo.py (and
friend_photos.py, for the photos). Safe to run again. Local use only."""
import subprocess
import sys

TEAM = {"daniellarkin": "00000011-0000-4000-8000-000000000004", "dhyanpatel": "00000011-0000-4000-8000-000000000002",
        "nihalmenon": "00000011-0000-4000-8000-000000000003"}
# The note on the log that's already there: the merged card shows it (the newest log's), so it gets a long one and one
# with two lines, to show the first line and its "…".
NOTES = {
    ("daniellarkin", "Park Necessidades"): "Sunset from the top was unreal\nThen pastries at the bottom with the boys",
    ("daniellarkin", "Landmannalaugar"): "Worth every hour of the drive. Hiked the rhyolite hills all day and soaked in the hot spring after",
}
# (whose log is already there, the place) -> the friends who went too, each with a new log id and note.
TRIPS = {
    ("daniellarkin", "Park Necessidades"): [("dhyanpatel", "00000044-0000-4000-8000-000000000001", "Sunset from the top was unreal"),
                                            ("nihalmenon", "00000044-0000-4000-8000-000000000002", "")],
    ("dhyanpatel", "Kongobu-ji Danjo Garan (Elevated Precinct)"): [("daniellarkin", "00000044-0000-4000-8000-000000000003", "")],
    ("daniellarkin", "Landmannalaugar"): [("nihalmenon", "00000044-0000-4000-8000-000000000004", "Worth every hour of the drive")],
}


def q(text):
    return "'" + text.replace("'", "''") + "'"


def main():
    statements = ["begin;", "delete from public.visits where id::text like '00000044-%';"]
    for (owner, place), friends in TRIPS.items():
        original = f"""(select v.id from public.visits v join public.profiles pr on pr.id = v.owner_id
            join public.experiences e on e.id = v.experience_id join public.places p on p.id = e.place_id
            where pr.handle = {q(owner)} and p.name = {q(place)} and v.visit_date is not null order by v.created_at desc limit 1)"""
        if (owner, place) in NOTES:
            statements.append(f"update public.visits set public_note = {q(NOTES[(owner, place)])} where id = {original};")
        for handle, visit_id, note in friends:
            # The same place, day and audience, logged a moment before the original (so the original is the card).
            statements.append(f"""insert into public.visits (id, owner_id, experience_id, visit_date, date_precision, public_note, audience, created_at, updated_at)
select {q(visit_id)}, {q(TEAM[handle])}, o.experience_id, o.visit_date, 'day', {q(note)}, o.audience, o.created_at - interval '1 second', now()
from public.visits o where o.id = {original};""")
        # Everyone on the trip tags everyone else.
        ids = [original] + [q(f[1]) + "::uuid" for f in friends]
        people = [TEAM[owner]] + [TEAM[f[0]] for f in friends]
        for visit in ids:
            statements.append(f"delete from public.visit_companions where visit_id = {visit};")
        for visit, me in zip(ids, people):
            for other in people:
                if other != me:
                    statements.append(f"insert into public.visit_companions (visit_id, member_id) values ({visit}, {q(other)}) on conflict do nothing;")
    statements.append("commit;")
    result = subprocess.run(["docker", "exec", "-i", "supabase_db_roam", "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
                            input="\n".join(statements).encode(), capture_output=True)
    if result.returncode != 0:
        sys.exit("Adding logs together failed:\n" + result.stderr.decode())
    print(f"{len(TRIPS)} places logged together by Dhyan, Daniel and Nihal.")


if __name__ == "__main__":
    main()

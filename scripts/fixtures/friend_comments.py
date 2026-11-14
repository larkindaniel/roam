#!/usr/bin/env python3
"""Adds a few comments between the team accounts on friends' logs in the disposable LOCAL database, so the comments
sheet has conversations to show. Safe to run again (it replaces the comments it added). Local use only."""
import subprocess
import sys

# (log owner's handle, place name) -> [(commenter's handle, words)], oldest first.
COMMENTS = {
    ("daniellarkin", "Kopar"): [
        ("kieranhulsman", "The horns are a whole look"),
        ("nihalmenon", "Did you actually eat there or just take photos outside"),
        ("daniellarkin", "Both. Langoustine soup was unreal"),
    ],
    ("dhyanpatel", "Kongobu-ji Danjo Garan (Elevated Precinct)"): [
        ("daniellarkin", "Adding this to the Japan trip"),
        ("kieranhulsman", "Go early, it gets busy by ten"),
    ],
    ("dhyanpatel", "Alforat Iraqi Street Food (Toronto)"): [
        ("nihalmenon", "We need to go this week"),
    ],
    ("daniellarkin", "Park Necessidades"): [
        ("dhyanpatel", "Best view in Lisbon honestly"),
        ("kieranhulsman", "Saving this"),
        ("nihalmenon", "Was it worth the walk up?"),
        ("daniellarkin", "Every step"),
    ],
}


def q(text):
    return "'" + text.replace("'", "''") + "'"


def main():
    rows = ["begin;", "delete from public.comments where operation_id::text like '00000077-%';"]
    n = 0
    for (owner, place), thread in COMMENTS.items():
        for minutes, (author, body) in enumerate(thread):
            n += 1
            rows.append(f"""insert into public.comments (visit_id, author_id, body, operation_id, created_at)
select v.id, a.id, {q(body)}, '00000077-0000-4000-8000-{n:012d}', now() - interval '{(len(thread) - minutes) * 37} minutes'
from public.visits v join public.profiles o on o.id = v.owner_id join public.experiences e on e.id = v.experience_id
join public.places p on p.id = e.place_id join public.profiles a on a.handle = {q(author)}
where o.handle = {q(owner)} and p.name = {q(place)} order by v.created_at desc limit 1;""")
    rows.append("commit;")
    result = subprocess.run(["docker", "exec", "-i", "supabase_db_roam", "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
                            input="\n".join(rows).encode(), capture_output=True)
    if result.returncode != 0:
        sys.exit("Adding comments failed:\n" + result.stderr.decode())
    print(f"{n} comments on {len(COMMENTS)} logs.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Attaches real trip photos to some of the demo friends' logs in the disposable LOCAL database, so the Friends tab has
logs with no photos, one photo and several. The photos aren't in the repo; pass the folder they're in.

    python3 scripts/fixtures/friend_photos.py path/to/photos

Some photos go on the log of the place they were taken at; the rest fill logs near the top of the feed. Metadata is stripped. Safe to run again. Local use only.
"""
import hashlib
import importlib.util
import io
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("roam_fixture_setup", os.path.join(HERE, "setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

# (owner's handle, place name) -> photo files, in order.
PHOTOS = {
    ("daniellarkin", "Museu Nacional d'Art de Catalunya"): ["12.jpg"],
    ("daniellarkin", "Wasteland"): ["2.jpg", "16.jpg", "3.jpg"],
    ("daniellarkin", "Bastard Café"): ["4.jpg"],
    ("daniellarkin", "Plage du Pélican"): ["7.jpg", "19.jpg"],
    # The rest go on logs near the top of the Friends tab, so photos show straight away: some one, some several, some
    # none in between.
    ("dhyanpatel", "Alforat Iraqi Street Food (Toronto)"): ["21.jpg"],
    ("dhyanpatel", "Kongobu-ji Danjo Garan (Elevated Precinct)"): ["14.jpg", "15.jpg"],
    ("daniellarkin", "Kopar"): ["20.jpg"],
    ("daniellarkin", "Landmannalaugar"): ["5.jpg", "13.jpg"],
    ("daniellarkin", "Park Necessidades"): ["10.jpg", "18.jpg", "9.jpg"],
    ("dhyanpatel", "Okuno-in Cemetery"): ["11.jpg"],
    ("dhyanpatel", "Parque Juan Carlos I"): ["6.jpg", "8.jpg"],
}


def jpeg(path):
    """Up to 1600 pixels on the long side, re-encoded with no metadata."""
    from PIL import Image
    image = Image.open(path).convert("RGB")
    image.thumbnail((1600, 1600))
    out = io.BytesIO()
    image.save(out, "JPEG", quality=85)
    return out.getvalue(), image.width, image.height


def q(text):
    return "'" + text.replace("'", "''") + "'"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = sys.argv[1]
    env = setup.load_env()
    statements = ["begin;", "delete from public.media where object_path like 'fixture/friend-%';"]
    for (handle, place), files in PHOTOS.items():
        for position, name in enumerate(files):
            data, width, height = jpeg(os.path.join(folder, name))
            object_path = f"fixture/friend-{handle}-{name}"
            upload = urllib.request.Request(f"{env['ROAM_API_URL']}/storage/v1/object/visit-media/{object_path}", data=data, method="POST", headers={
                "Authorization": "Bearer " + env["ROAM_SERVICE_ROLE_KEY"], "apikey": env["ROAM_SERVICE_ROLE_KEY"],
                "Content-Type": "image/jpeg", "x-upsert": "true"})
            urllib.request.urlopen(upload, timeout=30).read()
            statements.append(f"""insert into public.media (owner_id, purpose, visit_id, bucket, object_path, position, state, byte_size, width, height, attached_at, inspected_at, content_sha256)
select v.owner_id, 'visit', v.id, 'visit-media', {q(object_path)}, {position}, 'attached', {len(data)}, {width}, {height}, now(), now(), {q(hashlib.sha256(data).hexdigest())}
from public.visits v join public.profiles pr on pr.id = v.owner_id join public.experiences e on e.id = v.experience_id join public.places p on p.id = e.place_id
where pr.handle = {q(handle)} and p.name = {q(place)} order by v.created_at desc limit 1;""")
    statements.append("commit;")
    result = subprocess.run(["docker", "exec", "-i", "supabase_db_roam", "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
                            input="\n".join(statements).encode(), capture_output=True)
    if result.returncode != 0:
        sys.exit("Attaching photos failed:\n" + result.stderr.decode())
    print(f"{sum(len(f) for f in PHOTOS.values())} photos on {len(PHOTOS)} logs.")


if __name__ == "__main__":
    main()

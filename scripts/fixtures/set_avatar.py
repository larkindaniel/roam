#!/usr/bin/env python3
"""Sets a fixture account's profile picture in the disposable LOCAL database, the same way the app does: upload to the
avatars bucket, let prepare-media check it, then save the path on the profile. Local use only.

    python3 scripts/fixtures/set_avatar.py kieran@roam.test path/to/photo.jpg
"""
import hashlib
import importlib.util
import io
import os
import sys
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("roam_fixture_setup", os.path.join(HERE, "setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def as_square_jpeg(path):
    """A 600-pixel square JPEG cropped from the middle, with no metadata (the upload check refuses location data)."""
    from PIL import Image
    image = Image.open(path).convert("RGB")
    side = min(image.size)
    left, top = (image.width - side) // 2, (image.height - side) // 2
    image = image.crop((left, top, left + side, top + side)).resize((600, 600))
    out = io.BytesIO()
    image.save(out, "JPEG", quality=88)
    return out.getvalue()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    email, image = sys.argv[1], sys.argv[2]
    env = setup.load_env()
    token = setup.sign_in(env, email)
    profile = setup.rpc(env, token, "my_profile", {})
    data = as_square_jpeg(image)
    attempt = str(uuid.uuid4())
    path = f"{profile['id'].lower()}/{attempt}.jpg"
    upload = urllib.request.Request(f"{env['ROAM_API_URL']}/storage/v1/object/avatars/{path}", data=data, method="POST", headers={
        "apikey": env["ROAM_PUBLISHABLE_KEY"], "Authorization": "Bearer " + token, "Content-Type": "image/jpeg", "x-upsert": "false"})
    with urllib.request.urlopen(upload, timeout=30):
        pass
    status, staged = setup.request(env, "POST", "/functions/v1/prepare-media", {
        "uploadAttemptID": attempt, "purpose": "avatar", "sha256": hashlib.sha256(data).hexdigest()}, token=token)
    if status >= 300:
        sys.exit(f"prepare-media failed: HTTP {status} {staged}")
    setup.rpc(env, token, "update_profile", {
        "p_display_name": profile["displayName"], "p_handle": profile["handle"], "p_bio": profile.get("bio", ""),
        "p_home_city": profile.get("homeCity"), "p_avatar_path": staged["path"]})
    print(f"{profile['displayName']}'s profile picture is set.")


if __name__ == "__main__":
    main()

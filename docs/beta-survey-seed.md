# Survey seed on the hosted beta

Loaded onto `roam-beta` (`xnjzuotytfzyppubjcfi`) on November 12, 2026, so TestFlight builds open onto a real
friend network.

- **Who:** 25 survey respondents (October 6–22, 2026), each a member with the first name and bio they typed (bios
  shortened to 160 characters). Six who left their name blank have a made-up first name: Maya, Theo, Arjun, Elena, Luc
  and Noah. Daniel and Nihal already have real accounts, so their answers aren't included.
- **No emails and no sign-in:** each account's address is `<handle>@seed.roam.invalid`, with no password. Seeded
  accounts carry `app_metadata.roam_seed = "beta-survey"`.
- **Friends:** every seeded member is friends with `daniellarkin`, `kieran`, `nihal` and `dhyan`. Nobody else is
  affected; new testers see them only after adding them as friends.
- **Places:** 126 of 134 recommendations were found in Apple Maps (`scripts/fixtures/mapkit_lookup.swift`) and created
  through `resolve_place`, so they're the same places people find in search. Visits are public, dated before the
  survey (November 2025 to September 2026), grouped into past trips outside each person's homes. Survey scores (1–10)
  are kept, and notes are as written, without links.
- **Not found (left out):** Azaya and Torikizoku Shibuya (Tokyo), Platform CPH sauna and Al Malek Shawarma (Copenhagen),
  the Gaia cable car (Porto), Lake Atitlán, Café Alma (Mississauga) and Jabal Coffee House (Nice). Spots too vague to
  place ("pub on King", an unnamed eco lodge) were skipped when curating.

```sh
python3 -I scripts/seed-beta-survey.py lookup   # refresh Apple Maps matches (cached in supabase/fixtures/beta-survey-places.json)
python3 -I scripts/seed-beta-survey.py plan     # summary and SQL, nothing written
python3 -I scripts/seed-beta-survey.py apply    # safe to run again
python3 -I scripts/seed-beta-survey.py remove   # deletes every seeded member and everything they own
```

`apply` and `remove` need the ignored `.env.beta`. Places and cities stay after `remove`, since anyone may have logged
them too.

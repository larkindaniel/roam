# Roam

Roam is a native iOS travel app for friends. You log places you've been, rank them, plan trips by city, save places
you want to go, and see where your friends went. It looks and behaves like a first-party iOS 26 app (Liquid Glass,
Apple's greys, colour only for place states). It's built with SwiftUI and MapKit on a local Supabase backend in Docker.
Google is used only server-side, for photos and star ratings.

- How the app works now: [How the app works](#how-the-app-works) below, and every screen and what each tap does in
  `docs/screens.md`.
- How screens look, and how to build new components so they match: `docs/design-language.md`.
- Working rules for agents: `CLAUDE.md`.
- The original v1 contract: `SPEC.md`, `MILESTONES.md` and `DECISIONS.md`. Where the app has moved on, the "Current
  product" section at the end of `DECISIONS.md` says what changed.
- Backend runbook (migrations, fixtures, cleanup and deletion workers, operator queries): `docs/local-backend.md`.

## Requirements

Xcode 26.3 or newer with an iOS simulator runtime (the deployment target is iOS 18.0), XcodeGen, the Supabase CLI and Docker Desktop. The exact versions used are recorded in `docs/m8-verification.md`.

## Start the backend

```sh
supabase start                 # local stack for project "roam"; applies migrations and seed
./scripts/configure-local.sh   # writes git-ignored Config/Local.xcconfig and scripts/.fixture-env (prints no keys)
./scripts/backend-health.sh    # containers, Auth, roam_health() and Storage
python3 -I scripts/fixtures/setup.py   # fictional fixture accounts (password roam-fixture-pass)
```

Only ever target this project's local stack. Never add `--linked`, `--db-url` or `--project-ref`.

To explore the app with real places, load the demo data instead of the test accounts, then sign in as `kieran@roam.test` with the same password:

```sh
supabase db reset --local
python3 -I scripts/fixtures/demo.py
```

Real-backend tests need the test accounts, so run `supabase db reset --local` and `scripts/fixtures/setup.py` before them.

## Build and run

```sh
./scripts/generate.sh          # XcodeGen: project.yml -> Roam.xcodeproj (generated, not committed)
./scripts/build.sh             # Debug build for the iPhone 17 Pro simulator
```

Open `Roam.xcodeproj` and run the `Roam` scheme, or install `build/DerivedData/Build/Products/Debug-iphonesimulator/Roam.app` with `xcrun simctl install`. Sign in with a fixture account such as `maya@roam.test`. Debug builds also accept `-roam-backend fixture -roam-fixture-account maya` for the in-memory fixture backend that the UI tests use.

## Test

```sh
supabase test db --local                                  # pgTAP: schema, RLS and every RPC
TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild -project Roam.xcodeproj -scheme Roam \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath build/DerivedData \
  -resultBundlePath build/results/tests-$(date +%Y%m%d-%H%M%S).xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test   # unit, real-backend integration and UI journeys
python3 -I scripts/tests/test_media_cleanup.py            # cleanup worker (add ROAM_LIVE_CLEANUP=1 for the live test)
python3 -I scripts/tests/test_account_deletion.py         # deletion worker (add ROAM_LIVE_DELETION=1 for the live test)
./scripts/export-screenshots.sh build/results/<run>.xcresult m8   # named screenshots into screenshots/m8/
```

Without `TEST_RUNNER_ROAM_BACKEND_TESTS=1` the real-backend integration tests skip, and a skip is not a pass.

## Not verified locally

Real Sign in with Apple (token exchange, reauthentication and revocation) needs Apple credentials and a device. An iOS 18 runtime or device pass is still outstanding. Hosted Supabase and SMTP, scheduled cleanup and deletion workers, public privacy/terms/support pages and a moderation owner are release setup. See `docs/m8-verification.md`.

## How the app works

### Model

- **Place → city → state → country.** Grouping is automatic from a place's address.
  - Mountains and lakes without a town take their municipality as their city.
  - Countries, states and towns are never place results.
- **States:**
  - **Been:** a logged visit, a logged city or a home.
  - **Going:** on an upcoming trip.
  - **Saved:** wishlisted. Places, cities, states and whole countries can all be saved.
- **Been beats wishlist** at every level. Being somewhere removes it from your wishlist (database triggers in
  `20261105001200_been_beats_wishlist`). Saving a place also puts its city and country on your wishlist until you've
  been.
- **Planning is by city:** trips hold cities (or whole countries). Places are saved, and a trip shows what you've saved
  in its cities. Trip status comes from its dates.
- **Homes:** one or more home cities. A home counts as been. When logging, "Part of" defaults to a trip happening now
  near the place, otherwise to Home.
- **Logging:**
  - A visit has a feeling (Didn't like, Neutral or Liked it; new logs start at Neutral), an optional date, a trip or
    home, photos (no limit), a note and an audience (Only me, Friends or Public; Public is the default).
  - Ranking uses comparisons, and the score is stored out of 10.
  - Cities can be logged too, with the places you went there.
  - Countries and states ask "Where in Norway?".
- **Friends** are two-way friend requests. Friend profile pages are switched off for now (`MemberProfiles.available` in
  `AppRouter.swift`), so names and avatars don't open anything.
- **Scores** are hidden app-wide (`Score.isShown == false`), except friends' stars and your own on a place page, shown
  out of 5. Google's rating is shown separately as `★ 4.6 (1.2K)`.
- **Photos:** your own photos come first. After that, a place uses Google, then a map with a pin. Cities, states and
  countries use Google's photo, cached and retried daily when missing, then Wikipedia.
- **Set aside, not deleted:**
  - custom lists (backend only)
  - sending places (the Send button is greyed out)
  - friend profile pages and the screens they open (their travel profile, passport, lists, "new this year" and your
    shared wishlist): the code is all here, switched off by `MemberProfiles.available`
- **Removed:** the Explore tab.

### Screens

Every screen, what's on it and what each tap does: `docs/screens.md`.

### Backend

Migrations from `20261101…` on in `supabase/migrations/` are each named for what they add:

- **Friendships and audience:** `friendships`, `audience_trips_lists_shares_taste`, `friend_memories`
- **Homes, trips and cities:**
  - `home_cities_trip_cities`, `home_marks_visited`, `trip_countries`, `trip_places_to_saved`
  - `set_visit_trip` (change a visit's trip; it must be yours)
- **Passport and been:**
  - `passport`, `visited_city_dates`, `passport_marked_dates`, `city_logs`, `city_log_photos`
  - `been_beats_wishlist` (triggers that clear wishlists of anywhere you've been)
- **Wishlists:** `saved_cities`, `saved_countries`, `saved_regions*`
- **Photos:** `google_place_details`, `country_photos`, `area_photos`, `photo_misses_retry_daily`, `my_photos`,
  `no_photo_limit`
- **Friends tab:** `friends_feed()` returns friends' dated visits you may see; the app groups them per friend and city
  (`Roam/Domain/FriendFeed.swift`).
- **Suggestions:** `suggested_places()`, `suggested_cities()`, `hide_suggestion()` and `onboarding_places()`
  (`20261107000100_suggestions`). Weights and rules are in DECISIONS.md, "Suggestions".
- **Edge function:** `supabase/functions/google-place` looks up Google photos and ratings near a place, refreshed about
  weekly.

### Key files

| Area | File |
|---|---|
| Tokens, cards, buttons | `Roam/DesignSystem/Theme.swift`, `RoamMarks.swift`, `PlaceMapMarkers.swift` |
| Tab bar, routes | `Roam/App/MainTabView.swift`, `Roam/App/AppRouter.swift` |
| Swipe-up card | `Roam/DesignSystem/GlobeSheetLayout.swift` |
| Standard rows, date row | `Roam/Features/Lists/MyPlacesSections.swift` |
| Photo cards, My Places tabs | `Roam/Features/Lists/MyPlacesTabs.swift` |
| Photos, gallery, Wikipedia | `Roam/Places/PlaceBackground.swift` |
| Discover / city / country | `Roam/Features/ForYou/` |
| Suggestions: reason lines, order, taste lean | `Roam/Domain/Suggestions.swift` |
| Onboarding (where have you been, rank them) | `Roam/Features/Onboarding/` |
| Place page | `Roam/Features/Experience/ExperienceDetailView.swift`, `MyVisitsCard.swift` |
| Friends on a place | `Roam/Features/Memories/PublicMemoriesSection.swift` |
| Friends tab | `Roam/Features/Feed/FeedRootView.swift`, `Roam/Domain/FriendFeed.swift` |
| Log screen | `Roam/Features/Rating/RatingFlowView.swift`, `RatingFlowModel.swift` |
| Trips | `Roam/Features/Plans/TripViews.swift` |
| Search | `Roam/Features/Search/PlaceSearchResults.swift` |

### Not done yet

- Unit tests and the database tests pass. The real-backend integration tests and the UI journey tests haven't been
  updated for the current app.
- Daniel's social features are being moved into the new design. He built friendships, posts, comments, likes,
  finding people, sharing and profiles, and the current Friends tab runs on that work. Some of those screens are hidden
  while the redesign settles; none of the code or backend was deleted. How they come back is to be decided together:
  comments and likes, a good way to make posts, searching for friends, sharing places with friends, lists you can share
  with friends, and friend profiles.
- The fixture backend only stubs the newer features.
- iOS 18 still needs a runtime check (Liquid Glass falls back to frosted material before iOS 26).
- Google's terms require its photo credit and limit how long its data is kept. We refresh about weekly.
- Friend profile pages are in the code but switched off; turning them back on needs a restyle to the current design.

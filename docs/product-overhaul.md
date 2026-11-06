# Roam product overhaul: working context

Start here if you're picking up work on branch `kieran/roam-product-overhaul`, whether you're a person or an agent. This
page covers what the app is now, how its screens fit together and how we work. Two companion docs go with it:

- `docs/design-language.md`: the visual rules and the shared components. Read it before touching UI.
- `docs/overhaul-changelog.md`: a plain-English list of everything the overhaul changed.

The overhaul deliberately departs from the original v1 contract (`SPEC.md`, `MILESTONES.md`, `DECISIONS.md`, `PLAN.md`,
`CLAUDE.md`'s milestone run). Where they disagree, this page, the design language and Kieran's latest instructions win.
The older documents still hold for things the overhaul didn't touch, such as the ranking formula, the data rules and
the security model.

## How we work

- **Branch:** `kieran/roam-product-overhaul`, cut from `codex/sol-max-handoff`.
  - Commit locally after each round of changes. **Never push.**
  - Commit messages are plain English describing what changed for the user (see `git log`).
  - **No AI attribution:** no `Co-Authored-By` trailer. Kieran is the only author and committer.
- **Speed over ceremony.** Don't run the full test suites.
  - Build with `./scripts/build.sh <simulator-id>` (it runs XcodeGen and then builds).
  - Then `xcrun simctl install … build/DerivedData/Build/Products/Debug-iphonesimulator/Roam.app` and
    `xcrun simctl launch --terminate-running-process … com.daniellarkin.roam`.
  - When you change shared types or remove code, compile the tests with `xcodebuild … build-for-testing`. Don't run
    them.
- **Simulator:** iPhone 17, `CC85E084-8AB2-46F6-ABF7-12546336CCF5`, located in Waterloo. Kieran checks screens himself:
  build, install and launch, but don't tap through the app unless he asks.
- **Backend:** local Supabase in Docker. The tools are in `~/.local/bin` (`export PATH="$HOME/.local/bin:$PATH"`).
  - Schema changes are forward-only migrations in `supabase/migrations/`. Apply them with
    `supabase migration up --local`.
  - To look at data, run `docker exec supabase_db_roam psql -U postgres`.
  - A new edge function is only served after `supabase stop && supabase start`. Data survives the restart.
  - Demo login: `kieran@roam.test`. The password is in `scripts/fixtures/setup.py`. The demo seed is
    `scripts/fixtures/demo.py` and isn't idempotent (`plans_sql()` re-runs only trips, homes and visited cities).
- **Secrets:** the Google Places key lives in `supabase/functions/.env` (gitignored) as `GOOGLE_PLACES_KEY`. Never commit
  it, paste it anywhere or put any key in the app.
- **Feedback loop:** Kieran sends many small UI notes, often mid-task. Fold each one in, rebuild, install, and commit in
  small batches. When a note reverses an earlier one, the latest note wins. Remove the old version rather than keeping
  both behind a flag.

## What the app is

Roam is a travel memory and discovery app for friends. You log places you've been, rank them, plan trips by city, save
places you want to go, and see where your friends went. Maps are MapKit. Google is used only server-side, for place,
city and country photos and for star ratings.

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
- **Friends** are two-way friend requests. There are no member profile pages: names and avatars don't open anything.
- **Scores** are hidden app-wide (`Score.isShown == false`), except friends' stars and your own on a place page, shown
  out of 5. Google's rating is shown separately as `★ 4.6 (1.2K)`.
- **Photos:** your own photos come first. After that, a place uses Google, then a map with a pin. Cities, states and
  countries use Google's photo, cached and retried daily when missing, then Wikipedia.
- **Set aside, not deleted:** custom lists (backend only), sending places (the Send button is greyed), the unit and UI
  test suites (out of date). Member profiles, the passport, shared wishlists and the Explore tab were removed.

## Screen tree

```
App (Roam's own floating glass tab bar: Discover · Friends · My Places; each tab button returns to its home)
│
├── Discover  (Features/ForYou/ForYouRootView)
│   ├── Search bar (cities, countries, places) · settings cog
│   └── "Places we think you'd enjoy": big city photo cards (loading: SkeletonCards) → City page
│
├── Friends  (Features/Feed/FeedRootView)
│   ├── Top right: friends and requests · notifications · settings
│   └── One card per friend and city, newest visit first (undated visits left out):
│       avatar, name and dates → the city's photo with "Japan 🇯🇵" (opens the city) → each place as a row with a chevron
│
├── My Places  (Features/Lists: full-screen globe with a swipe-up card)
│   ├── Search bubble when minimised; the globe always shows every place's dot (been > going > saved)
│   ├── Saved (left, opens first): homes, upcoming trips with + New trip, saved countries/states as photo cards or a grid
│   └── Been (right): homes, countries you've been to as photo cards or a grid, past trips
│
├── City page  (Features/ForYou/CityPageView): the app's explorer, shared by every tab
│   ├── Full-screen map showing only your places (green been, yellow saved), with Apple Maps–style icons
│   ├── Minimised: "Search <city>" in the tab bar's spot, with the blue directions circle beside it
│   ├── Open: name with Set as home, round buttons Log · Wishlist · Trip · Send · Plan; Start → End when been;
│   │   photo and blurb; untitled wishlist and been cards; suggested places as big photo cards
│   └── Opening a place stays on this map: the card swaps to the place (no slide), and back returns the city
│
├── Country / state page  (CountryPageView): name and flag, Been · Wishlist · Trip · Plan, photo and blurb,
│   homes, trips, wishlist and been city rows, suggested cities
│
├── Place page  (Features/Experience/ExperienceDetailView): map with a swipe-up card
│   ├── Header: name, city chip, ★ Google rating, directions; buttons Log/Been · Save · Send
│   │   (Been offers only Delete)
│   └── Card: photo gallery (dots), Wikipedia blurb, your visits (rows; tap to edit, swipe to delete,
│       + Add visit), then a titleless card with You first, then friends with their stars, then everyone else
│
├── Trip page  (Features/Plans/TripViews): name with an edit icon, date bubbles, cities as photo cards
│   (several countries: a country card with city rows), swipe to delete, Add to trip at the bottom, bin to delete
│
├── Settings  (cog): profile row → Edit profile (photo, name, handle, bio, home cities), account, privacy
│
└── Sheets
    ├── Log (RatingFlowView): name, feeling, date chip, Part of, photos, note, glass Save
    │   ├── then comparisons: "Which did you like more?", two cards, Undo · Too tough · Skip
    │   └── the same screen, filled in, edits a visit (it can change trip, date, photos, note, audience)
    ├── City log: the same, plus places you went (rows) and photos
    ├── New trip: name, Start → End, cities, × with discard
    └── Plan with AI (pink): ChatGPT · Claude · copy
```

## Backend added in the overhaul

These are the migrations from `20261101…` on in `supabase/migrations/`, each named for what it adds:

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
- **Edge function:** `supabase/functions/google-place` looks up Google photos and ratings near a place, refreshed about
  weekly.

## Key files

| Area | File |
|---|---|
| Tokens, cards, buttons | `Roam/DesignSystem/Theme.swift`, `RoamMarks.swift`, `PlaceMapMarkers.swift` |
| Tab bar, routes | `Roam/App/MainTabView.swift`, `Roam/App/AppRouter.swift` |
| Swipe-up card | `Roam/DesignSystem/GlobeSheetLayout.swift` |
| Standard rows, date row | `Roam/Features/Lists/MyPlacesSections.swift` |
| Photo cards, My Places tabs | `Roam/Features/Lists/MyPlacesTabs.swift` |
| Photos, gallery, Wikipedia | `Roam/Places/PlaceBackground.swift` |
| Discover / city / country | `Roam/Features/ForYou/` |
| Place page | `Roam/Features/Experience/ExperienceDetailView.swift`, `MyVisitsCard.swift` |
| Friends on a place | `Roam/Features/Memories/PublicMemoriesSection.swift` |
| Friends tab | `Roam/Features/Feed/FeedRootView.swift`, `Roam/Domain/FriendFeed.swift` |
| Log screen | `Roam/Features/Rating/RatingFlowView.swift`, `RatingFlowModel.swift` |
| Trips | `Roam/Features/Plans/TripViews.swift` |
| Search | `Roam/Features/Search/PlaceSearchResults.swift` |

## Open ends

- The unit and UI tests haven't caught up with the overhaul. They compile but aren't kept green.
- The fixture backend only stubs the newer features.
- iOS 18 still needs a runtime check (Liquid Glass falls back to frosted material before iOS 26).
- Google's terms require its photo credit and limit how long its data is kept. We refresh about weekly.
- Friends' profiles may come back later as a rebuilt page.

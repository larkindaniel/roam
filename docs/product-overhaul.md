# Roam product overhaul: working context

Context for anyone (including a fresh Claude session) picking up the product overhaul on branch
`kieran/roam-product-overhaul`. It covers what the app is now, the design direction, how the screens fit
together, and how we work. It is not a changelog; `git log` has that.

The overhaul deliberately departs from the original v1 contract in `SPEC.md` and `MILESTONES.md`. Where this
document and those disagree, this document and the latest instructions from Kieran win. `DECISIONS.md` records
the individual product decisions as they are made.

## How we work

- **Branch:** `kieran/roam-product-overhaul`, branched from `codex/sol-max-handoff`. Commit locally after each
  round of changes. **Never push.**
- **Speed over ceremony:** don't run the full test suites. Build with `./scripts/build.sh <simulator-id>`
  (it runs XcodeGen and then builds), install, and check by eye in the simulator. The unit and UI tests are
  out of date with the overhaul and aren't kept green right now.
- **Simulator:** iPhone 17, `CC85E084-8AB2-46F6-ABF7-12546336CCF5`, with its location set to Waterloo.
  Simulator taps are often delivered late or dropped, so take a screenshot to confirm what actually happened.
- **Backend:** local Supabase in Docker. Tools live in `~/.local/bin` (`export PATH="$HOME/.local/bin:$PATH"`).
  - Schema changes are forward-only migrations in `supabase/migrations/`; apply them with
    `supabase migration up --local`.
  - A newly added edge function is only served after `supabase stop` and `supabase start`. Data survives
    the restart.
  - The base demo seed in `scripts/fixtures/demo.py` isn't idempotent. To re-run only its plans part
    (trips, home cities, visited cities), call `plans_sql()`.
  - Demo login: `kieran@roam.test`. The password is in `scripts/fixtures/setup.py`.
- **Secrets:** the Google Places key is in `supabase/functions/.env` (gitignored) as `GOOGLE_PLACES_KEY`.
  `.env.example` documents it. Never put keys in the app.
- **Feedback loop:** Kieran sends many small UI notes in quick succession, often while you're mid-task. Fold
  each one in, rebuild, screenshot, and commit in small batches.

## Design direction: "Apple, Liquid Glass"

The goal is for Roam to look and feel like a first-party iOS 26 app. Prefer system patterns and Liquid Glass
(`glassEffect`) over custom styling, and don't invent decoration.

- **Colour:** Apple neutral greys. The background is the grouped grey (`#F2F2F7`) and cards are off-white
  (`Roam.paperRaised`). Cards are set apart by a soft shadow all round, not borders. The only colours are
  photos and the three place-state colours:
  - **Green = been** (visited)
  - **Blue = going** (planned, on a trip)
  - **Yellow = saved** (wishlist)

  Use these colours consistently for buttons, pins, globe country fills and tabs.
- **Shape:** continuous "squircle" corners everywhere. `Theme.cornerRadius` is 26. Elements nested inside a
  card get a smaller radius so the curves stay concentric. Corners of a sheet that sit at the bottom of the
  screen follow the screen's own rounded corners.
- **Floating controls:** glass circles and pills (`floatingBubble(_:)` in `ExploreRootView.swift`) sit over
  full-bleed maps. A screen's top bar is a row of glass buttons rather than a navigation title.
- **Tab bar:** Roam draws its own floating glass tab bar (`RoamTabBar` in `MainTabView.swift`) so it can
  match the screen's margins (wider at the sides than below, because the screen corners curve in) and step
  aside per screen. To hide it, use `.roamTabBar(hidden:)`, not `.toolbar(.hidden, for: .tabBar)`.
- **Swipe-up cards** (`GlobeSheetLayout`) follow the Apple Maps place sheet:
  1. **Bubble:** a short floating pill with wide margins and the grab bar, most see-through.
  2. **Half:** narrow margins, less see-through. Cards inside it are a see-through grey.
  3. **Full:** solid and edge to edge, stopping just below the top buttons. Cards inside it turn white.

  The header (grab bar, title, main action) stays fixed. On place pages and My Places, scrolling replaces it
  with a dark fade at the top showing just the name, small, white and centred. Scrolling up raises the card;
  pulling down past the top lowers it.
- **Copy:** short and plain. No explanation paragraphs, no place counts on countries or cities, and no
  repeated information.
- **Scores:** shown out of 5 (`Score.formatted`). They are still stored and ranked out of 10
  (`formattedOutOf10`, formula `roam-category-v1`).

## What the app is

Roam is a travel memory and discovery app for friends. You log places you've been, rank them, plan trips, save
places you want to go, and discover places through what your friends loved. It is MapKit only; Google is used
only server-side for place photos and star ratings.

### Core model

- **Place → city → country.** Grouping by city and country is automatic.
- **Place states:** been (a logged visit), going (on an upcoming trip), saved (bookmarked).
- **Planning is by city:** only cities go on trips; places are saved, and a trip shows what you've saved in its cities.
- **Trips** cover one or more cities and take their status from their dates: planning (no dates), upcoming,
  now, or past. Trips without dates sort after dated ones. Places on a trip are planned. Logging a visit can
  attach it to a trip.
- **Home cities:** one or more per person. Anything within 100 km of a home city counts as home and stays off
  the travel timeline. When logging, the visit defaults to the nearest home; you can pick a trip instead.
- **Visited cities:** you can mark a city as visited without logging any place. It appears only in your
  passport, never in friends' feeds.
- **Passport:** every country and city you've been to. A friend sees your whole passport but can only open the
  places you've shared with friends; private ones show as "Kept private".
- **Friends** are two-way friend requests. The Friends feed is grouped by country.
- **Lists:** custom lists of places, alongside the wishlist.
- **Scores:** each place card shows three sources separately, never blended: You, Friends (the average of
  your friends' scores), and Google (★ out of 5 with a review count, when Google has the place).
- **Photos:**
  - Places: a photo from a Roam visit, else Google's photo (with its credit), else a full-colour map with a
    red pin showing the category icon.
  - Cities, trips and saved countries: Wikipedia's lead photo (`CityGuide`, `WikipediaPhoto`). Saved
    countries use their main city's photo, because a country's article leads with its flag.
  - Look Around is a binoculars button on a place page's map.

### Backend pieces added in the overhaul

| Migration or function | Adds |
|---|---|
| `20261101001100_country_feed` | `country_feed()` and `country_updates(owner, country)`, the Friends feed grouped by country |
| `20261102000100_home_cities_trip_cities` | `home_cities` and `trip_cities` tables; `my_home_cities`, `set_home_city`, `set_trip_city`; `trip_json` now includes `cities` |
| `20261102000200_passport` | `visited_cities` table; `set_city_visited`; `passport(owner)`, available to yourself and friends |
| `20261102000300_google_place_details` | Google rating and count columns on places; service-only `google_lookup_targets` and `save_google_lookup` |
| `supabase/functions/google-place` | Places API (New) text search near the place (match within 750 m), first photo and rating, refreshed about weekly; the app calls it via `refreshGoogleDetails` |

## Screen tree

```
App
├── Floating tab bar: Discover · Friends · My Places  (Roam's own; hidden on place pages,
│   Explore-style full maps, and My Places until its card is fully up)
│
├── Discover  (ForYouRootView)
│   ├── Top row of glass buttons: [+ Log] [Search] [Map · Profile]
│   │   ├── Tapping Search hides the other buttons; results list cities, Roam places and Apple Maps places
│   │   └── The row tucks away when you scroll down and returns when you scroll up
│   ├── "Places we think you'd enjoy": suggested city cards with Wikipedia photos and "Dhyan has been"
│   └── → City page (below)
│
├── Friends  (FeedRootView)
│   ├── Country cards per friend  →  Country updates (that friend's places in that country)
│   ├── Friend requests, notifications, profile
│   └── Friend profile  →  globe, Passport (countries → cities → shared places)
│
├── My Places  (MyPlacesRootView: full-screen satellite globe with a swipe-up card)
│   ├── Top left: back to Discover (bubble and half) or + Log (full), then recenter
│   ├── Top right: map (Explore for the country in view) · profile
│   ├── Bubble: "My Places" with a green "+ Add a place"
│   ├── Segmented toggle; the globe shows and turns to the chosen tab's places
│   │   ├── Been (green): "N countries · N cities", passport stamps (→ passport country → city),
│   │   │   "Add a city", home cities (→ home city spots), past timeline (trips and journeys by country)
│   │   ├── Going (blue): next trip as a large photo card with a countdown, other trips, New trip
│   │   └── Saved (yellow): country photo tiles (→ wishlist country with "Plan a trip"), your lists, +
│   └── Tapping or panning to a country you have places in flies there; the card switches to that country
│
├── Place page  (ExperienceDetailView: full-screen map with a swipe-up card, tab bar hidden)
│   ├── Map: red category pin, freely movable; Look Around binoculars at the bottom left
│   ├── Bubble: name and a round blue directions button (asks Apple Maps or Google Maps)
│   └── Card: category · area; action buttons (green Log, blue Plan, yellow Save, Send; once the place is
│       been, planned or saved, that button fills in and the other two hide); photo gallery;
│       friends' visits; You / Friends / Google scores; private note; memories
│
├── Trip page  (TripDetailView): cities, dates, places by country then city, add from wishlist, add a city
├── City page  (CityPageView, shared by Discover, My Places, friends' passports, and every map button)
│   ├── Full-screen map: your spots green, suggestions red; tapping a pin opens the place
│   ├── Bubble (minimised, in the tab bar's spot): "Search <city>", results limited to the city and around it
│   ├── Half / full: search at the top, then name · Set as home · Plan (trip or Plan with AI) on one line,
│   │   Wikipedia photo and blurb, your spots, places we think you'd enjoy; searching swaps in results
│   ├── Tab bar only when the card is fully up; back button top left
│   └── Map buttons open the city you're in (Discover) or the country-in-view's main city (My Places)
└── Sheets: Log a place → rating flow ("Part of": home or trip), Add to trip, Destination picker,
    New trip (optional side-by-side start and end dates), Share, Plan with AI
```

## Key files

| Area | File |
|---|---|
| Tab bar and routes | `Roam/App/MainTabView.swift`, `Roam/App/AppRouter.swift` |
| Swipe-up card | `Roam/DesignSystem/GlobeSheetLayout.swift` |
| Tokens, cards, pills | `Roam/DesignSystem/Theme.swift`, `RoamMarks.swift` |
| Globe | `Roam/Features/Globe/GlobeMapView.swift`, `Roam/Geography/CountryGeometry.swift` |
| My Places | `Roam/Features/Lists/ListsRootView.swift` (model and root), `MyPlacesTabs.swift`, `MyPlacesSections.swift` |
| Discover | `Roam/Features/ForYou/ForYouRootView.swift` |
| City page (the app's explorer) | `Roam/Features/ForYou/CityPageView.swift` |
| Place page | `Roam/Features/Experience/ExperienceDetailView.swift` |
| Photos and Wikipedia | `Roam/Places/PlaceBackground.swift` |
| Trips | `Roam/Features/Plans/TripViews.swift` |

## Open ends

- The unit and UI tests haven't been updated for the overhaul.
- The fixture backend (`FixtureBackend`) only stubs the newer features.
- iOS 18 still needs a runtime check: Liquid Glass falls back to frosted material before iOS 26.
- Place photos come from Google when there's no visit photo. Google's terms require the photo credit and
  limit how long its data is kept (we refresh about weekly).

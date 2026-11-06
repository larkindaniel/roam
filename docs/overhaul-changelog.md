# What the overhaul changed

A plain-English summary of branch `kieran/roam-product-overhaul` (Nov 1–6, 2026, about 345 commits on top of
`codex/sol-max-handoff`). It describes where things ended up, not every intermediate try; `git log` has those.

## Foundations

- Rebuilt the look to feel like a first-party iOS 26 app:
  - Apple neutral greys, off-white cards with soft shadows, squircle corners and Liquid Glass controls.
  - Colour reserved for place states: green been, blue going, yellow saved.
- Replaced the five-tab shell with three tabs (Discover, Friends, My Places) under Roam's own floating glass tab bar.
  Tapping a tab returns to its home page, scrolled to the top.
- Turned one-way follows into two-way friend requests, and added who-can-see-this (Only me, Friends, Public) to every
  log.
- Added unranked logging, trips, lists, direct shares and taste to the backend, with database tests across users.
- Debug simulator builds stay signed in between launches.
- New app icon: the Earth with a red pin.
- Added one shared design language: standard rows, photo cards, bubble buttons, round action buttons, chips, date
  pickers and loading placeholders, used on every visible screen. It's written down in `docs/design-language.md`.

## Places and logging

- **Log screen on one page:**
  - The place's name with its city under it.
  - A feeling picker: Didn't like, Neutral or Liked it, starting at Neutral and coloured red, white or green.
  - A date chip with a × to clear it and a calendar on tap.
  - "Part of", which picks a trip happening nearby or Home.
  - Unlimited photos in a swipeable carousel.
  - A roomy note that takes new lines.
  - Glass Save, and a × that asks before discarding. No drafts.
- **Comparisons cut down** to "Which did you like more?", two cards with "or" between them, and Undo, Too tough and
  Skip.
- **Fewer glitches:** saving closes straight away with no result screen, and nothing flashes when you close or finish a
  comparison. The red photo-upload warning is gone.
- **Editing a visit** reopens the same log screen, filled in, and can change its trip. There's no separate edit screen.
- **Cities can be logged** like places, with the places you went there and photos. Logging a country or state asks
  "Where in Norway?".
- **Categories:** places that already have a category, from Roam or from Apple's place type, skip the category picker.
- **Search** finds places, cities, states and countries, each with the right icon:
  - Towns never show up as places.
  - Mountains take their municipality as their city.
  - Small territories like Hong Kong are found.
  - When search fails it says why, with Try again.
  - Nothing autocapitalises or autocorrects.

## Place page

- A full-screen map with an Apple Maps–style swipe-up card. Opening a place from a city stays on the same map, and the
  card swaps over with no slide.
- **Header:** the name, a city chip, Google's rating as a small `★ 4.6 (1.2K)` and a blue directions button (Apple Maps
  or Google Maps).
- **Buttons:** Log or Been, Save and Send, with Send greyed out until it's built. Been only offers Delete, with one
  confirmation.
- **Photos:** a swipeable gallery with dots, your own photos first, and the Wikipedia blurb under it when there is one.
- **Your visits:** rows with a photo, the date and the first line of the note. Tap a row to edit it, swipe to delete,
  and + Add visit at the bottom.
- **Friends:** one titleless card. You come first with your rating, then each friend with when they last went and their
  stars.
- **Removed:** the private note card, the category label and icon, and the place's Plan button (only cities are
  planned).

## Cities, countries and states

- **The city page is the app's explorer:**
  - A full-screen map of your own places (green been, yellow saved) with Apple Maps–style icons.
  - Search inside the city, with directions beside the search bar.
  - Round buttons: Log, Wishlist, Trip, Send and Plan with AI (pink).
  - Set as home, and visit dates (Start → End) once you've been.
  - Untitled wishlist and been cards, then suggested places as big photo cards.
- **Country and state pages** follow the same pattern: name and flag, Been, Wishlist, Trip and Plan, a Google photo,
  the Wikipedia blurb, your homes, trips, wishlist and been cities, and suggested cities.
- **Wishlists at every level:**
  - Whole cities, states and countries can be saved.
  - Saving a place puts its city and country on your wishlist.
  - Been always beats wishlist: being somewhere takes it off.
- **Photos:** cities and countries get Google photos everywhere, cached and retried daily if missing. Wikipedia blurbs
  are found far more often.
- **Plan with AI:** a sheet that hands a prompt to ChatGPT or Claude, or copies it.

## Trips

- Trips hold cities, or whole countries. Saved places show up on any trip to their city.
- **Trip page:**
  - Name with an edit icon.
  - Start → End date bubbles, edited in place.
  - Cities as big photo cards, or one card per country with city rows when the trip crosses countries.
  - Swipe to delete a city, Add to trip at the bottom, and a red bin to delete the trip.
- **New trip** needs dates and at least one city, and the × asks before discarding.

## My Places

- A full-screen satellite globe that always shows every place's dot (been, then going, then saved), under a swipe-up
  card.
- **Two tabs:**
  - **Saved** (opens first): your homes, upcoming trips with + New trip, and saved countries and states.
  - **Been:** your homes, the countries you've been to, and past trips.
- Countries show as big photo cards, switching to a two-across grid from ten countries.
- Searching from the minimised bubble raises the card.
- **Homes:** one or more home cities, which count as been. They're edited from a city's page or Edit profile.

## Friends

- **Friends tab:** one card per friend and city, newest visit first, leaving out visits without a date. Each card has:
  - The friend's avatar, name and dates.
  - The city's photo with "Japan 🇯🇵" under it, which opens the city.
  - Each place they went as a row with a chevron.
- **Friend profile pages removed,** along with the screens only they led to (shared wishlist, travel profile, new this
  year, member lists, passport). Names and avatars no longer open anything.

## Settings and housekeeping

- **Settings:** a cog in its own glass circle on every tab. Settings itself was trimmed to profile, account and privacy.
  Edit profile holds your photo, name, handle, bio and home cities.
- **Scores:** Roam's own scores are hidden app-wide; only friends' stars and your own show, out of 5. Google's rating is
  never blended in.
- **Demo data:** real survey places under the team's accounts, with photos and dated trips.
- **Commit history:** the branch's commits carry no AI attribution.
- **Docs:** rewrote `docs/product-overhaul.md` and added `docs/design-language.md` and this file.

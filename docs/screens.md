# Roam screens

Every screen people can reach: what's on it, what each tap does, and how you move between screens. Keep this current
when you change a screen. `docs/design-language.md` covers how they look.

## Everywhere

- **Tab bar:** Roam's own floating glass bar with Discover, Friends and My Places. Tapping a tab always goes back to its
  home page, scrolled to the top. On screens with a full-screen map (city, place, My Places), the bar steps aside until
  the card is fully up.
- **Settings:** a cog in a glass circle at the top right of each tab opens Settings.
- **Swipe-up cards** (city, place, My Places) have three heights:
  - **Peek:** a short bubble.
  - **Half.**
  - **Full**, which shows the tab bar.

  Tapping the card's header swaps between half and full. Scrolling up raises the card; pulling down at the top lowers
  it.
- **Back:** a back button at the top left of pushed pages. Opening a place or city from another map stays on the same
  map (see City page), so there's no slide.
- **Search** (Discover, My Places, city pages) uses the same results list:
  - Your places, then cities, states and countries, then everything Apple Maps knows.
  - A country opens its country page, a state its state page, a city its city page and a place its place page.
  - The field's own × ends the search, and leaving the tab clears it.

## Onboarding (end of setup)

After name, handle, photo, home and Find friends, two steps teach Roam what you like. Both can be skipped.

- **Where have you been?** Up to 12 places around your home city as standard rows, the ones your friends have been to
  first, then the most rated. A search field finds anything else. Tapping a row ticks it (green Been mark). The button
  says "Skip for now" until something is ticked, then "Continue". With no home city it's search only.
- **One place at a time** ("1 of 3"): "How was it?" with the feeling picker, then "Which did you like more?" against
  your other places, with Undo, Too tough and Skip, like the log screen. After 10 comparisons in all, places go to the
  middle of where they'd fit without asking. Each place is saved as soon as it's placed: a visit with no date, seen by
  friends, so it's on your Been list but never on anyone's Friends tab. "Skip the rest" stops; what's saved stays.
- Then the visibility explainer and Start using Roam.

## Discover

- **Top:** a search bar and the settings cog.
- **Body:** "Places we think you'd enjoy", big city photo cards (grey placeholder cards while loading), ranked by Roam
  (see DECISIONS.md, "Suggestions").
  - Under each name: the country, then why it's suggested, such as "Portugal · Theo sent you a place here", "On your
    Japan trip", "On Maya's Lisbon list", "Maya loved it here", "Maya has been" or "Popular on Roam".
  - Your homes, cities you've been to and cities you've hidden never show.
  - A card opens that city's page. Long-press: Not interested hides it.
  - With nothing to suggest (no friends, nothing rated): "Nothing to suggest yet", "Add friends to see the places they love." and Find people.
  - Friends' picks show above the cards when there are any. A pick opens its place or trip.

## Friends

- **Top right:** friends and requests (people, requests, add friends), notifications, and settings.
  - In notifications, friend-request notifications mark themselves read but open nothing. Activity notifications open
    the post.
- **Body:** one card per friend and city, newest visit first. Visits without a date aren't shown. Each card has:
  - The friend's avatar, name and the dates they were there. Not tappable.
  - The city's photo with "Japan 🇯🇵" under the name, which opens that city's page.
  - Each place they went there as a row with a chevron, which opens the place.
- Friend profile pages are switched off for now (`MemberProfiles.available`), so names and avatars don't open anything.
- With no friends yet, the empty state offers "Find people".

## My Places

A full-screen satellite globe that always shows every place's dot (been, then going, then saved), with a swipe-up card
over it.

- **Opens halfway.** At peek, the card is a "Search places" bubble. Tapping it raises the card and searches your places,
  then cities, then Apple Maps.
- **Selector:** Saved (left, opens first) and Been (right).
  - **Saved:**
    - Home cities (rows with a black house). Each opens its city page.
    - Upcoming trips (rows with a blue plane), each opening its trip page, then a full-width "+ New trip" that opens the
      New trip sheet.
    - Countries and states you've saved, as photo cards (a two-across grid from ten). Each opens its country page.
  - **Been:**
    - Home cities.
    - Countries you've been to, as photo cards. Each opens its country page.
    - Past trips (rows with a green mark). Each opens its trip page.

## City page

The app's explorer, used from every tab. Map buttons elsewhere open one, either the city you're in or the main city of
the country in view.

- **Map:** only your places, as green been and yellow saved pins using the place's icon. Suggestions stay in the card.
  - Tapping a pin opens that place in the card. The map doesn't move.
  - Tapping anything Apple shows on the map opens it as a place.
  - Tapping another city on the map opens that city's page on the same view.
- **Peek:** "Search <city>" in the tab bar's spot, with a blue directions circle beside it that asks Apple Maps or
  Google Maps. Searching stays within the city and its surroundings.
- **Opened:**
  - **Name and home:** the name, with Set as home beside it. A home city shows a solid black house instead.
  - **Round buttons:**
    - **Log** (green): ticks straight away and shows Start → End dates under the buttons. The visit saves once both
      dates are picked or you leave. Once you've been, the dates you gave show there.
    - **Wishlist** (yellow): saves the city. It greys out once you've been.
    - **Trip** (blue): add the city to an upcoming trip or start a new one.
    - **Send:** greyed out until sending is built.
    - **Plan** (pink): opens the Plan with AI sheet (ChatGPT, Claude or copy).
  - A home city shows only the house and Plan.
  - **Below the buttons:** the city's photo and Wikipedia blurb, then an untitled card of the places there you've saved,
    then one of the places you've been. Rows open the place.
  - **Suggestions:** big place photo cards, ranked by Roam, each with its reason line ("Theo sent you this", "On
    Maya's Lisbon list", "Maya and Theo loved it", "Maya has been", "Like the cafés you loved", "Like places you loved",
    "Popular on Roam"; the
    category when there's none) and the Google stars. Places you've been to, saved or hidden never show. A card opens
    the place. Long-press: Not interested hides it.
- **Opening a place from here** stays on this map. The map glides to it and the card swaps to the place, halfway up.
  Back brings the city's card back.

## Country and state pages

- **Header:** the name with its flag under it, and round buttons Been, Wishlist, Trip and Plan.
  - **Been** and **Wishlist** follow from your cities and places there. Removing Been asks first, then clears what you
    logged there (homes stay).
  - **Trip** opens a new trip with the country on it.
  - If the name won't fit beside the buttons, the buttons move under it.
- **Body:**
  - A Google photo and the Wikipedia blurb.
  - Your home there, which opens its city.
  - Your trips there (rows), which open the trip.
  - An untitled wishlist card, then a been card, of city rows that open the city.
  - Saved states, which open their state page.
  - Suggested cities as photo cards, ranked by Roam, each with its reason line (or the state when there's none).
    A card opens the city. Long-press: Not interested hides it.
- A state page also has a chip that opens its country.

## Place page

A map with the place's pin and a swipe-up card. On the map, Look Around (binoculars) appears when available, and
tapping another place or pin swaps the card to it.

- **Header:**
  - The name, a grey city chip that opens the city, and Google's rating `★ 4.6 (1.2K)`.
  - The blue directions circle, which asks Apple Maps or Google Maps.
  - **Log / Been:** Log opens the log sheet. Once you've been, the button shows Been, and tapping it offers only
    Delete, with one confirmation, which removes your visits and ranking.
  - **Save:** saves or unsaves the place. It's greyed out once you've been.
  - **Send:** greyed out.
- **Card:**
  - **Photos:** a swipeable gallery with dots, your own photos first. The Wikipedia blurb sits under it when there is
    one.
  - **Your visits:** rows showing the first photo, the date and the first line of the note.
    - Tapping a row opens the log sheet filled in, to edit it.
    - Swiping a row left deletes it.
    - "+ Add visit" logs another visit.
  - **People who've been:** a titleless card. "You" comes first with your stars, then each friend with when they last
    went and their stars. Long-pressing a friend offers Report.
  - **Everyone else:** other people's visits, with All photos opening the photo viewer.

## Trip page

- **Header:**
  - The name with an edit icon, which opens a sheet to rename the trip.
  - Start → End date bubbles, edited right there.
  - A red bin, which deletes the trip after one confirmation.
- **Places:**
  - **One country:** each city as a big photo card that opens the city.
  - **Several countries:** one card per country, with the country's photo on top (opens the country) and its cities as
    rows (each opens the city).
  - Swiping a city or country deletes it from the trip.
- **Bottom:** "+ Add to trip" opens the city search.

## Settings

- Your profile row opens Edit profile: photo, name, handle, bio, and home cities (add any number, swipe to remove).
  Cancel with changes asks to discard them.
- Your tastes: five optional questions (atmosphere, budget, crowds, novelty, pace) that go into Plan with AI prompts.
  Suggestions don't use them; they learn from your rankings.
- Account: email, sign out, delete account. Then privacy, terms and version.

## Sheets

- **Log a place (opened from Log or + Add visit):**
  - The name with its city under it.
  - The feeling picker: Didn't like, Neutral or Liked it. It starts at Neutral.
  - A date chip: × clears it, and tapping it opens a calendar.
  - "Part of": a trip happening nearby, or Home, or any trip.
  - Add photos opens the picker; photos then swipe in a carousel.
  - A note, and who can see the visit.
  - Save saves the visit. A ranked log first asks "Which did you like more?" between pairs of places (Undo, Too tough,
    Skip), then closes.
  - × with anything filled in asks to discard. Nothing is kept as a draft.
- **Edit a visit:** the same sheet, filled in. It can change the date, trip, photos, note and audience.
- **Log a city:** the same, plus "Add places" (search, one tap to add) and photos. The places you add are logged as been
  without ratings.
- **Log a country or state:** asks "Where in Norway?" and you add cities and places.
- **New trip:**
  - Name, then Start → End dates (both required).
  - "+ Add a city", which opens the city search. At least one city is needed.
  - × asks before discarding. Save is at the bottom.
- **Plan with AI:** copies a prompt for the city or country, or hands it to ChatGPT or Claude. The prompt has your
  tastes, the kinds of places you tend to love (cafés, museums: from your Liked rankings, once there are 3) and up to
  five places you liked.

# Roam screens

Every screen people can reach: what's on it, what each tap does, and how you move between screens. Keep this current
when you change a screen. `docs/design-language.md` covers how they look.

## Signing in

- **Welcome:** the Roam logo (the app icon, as big as the screen allows), "Roam", and "Find places you love from people
  you trust." Continue with Apple (black; new and returning
  people both use it) and Sign in with email (grey; for accounts with a password) sit at the bottom.
- **Sign in, and the email steps** (create account, code, forgot password, new password): the round glass back button,
  a big title (no line under it), grey rounded fields, quiet links under them, and the black action pinned at the bottom.
- **Setup** (a new account), one page per step (just a title, no line under it) with a round back button and a thin
  progress bar at the top, and the
  step's button pinned at the bottom (grey "Skip for now" when nothing's chosen, black "Continue" once something is):
  1. **What's your name?**, then **your handle** (a tick once it's free). These make the profile. When Apple shared
     their name on first sign-in, setup opens on the handle (suggested from it); back still edits the name.
  2. **A profile photo**: tap the big circle to choose one.
  3. **What do you like?** Five questions (atmosphere, budget, crowds, classics or hidden gems, pace), each a slider
     like the log screen's feeling: drag or tap to choose, tap the chosen one again to clear. These feed Plan with AI and can be changed in Settings.
  4. **Where's home?** Search cities and pick as many as you like; each shows as a row with × to take it off, and the
     search stays to add another. They become your home cities.
  5. **Add friends:** suggestions, or search for anyone, each with Add. "Start using Roam" finishes.
  Every step can go back. Nothing is saved until you continue from home: then the profile is made (name, handle,
  photo, preferences, homes) but nobody can find it yet. The people you add are only asked, and the profile only becomes
  findable, when you tap "Start using Roam". Setup never logs places.

## Everywhere

- **Keyboard:** scrolling any page or list puts it away; on a log, tapping anywhere off the note does too.

- **Tab bar:** Roam's own floating glass bar with Discover, Friends and My Places. Tapping a tab always goes back to its
  home page, scrolled to the top. On screens with a full-screen map (city, place, My Places), the bar steps aside until
  the card is fully up.
- **Profile:** your profile picture in a glass circle at the top right of each tab opens your profile and settings.
- **Bug button (beta):** a red circle with a bug is the right-most button at the top of every page. That covers the
  tab pages, everything pushed on them, welcome, sign-in and setup. It snaps the screen, then opens **Report a bug**:
  - What went wrong, in a note card.
  - The screenshot of the screen you were on, shown big enough to read, with × to remove it.
  - **Add another** beside it, for more screenshots or recordings from Photos (up to six). With none attached, it's
    a grey **Add screenshots or recordings** bubble.
  - **Send**, at the bottom.

  Signed out, it's words only. The report is saved with the steps that led to it (see `docs/telemetry.md`).
- **Swipe-up cards** (city, place, My Places) have three heights:
  - **Peek:** a short bubble.
  - **Half.**
  - **Full**, which shows the tab bar.

  Tapping the card's header swaps between half and full. Scrolling up raises the card; pulling down at the top lowers
  it.
- **Back:** a back button at the top left of pushed pages. Opening a place or city from another map stays on the same
  map (see City page), so there's no slide.
- **Search:** there are exactly three, and every search field is one of them (`RoamSearchField`).
  1. **Worldwide places** (Discover, My Places, Log a place, onboarding, city pickers): your places (My Places only),
     countries, states, cities, then everything Apple Maps knows, places near you first. No filters. A city picker keeps
     only the cities; onboarding keeps only places.
  2. **A city or area** (city page, Add places when logging a city, "Where in Norway?"): only cities near it and places in
     or around it.
  3. **Accounts** (Find people, and picking friends for Send, trip invites and "went with", which lists only your
     friends).
  - Results look the same everywhere. Tapping one opens it, unless the screen is picking something.
  - The field's own × ends the search, and leaving the tab clears it. On Discover, tapping anywhere but a result ends it
    too.

## Discover

- **Top:** a search bar and your profile picture. Scrolling down swaps them for a dark fade with "Discover" centred;
  scrolling back up brings them back.
- **Body:** "Places we think you'd enjoy", big city photo cards (grey placeholder cards while loading), ranked by Roam
  (see DECISIONS.md, "Suggestions").
  - Under each name: the country, then why it's suggested, such as "Portugal · Theo sent you a place here", "On your
    Japan trip", "On Maya's Lisbon list", "Maya loved it here", "Maya has been" or "Popular on Roam".
  - Your homes, cities you've been to and cities you've hidden never show.
  - A card opens that city's page. Long-press: Not interested hides it.
  - With nothing to suggest (no friends, nothing rated): "Nothing to suggest yet", "Add friends to see the places they love." and Find people.
  - Friends' picks show above the cards when there are any. A pick opens its place or trip.

## Friends

- **Top:** a green "+ Log a place" bubble on the left opens Log a place (a search; pick a place to log a visit). On the
  right, Add friends, then your profile.
  Notifications are off for now. Scrolling down swaps the row for a dark fade with "Friends" centred; scrolling back up
  brings it back as glass on the fade.
- One card per dated friend log, newest first. A log is a visit; there are no separate posts. Only logs the log's
  audience allows show (Only me never does), with the log's own note and photos.
- Friends who went somewhere together (logs of the same place where one tagged the other with "With") show as one card
  with all their photos; the note, likes and comments are the newest log's.
- The top of a log, like Instagram: with no one else, "picture, name · date". With others (friends who logged it too, or
  anyone tagged with "With"), the pictures stacked with the author's on top, "Daniel Larkin with Nihal Menon" or "Daniel
  Larkin with 2 others", and the date on the line below. Each picture and name opens that person's profile; "2 others"
  opens a small white card in the middle of the screen listing everyone (tap outside to close), each opening their profile. There's no separate "With…" line.
- Logs sit straight on the page, with no card around them; the photos set them apart. Each log: a photo, either theirs (square; swipe between several, with dots at the bottom) or, with none, the
  place's Google photo at its usual size. Set into the top of the photo is one small line: their picture, name · date,
  which opens their profile (with no photo at all, the line sits on its own). Tapping a photo opens the log's own page; double-tapping likes it. Under the photo, a slim card with the place's name, city and country opens the place (with no photo, it's the standard place row instead). The note's first line (with "…" if there's more) sits bottom left in the photo, level with like and comment in white on the bottom right, on a dark fade (under the card when there's no photo); comment opens the log as its own page (the log, then the author's note as the first comment, then the comments as plain rows, with no "Comments" heading, long-press to delete yours or report someone else's, and a white field pinned at the bottom with your picture (which slides away once the comment wraps) and a send arrow). Double-tapping a photo likes it. A card never opens a page of its own.
- Likes and comments belong to the log. The comment field stays above the keyboard, and retry keeps the draft. A log is
  deleted from its place page; a tagged friend can remove their own tag.

## Add friends

- A back button and a white "Search for friends" bar at the top.
- Before you search: your friend requests, each with Accept. There's no separate requests page.
- Search results show everyone by name or @handle, each with its own Add, Requested, Accept or Friends button, so
  nothing takes two taps. Tapping a name opens that person's profile.

## Member profile

- The header shows the avatar, name, handle, and friendship action. Settings opens your own profile.
- Anyone's profile opens. Activity shows the logs you can see, and Passport (open for anyone) counts only logs whose
  audience includes you; cities marked as been without a log show to friends only. Lists shared directly with you
  appear too.

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
    - Trip invitations, Sent to you, and Lists each open a separate page.
    - Countries and states you've saved, as photo cards (a two-across grid from ten). Each opens its country page.
  - **Been:**
    - Home cities.
    - Countries you've been to, as photo cards. Each opens its country page.
    - Past trips (rows with a green mark). Each opens its trip page.
  - Both tabs include trips you own and trips you've joined. Past trips are in Been.

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
  - **Name:** the name, with its country under it.
  - **Round buttons:**
    - **Log** (green): ticks straight away and shows Start → End dates under the buttons. The visit saves once both
      dates are picked or you leave. Once you've been, the dates you gave show there.
    - **Wishlist** (yellow): saves the city. It greys out once you've been.
    - **Trip** (blue): add the city to an upcoming trip or start a new one.
    - **Send:** send the city to one or more friends, with an optional note. It shows in their Sent to you, with the
      city's photo, and opens its city page.
    - **Plan** (pink): opens the Plan with AI sheet (ChatGPT, Claude or copy).
    - **Home**, last: makes it one of your homes.
  - A home city has no round buttons: a solid house (tap to remove it as home) and Plan sit beside the name.
  - **Below the buttons:** the city's photo and Wikipedia blurb, then an untitled card of the places there you've saved,
    then one of the places you've been. Rows open the place.
  - **Friends who’ve been** shows friends with shared visits in the city. Tapping a friend opens their profile. The city map keeps showing your own pins.
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
- **Friends who’ve been** shows the cities friends visited in the country or state. Tapping a friend opens their profile. Suggested city cards use the same short reason line as Discover.

## Place page

A map with the place's pin and a swipe-up card. On the map, Look Around (binoculars) appears when available, and
tapping another place or pin swaps the card to it.

- **Header:**
  - The name, a grey city chip that opens the city, and Google's rating `★ 4.6 (1.2K)`.
  - The blue directions circle, which asks Apple Maps or Google Maps.
  - **Log / Been:** Log opens the log sheet. Once you've been, the button shows Been, and tapping it offers only
    Delete, with one confirmation, which removes your visits and ranking.
  - **Save:** saves or unsaves the place. It's greyed out once you've been.
  - **Send:** choose one or more friends and add an optional note (tap off it to put the keyboard away); each friend gets it. Friends can open it from Sent to you in My Places or
    from Discover. The place page shows who sent it and their note.
- **Card:**
  - **Photos:** a swipeable gallery with dots, your own photos first. The Wikipedia blurb sits under it when there is
    one.
  - **Your visits:** rows showing the first photo, the date and the first line of the note.
    - Tapping a row opens the log sheet filled in, to edit it.
    - Swiping a row left deletes it.
    - "+ Add visit" logs another visit. A log can link to an editable trip and tag current friends under With.
      A tag appears immediately to eligible viewers. Each friend logs their own visit.
    - New logs start with Friends. Public is visible to signed-in Roam members. Editing a log keeps its saved
      audience unless you change it.
  - **People who've been:** a titleless card. "You" comes first with your stars, then each friend with when they last
    went and their stars. Tapping a friend opens their profile. Long-pressing a friend offers Report.
  - **Everyone else:** other people's visits, with All photos opening the photo viewer.

## Trip page

- **Header:**
  - The name with an edit icon, which opens a sheet to rename the trip.
  - Start → End date bubbles, edited right there.
  - The owner can delete the trip and manage invitations from the People card. Invitees accept or decline in My Places
    under Trip invitations. Accepted members can edit the itinerary and dates, log their own visits, and leave.
- **Places:**
  - **One country:** each city as a big photo card that opens the city.
  - **Several countries:** one card per country, with the country's photo on top (opens the country) and its cities as
    rows (each opens the city).
  - Swiping a city or country deletes it from the trip.
- **Visits:** Scroll below the itinerary to see the places logged on the trip, with who went and when. Tap a row to
  open its activity, or the place if it has no activity. This section appears once there's a visit you can see.
- **Add to trip:** opens the city search.

## Lists and Sent to you

- **Lists** (My Places › Saved › Lists): your lists as standard rows (name, number of places), then lists friends sent
  you, and a New list bubble that names it and opens it.
- **A list:** its name big, with an edit pencil on your own (rename) and, at the top right, Send (indigo) then a red bin (delete). A list is private: only friends you send it to can
  open it. A friend's
  list has a small chip with their picture and name, opening their profile. Then
  its places as standard rows in one card (swipe left to remove one from your own list), then a green "Add a place"
  bubble. That opens the place search: tapping a result adds it with a tick, tapping again takes it off; × closes.
- From a place's page, Add to list shows your lists as rows (tap one to add), a new list by name, and an optional note.
- Recipients open the current contents from Lists or Sent to you. Sent to you includes the sender and their note.

## Settings

- Your profile row opens Edit profile: photo, name, handle, bio, and home cities (add any number, swipe to remove).
  Cancel with changes asks to discard them.
- Your tastes: five optional questions (atmosphere, budget, crowds, novelty, pace) that go into Plan with AI prompts.
  Suggestions don't use them; they learn from your rankings.
- Account: email, sign out, delete account. Deleting an Apple account asks for a fresh Apple sign-in
  so Roam can revoke its Apple authorization while removing the account.
- Safety: Blocked people and Muted people (each can be undone from its list) and Your reports (status of reports
  you filed).
- About: Support, Privacy, Terms of use and version. Support and Terms end with a Contact card that emails the
  support address; Privacy ends with a link to the full published policy. Both come from `ROAM_SUPPORT_EMAIL` and
  `ROAM_PRIVACY_POLICY_URL`; Release builds fail without them, and Debug builds without them hide the links.

## Sheets

- **Log a place (opened from Log or + Add visit):**
  - The name with its city under it.
  - The feeling picker: Didn't like, Neutral or Liked it. It starts at Neutral.
  - A date chip: × clears it, and tapping it opens a calendar. Tapping a day picks it; Done picks the day shown.
  - The note has no Done button: tapping anywhere off it drops the cursor and puts the keyboard away, as does scrolling.
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

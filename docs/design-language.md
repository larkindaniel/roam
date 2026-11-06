# Roam design language

How Roam's screens look, the shared pieces they're built from, and how to make new components so they match. Read this
before building or changing any UI. Reuse what's here first. When something new is needed, build it from these tokens
and patterns, then add it to this page. `docs/screens.md` describes each screen and how it behaves.

## Principles

- **Look first-party iOS 26.** Use system patterns and Liquid Glass. Don't invent decoration, borders, gradients or
  custom chrome.
- **Simple and quiet.** One idea per card. No explanation paragraphs, hint lines or counts nobody asked for (no
  "12 places" on a city). Don't repeat what's already on screen.
- **Marks over headings.** Cards are usually untitled: the coloured mark on each row says what it is (been, saved,
  trip, home).
- **Short, plain words.** "Been", not "Been here". A destructive choice is just "Delete".
- **Reuse before you build.** Every row, card, button and chip below already exists. Match it exactly (sizes, fonts,
  spacing). If a new screen needs a row, it's the standard row.

## Tokens (`Roam/DesignSystem/Theme.swift`)

| Token | Use |
|---|---|
| `Roam.paper` (#F2F2F7) | Page background: Apple's grouped grey |
| `Roam.paperRaised` | Cards: off-white, set apart by a soft shadow, never a border |
| `Roam.ink` / `inkMuted` / `inkFaint` | Text: primary, secondary (subtitles, dates, notes), disabled |
| `Roam.fill` | Grey fills: chips, grey buttons, placeholders, row lines |
| `Roam.ruleOnGlass` | Row lines on a see-through card |
| `Roam.signal` / `Theme.destructive` | Errors and destructive actions only |
| `Theme.Spacing` | xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 |
| `Theme.cornerRadius` | 26, continuous (squircle). Anything nested inside a card uses a smaller radius so the curves stay concentric (a photo inset 6pt in a card uses `cornerRadius - 6`) |
| `Font.roamTitle()` | Rounded bold title2: page names, card titles, names on photos |

Type ramp elsewhere is system: `.headline` for row titles, `.footnote` in `inkMuted` for the line under them,
`.subheadline` for chips and stars, `.caption2` for captions under round buttons.

## Colour means state

Photos and these state colours are the only colour in the app. Use them consistently on buttons, marks, pins, globe
fills and selectors.

| State | Colour | Symbol | `PlaceState` |
|---|---|---|---|
| Been | green | `checkmark` | `.visited` |
| Going / trip | blue | `airplane` | `.planned` |
| Saved / wishlist | yellow | `bookmark.fill` | `.wishlist` |
| Home | black (`Roam.home`) | `house.fill` | `StatusMark(symbol:color:label:)` |
| Plan with AI | pink | `sparkles` | `Color.pink` |

Get colours from `PlaceState.markerColor` and symbols from `markerSymbol`. Never hard-code them.

- **Been beats wishlist** everywhere: once you've been somewhere it's off your wishlist, and Save/Wishlist shows
  greyed out.
- **Send** isn't built yet, so it's always shown greyed out (`inkFaint`).

## Cards

- `.roamCard()` is the standard card surface. Use `.roamCard(padding: Theme.Spacing.m)` for a card of rows.
- **Photo-topped card** (a city's photo with rows under it, as on a multi-country trip and the Friends tab):
  `.roamCard(padding: 0)`, with the photo inset `6pt` and its corners at `Theme.cornerRadius - 6`.
- Inside a swipe-up card short of fully up, cards turn see-through grey automatically (`\.onGlass`).

## Rows: the standard row

Every list of places, cities, trips, visits and friends uses one row anatomy:

```
[48pt photo + small mark]  Title (headline, 1 line, … if long)          [chevron or ★ 4.2]
                           subtitle (footnote, inkMuted)
```

- **Photo:** `PlaceThumbnail(size: 48)`. Mark at the bottom right:
  `StatusMark(state:).scaleEffect(0.75).offset(x: 6, y: 6)`. People get `AvatarView(size: 48)` in its place.
- **Title:** `.headline`, `lineLimit(1)`, `.truncationMode(.tail)`.
- **Subtitle:** `.footnote` in `inkMuted`. When it's a date or a note's first line, tuck it right under the title with
  `VStack(spacing: -2)`.
- **Right side:** a chevron (`chevron.right`, `.caption.weight(.semibold)`, `inkMuted`) when tapping opens something,
  or friends' stars.
- **Padding and lines:** `.padding(.vertical, Theme.Spacing.s)`. Put `RowSeparator()` between rows, never after the
  last one. The line starts after the photo, is a solid 1pt and goes darker on glass by itself.
- **Ready-made rows:** `PlaceRow`, `CityRow`, `TripRow` (`Features/Lists/MyPlacesSections.swift`), `MyVisitsCard`
  (your visits), `FriendMemoriesSection` (You plus friends on a place), `FriendCityCard` (the Friends tab).
- **Swipe to delete:** a `List`'s `.swipeActions` with a red Delete, or `SwipeToDelete` for rows inside a card.

## Photo cards

- `HeroPhotoCard` (`Features/Lists/MyPlacesTabs.swift`) is the big card: a 210pt photo edge to edge, darkening at the
  bottom, with the name in white `roamTitle` and a white line under it at `-3` spacing.
- `CityHeroCard` and `CountryCoverCard` wrap it with the right Google or Wikipedia photo. `DiscoverPlaceCard` adds the
  stars at the bottom right. All of them take `cornerRadius` for nesting.
- Lists of countries: big cards up to nine, then a two-across grid from ten.
- Photos come from your own logs first, then Google, then Wikipedia. With no photo, a full-colour map with the place's
  pin shows instead.

## Buttons

- **Round action buttons** (place, city, country pages): a 38pt circle with the symbol at `.headline`, the state colour
  at 0.15 opacity behind it (solid colour with a white symbol once that state is on), and a `.caption2` caption
  underneath. Spread them evenly. Once a state is on, its button fills in; buttons that no longer apply grey out.
- **Full-width bubble:** a 44pt capsule filled with the colour at 0.15 opacity, the label in that colour, with a `plus`
  icon (`+ Add visit` green; `+ New trip`, `Add to trip` and `Add a city` light blue; `Add places` and `Add photos`
  grey with black text).
- **Directions:** a solid blue 38pt circle (`arrow.triangle.turn.up.right.diamond.fill`). It opens a confirmation
  dialog with no title and two choices: Apple Maps and Google Maps.
- **Settings:** `SettingsToolbarItem`, a cog in its own glass circle at the top right of each tab.
- **Inside a swipe-up card's header,** use `onTapGesture` with `.accessibilityAddTraits(.isButton)` and an
  `accessibilityAction` instead of `Button`. Buttons there don't receive taps.

## Chips, dates and fields

- **City chip:** a slim grey capsule 24pt tall with `.subheadline.weight(.medium)` text, a small `chevron.right` and
  `Roam.ink.opacity(0.08)`. It opens the city.
- **Google rating:** one small line, `★ 4.6 (1.2K)`, beside the city chip. The count is grey.
- **Date ranges:** `DateRangeRow`, two pills `Start → End` with calendar icons. Each opens a calendar in a popover,
  starts empty and has Remove date.
- **Single date on the log screen:** a chip showing the date with an `xmark.circle.fill` on its right to clear it.
  Tapping anywhere else opens a graphical calendar in a popover that closes when you pick a day.
- **Text fields:** no autocapitalisation or autocorrect on search, names or notes. Notes use `NoteBox`, a roomy box
  that takes new lines. Search fields end with their own ×, not a Cancel button.

## Floating chrome and sheets

- **Tab bar:** Roam draws its own floating glass `RoamTabBar` (`App/MainTabView.swift`). Hide it with
  `.roamTabBar(hidden:)`, never `.toolbar(.hidden, for: .tabBar)`. Scrolling pages keep their last item clear of it
  (`contentMargins(.bottom, RoamTabBar.reservedHeight + Theme.Spacing.l, for: .scrollContent)`). Tapping a tab returns
  it to its home page, scrolled to the top.
- **Glass over maps:** `floatingBubble(_:tint:)` gives Liquid Glass on iOS 26 and frosted material before it.
- **Swipe-up cards:** `GlobeSheetLayout`, modelled on the Apple Maps sheet. It has three heights:
  1. **Peek:** a floating bubble, most see-through.
  2. **Half:** narrow margins, see-through grey inner cards.
  3. **Full:** solid and edge to edge, white inner cards, and the tab bar shows.

  The header stays fixed; scrolling replaces it with a dark fade showing just the name.
- **Sheets:** a round × at the top right closes them. If something is filled in, the × asks "Discard …?". Save sits at
  the bottom as see-through glass. Nothing is kept as a draft.
- **Confirmations:** one confirmation only, raised from the button that triggered it, with "Delete" as the destructive
  choice.

## Other shared pieces

- **Feeling picker** (`FeelingSlider`): a grey track with a raised pill, like My Places' Saved/Been selector. The pill
  is red, white or green for Didn't like, Neutral or Liked it. New logs start at Neutral.
- **Photo gallery** (`PlaceGallery`): swipeable pages with white dots in a dark capsule at the bottom. No counter and
  no arrows.
- **Segmented selector** (My Places): one track with the chosen segment's pill sliding across in its state colour.
- **Loading:** `SkeletonCards` where photo cards will appear, `SkeletonList` where rows will. Errors use
  `InlineRetryView` with Try again.
- **Search results:** `PlaceSearchResults` is shared by Discover, My Places and city pages. Cities show the signpost
  icon, countries show their flag, and towns never appear as places.
- **Flags:** write the country, then its flag: `Japan 🇯🇵` (`TripTitle.flag`). Country names are plain ("China", not
  "China mainland").

## Scores

- Roam's own scores are computed but hidden (`Score.isShown == false`).
- Stars appear in exactly two places, both drawn explicitly with
  `Label(score.formatted, systemImage: "star.fill")`:
  - **Friends' ratings** of a place.
  - **Your own rating,** as the "You" row on a place page.
- Stars are always out of 5. Storage and ranking stay out of 10.
- Google's rating is kept separate and is never blended with Roam's.

## Spacing habits

- Sections on a page: `VStack(spacing: Theme.Spacing.xl)`. Cards in a list: `Theme.Spacing.l`.
- A subtitle hugs its title (`-2` or `-3`). Leave a little more room before the next card than between the lines of a
  header.
- Corners of a sheet at the bottom of the screen follow the screen's own corners. Side margins are wider than bottom
  margins, because the screen corners curve in.

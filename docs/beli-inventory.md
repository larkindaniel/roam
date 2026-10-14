# Beli screen and flow inventory — evidence draft

Capture date: 2026-10-13 (America/Toronto). Initial review boundary: screenshots 01–301. Capture remains active; later additions are tracked separately below if reviewed. This is an inventory, not permission to implement. Reference files are read-only.

**Live-session update:** A separate new-account session now documents B41–B44: onboarding, first-use teaching, the first three ratings, comparison/Too tough, own rated detail, deletion and feed empty state. See the [53-file visual-review ledger and detailed inventory](beli-live-capture-addendum.md). These files are in `docs/captures/`; `reference/beli/` remains untouched. Numeric score reveal, larger-list comparison sequences and public posting behavior are still pending.

## Evidence rules

- **Observed (visual):** visible pixels inspected in grouped contact sheets, with individual full-size checks for representative repeated content and ambiguous controls. Every distinct layout/state in the initial boundary was inspected; repeated content is explicitly sampled.
- **Observed (flow notes):** actions/scroll behavior reported by `reference/beli/flows.md`, cross-checked against available before/after images. This review did not control the app. Static images alone do not verify persistence, animation, backend behavior or successful writes.
- **Inference:** interpretation of an affordance, or proposed reuse of a pattern. No inference establishes Beli’s private algorithms.
- **Unknown / pending:** missing, inaccessible, or untested. Empty, locked, loading and permission-denied are separate states. Proposals belong in the Roam map/spec.
- Filenames below link to the immutable reference. Contact-sheet derivatives were made only in `/tmp/roam-review/`; no reference was edited. All per-file review dispositions are in the ledger.

## Screen families and flows

### B01 — Application shell

**Evidence:** [01-profile-overview-a.png](../reference/beli/01-profile-overview-a.png), [04-profile-overview-loaded.png](../reference/beli/04-profile-overview-loaded.png), [59-profile-been-b.png](../reference/beli/59-profile-been-b.png), [173-feed-home-a.png](../reference/beli/173-feed-home-a.png), [188-search-restaurants-initial.png](../reference/beli/188-search-restaurants-initial.png), [230-search-explore-location-gate.png](../reference/beli/230-search-explore-location-gate.png).

**Observed purpose, layout, components and data:** Five bottom destinations: Feed, Your Lists, central circular plus labeled Search, Explore, Profile. White surfaces, fine separators, compact sans-serif body text, teal actions and outline icons; large serif place/modal headings. Search is a destination with close X, not evidence of a direct post composer. Mirroring toolbar, cursor, phone frame and status bar are capture chrome, not app components.

**Navigation, controls and scrolling:** Flow notes record launch → Feed → Profile; Profile Been switches to Your Lists. Root lists/feed/profile retain bottom tabs; dedicated forms, photo viewer and comment detail often replace them with their own navigation. Back arrows pop detail views; X closes overlays.

**Available states:** Active destinations use darker icon/text; unavailable sections use locks. Persistent top controls can be compared across scroll captures.

**Unknowns / inference boundary:** Cross-tab stack restoration, interactive-back gestures, animation durations, haptics and deep-link routing are not verified.

### B02 — Own profile overview and suggested members

**Evidence:** [01-profile-overview-a.png](../reference/beli/01-profile-overview-a.png), [04-profile-overview-loaded.png](../reference/beli/04-profile-overview-loaded.png), [08-profile-suggested-people-a.png](../reference/beli/08-profile-suggested-people-a.png), [09-profile-suggested-people-b.png](../reference/beli/09-profile-suggested-people-b.png), [10-profile-suggested-people-c.png](../reference/beli/10-profile-suggested-people-c.png).

**Observed purpose, layout, components and data:** Pinned name/share/menu header; centered avatar or initials, handle, joined date, Add School, follower/following/rank stats; Edit profile, Share profile and dropdown. Been/Want/Recs rows with counts or lock, two rank/streak cards and annual-goal card. Dropdown reveals horizontal contact/member cards with avatar, Follow, dismiss X and See all.

**Navigation, controls and scrolling:** Profile tab → overview; dropdown expands suggestions; vertical body scrolls under fixed name header and above tab bar. Lists and count links lead to their dedicated surfaces.

**Available states:** Zero Been/Want, locked recommendations/rank; loaded cards. Suggestions expanded and scrolled. Initial placeholders are reported in notes but not separately established by these loaded images.

**Unknowns / inference boundary:** Edit/share-profile forms, suggestion dismissal/follow outcomes and See all destination are pending.

### B03 — Followers and following

**Evidence:** [05-profile-followers-a.png](../reference/beli/05-profile-followers-a.png), [06-profile-following-a.png](../reference/beli/06-profile-following-a.png), [07-profile-following-no-results.png](../reference/beli/07-profile-following-no-results.png), [271-friend-following-loading.png](../reference/beli/271-friend-following-loading.png), [272-friend-following-a.png](../reference/beli/272-friend-following-a.png), [273-friend-followers-a.png](../reference/beli/273-friend-followers-a.png).

**Observed purpose, layout, components and data:** Back/handle header, two count tabs with active underline, search field, Find friends row, vertically stacked avatar/name rows. Buttons distinguish Follow back, Following and Follow. Other-member lists use same shell.

**Navigation, controls and scrolling:** Profile count → list; segment switches follower/following; query filters. Standalone page has no root tab bar in reviewed captures.

**Available states:** Populated self/other lists; unmatched query shows centered No results; other-member Following has avatar/text skeletons.

**Unknowns / inference boundary:** Follow/unfollow persistence, pagination boundaries and Find friends route were not exercised. Alphabetical-looking rows do not establish every list’s ordering rule.

### B04 — Profile activity

**Evidence:** [11-profile-activity-a.png](../reference/beli/11-profile-activity-a.png), [12-profile-activity-empty-b.png](../reference/beli/12-profile-activity-empty-b.png), [13-profile-activity-empty-c.png](../reference/beli/13-profile-activity-empty-c.png), [275-friend-activity-a.png](../reference/beli/275-friend-activity-a.png).

**Observed purpose, layout, components and data:** Activity/Taste Profile/Guides (Custom Guides on paid creator profile) tab strip below profile summary. Own Activity centers No recent activity, explanation and Start ranking. Other profile embeds ranking cards with score, photo, note, visit and social actions.

**Navigation, controls and scrolling:** Lower profile tab selection changes body; header and bottom tabs remain while whole profile scrolls. Start ranking visible; downstream path not tested.

**Available states:** Empty own activity and populated other-member activity.

**Unknowns / inference boundary:** Bookmark and accomplishment activity types are mentioned in empty copy; their profile layouts are not independently captured.

### B05 — Taste statistics, calendar and geographic breakdown

**Evidence:** [14-profile-taste-locked-a.png](../reference/beli/14-profile-taste-locked-a.png), [15-profile-taste-locked-b.png](../reference/beli/15-profile-taste-locked-b.png), [16-profile-taste-locked-c.png](../reference/beli/16-profile-taste-locked-c.png), [17-profile-taste-locked-d.png](../reference/beli/17-profile-taste-locked-d.png), [18-profile-taste-locked-e.png](../reference/beli/18-profile-taste-locked-e.png), [19-profile-taste-locked-f.png](../reference/beli/19-profile-taste-locked-f.png), [20-profile-taste-locked-g.png](../reference/beli/20-profile-taste-locked-g.png), [21-profile-taste-locked-h.png](../reference/beli/21-profile-taste-locked-h.png), [22-profile-taste-locked-i.png](../reference/beli/22-profile-taste-locked-i.png), [23-profile-taste-cuisines-empty.png](../reference/beli/23-profile-taste-cuisines-empty.png), [24-profile-taste-sort-menu.png](../reference/beli/24-profile-taste-sort-menu.png), [25-profile-taste-cities-empty.png](../reference/beli/25-profile-taste-cities-empty.png), [26-profile-taste-countries-empty.png](../reference/beli/26-profile-taste-countries-empty.png), [264-friend-taste-a.png](../reference/beli/264-friend-taste-a.png), [265-friend-taste-cuisines.png](../reference/beli/265-friend-taste-cuisines.png), [266-friend-taste-cities.png](../reference/beli/266-friend-taste-cities.png), [267-friend-taste-countries.png](../reference/beli/267-friend-taste-countries.png), [268-friend-taste-sort.png](../reference/beli/268-friend-taste-sort.png), [269-friend-taste-average-score.png](../reference/beli/269-friend-taste-average-score.png), [270-friend-taste-cities-middle.png](../reference/beli/270-friend-taste-cities-middle.png).

**Observed purpose, layout, components and data:** Own Taste stacks locked blurred purple stats, white calendar and world-map cards. Bottom Cuisines/Cities/Countries segment, total count, Count/Avg. Score sort sheet. Other profile shows last-30-days activity percentile, place/cuisine counts and city; flat world map with city dots and city/place totals; rows have label, place count, score circle and chevron. These are Beli summary averages, not proof of balanced city scoring.

**Navigation, controls and scrolling:** Taste tab → segment → sort sheet. Notes and images support Count → Avg. Score reordering. Profile header and bottom bar persist; summary cards scroll away. Geographic row drill-down is only a visible affordance.

**Available states:** First-rating locks; zero cuisines/cities/countries; populated segments; average-score sorted countries/cities. Friend calendar is not shown.

**Unknowns / inference boundary:** Calendar interaction, row drill-down, expanded map, score aggregation and percentile formula unknown. No interactive 3D globe or shaded countries observed.

### B06 — Goals, rank unlock, streak and personalized-rec gates

**Evidence:** [27-profile-guides-empty.png](../reference/beli/27-profile-guides-empty.png), [28-profile-goal-form.png](../reference/beli/28-profile-goal-form.png), [29-profile-goal-cancel-confirm.png](../reference/beli/29-profile-goal-cancel-confirm.png), [30-profile-rank-locked-dialog.png](../reference/beli/30-profile-rank-locked-dialog.png), [31-profile-streak-card.png](../reference/beli/31-profile-streak-card.png), [32-profile-recs-locked-dialog.png](../reference/beli/32-profile-recs-locked-dialog.png), [132-lists-guides-locked-dialog.png](../reference/beli/132-lists-guides-locked-dialog.png).

**Observed purpose, layout, components and data:** Own Guides empty copy says rank 30 restaurants; Guides modal adds at least 10 in a city. Annual goal form has gradient year banner, X, numeric field, 20/50/100 presets, Set goal; exit confirmation Skip/Set my goal. Rank modal shows 0/50 with Rank more/Close. Recs modal asks for more rankings without a numeric threshold. Streak is full-screen orange gradient, flame/count/handle, back arrow and bottom sharing-target tray.

**Navigation, controls and scrolling:** Overview cards and Guides/Recs tabs open forms/modals. Goal X leads to skip confirmation (notes); dismissal does not save. Streak back returns; sharing targets untouched.

**Available states:** Zero-week streak, locked rank/recs/guides, goal default and cancel confirmation.

**Unknowns / inference boundary:** Goal saved/progress/completion, actual rank leaderboard rules, nonzero own streak, recommendation algorithm and unlocked own guides unknown. Threshold copy is observed Beli policy, not automatically a Roam requirement.

### B07 — Own Been starter list and list search

**Evidence:** [02-profile-been-a.png](../reference/beli/02-profile-been-a.png), [56-profile-been-search-empty.png](../reference/beli/56-profile-been-search-empty.png), [57-profile-been-search-no-results.png](../reference/beli/57-profile-been-search-no-results.png), [59-profile-been-b.png](../reference/beli/59-profile-been-b.png), [85-profile-been-ab.png](../reference/beli/85-profile-been-ab.png), [117-profile-been-bh.png](../reference/beli/117-profile-been-bh.png).

**Observed purpose, layout, components and data:** MY LISTS header with share/overflow, All dropdown and horizontal Been/Want/Recs/Guides/More strip. Empty personal ranking contains unlock progress, camera-roll CTA and suggested places; rows show name/location plus add, bookmark and X. No rank numbers or personal scores on these starter rows. Search mode replaces starter body with query/clear/Close and blank results.

**Navigation, controls and scrolling:** Profile Been or Your Lists → Been. Name/category/tabs and bottom navigation stay pinned across long suggestion scroll. Flow notes say a long-press on La Pecora row opened detail, not a context menu.

**Available states:** Starter list top/middle/later rows; empty query and unmatched query (blank body without No results label). 59–117 are mostly repeated suggestion rows; no proven terminal bottom.

**Unknowns / inference boundary:** Own populated/rated rows, edit/delete/rerank, photo import and dismiss/bookmark outcomes not captured. Screenshot 02 already includes dimmed share overlay, so use 59/85/117 for unobstructed rows.

### B08 — List share and overflow

**Evidence:** [03-profile-been-share-options.png](../reference/beli/03-profile-been-share-options.png), [33-profile-been-options.png](../reference/beli/33-profile-been-options.png), [242-lists-trending-overflow.png](../reference/beli/242-lists-trending-overflow.png), [246-friend-been-overflow.png](../reference/beli/246-friend-been-overflow.png).

**Observed purpose, layout, components and data:** Share-choice sheet offers full-list link or selected places. Own overflow offers filter/search/full-link/select places/Gmail reservations/photo-library import. Trending overflow has filter/search/select places. Other-member list overflow has filter/search owner list/full-link. Do not assume all contexts expose identical actions.

**Navigation, controls and scrolling:** Overflow icons open bottom sheets. Intended share-icon path to 03 is uncertain in notes; original backdrop became black and dismissal failed, later recovered. No sharing option selected.

**Available states:** Context-specific action sheets; stuck/black backdrop state in 03.

**Unknowns / inference boundary:** Selection editor, generated cards, full-list link behavior and imports from these controls unknown; black backdrop is an anomaly, not a pattern to reproduce.

### B09 — Category, sorting and personal filter sheet

**Evidence:** [34-profile-been-filters-a.png](../reference/beli/34-profile-been-filters-a.png), [35-profile-been-filters-good-for.png](../reference/beli/35-profile-been-filters-good-for.png), [36-profile-been-filters-city.png](../reference/beli/36-profile-been-filters-city.png), [37-profile-been-filters-score.png](../reference/beli/37-profile-been-filters-score.png), [38-profile-been-filters-friends.png](../reference/beli/38-profile-been-filters-friends.png), [39-profile-been-filters-cuisine.png](../reference/beli/39-profile-been-filters-cuisine.png), [40-profile-been-filters-price.png](../reference/beli/40-profile-been-filters-price.png), [41-profile-been-filters-borough.png](../reference/beli/41-profile-been-filters-borough.png), [42-profile-been-filters-neighborhood.png](../reference/beli/42-profile-been-filters-neighborhood.png), [43-profile-been-filters-country.png](../reference/beli/43-profile-been-filters-country.png), [44-profile-been-category-restaurants.png](../reference/beli/44-profile-been-category-restaurants.png), [45-profile-been-category-bars.png](../reference/beli/45-profile-been-category-bars.png), [46-profile-been-category-bakeries.png](../reference/beli/46-profile-been-category-bakeries.png), [47-profile-been-category-coffee.png](../reference/beli/47-profile-been-category-coffee.png), [48-profile-been-category-dessert.png](../reference/beli/48-profile-been-category-dessert.png), [49-profile-been-category-all.png](../reference/beli/49-profile-been-category-all.png), [50-profile-been-sort-score.png](../reference/beli/50-profile-been-sort-score.png), [51-profile-been-sort-distance.png](../reference/beli/51-profile-been-sort-distance.png), [52-profile-been-sort-date-added.png](../reference/beli/52-profile-been-sort-date-added.png), [53-profile-been-filter-reserve.png](../reference/beli/53-profile-been-filter-reserve.png), [54-profile-been-filter-open-now.png](../reference/beli/54-profile-been-filter-open-now.png), [55-profile-been-filter-order.png](../reference/beli/55-profile-been-filter-order.png), [58-profile-been-category-sheet.png](../reference/beli/58-profile-been-category-sheet.png).

**Observed purpose, layout, components and data:** Draggable white sheet with X. Category chips All/Restaurants/Bars/Bakeries/Coffee & Tea/Ice Cream & Dessert; Score/Distance/Date added segmented sort; Reserve/Open now/Order chips. City, Good For, Score, Number of friends, Cuisine, Price, Borough, Neighborhood, Country accordion rows. Expanded empty-data sections show search where available, not invented slider controls. Clear all/Apply footer remains visible; Apply (1) appears for a selected quick filter.

**Navigation, controls and scrolling:** Overflow → Filter; All dropdown opens smaller category-only sheet. Notes report mutually exclusive categories and accordion collapse. Sheet content scrolls independently of fixed footer. Captured changes remained unapplied.

**Available states:** Every category selected; each sort selected; quick-filter snapshots; expanded empty accordions. 55 does not visibly establish a selected Order state despite filename/notes, so only the control’s presence is certain.

**Unknowns / inference boundary:** Applied filter effects, score/friend-count value choices and combination semantics unknown; do not infer validation or persistence from an unapplied sheet.

### B10 — Want to Try and list imports

**Evidence:** [119-profile-want-to-try-empty-a.png](../reference/beli/119-profile-want-to-try-empty-a.png), [120-lists-import-menu.png](../reference/beli/120-lists-import-menu.png), [121-lists-import-google-maps-form.png](../reference/beli/121-lists-import-google-maps-form.png), [122-lists-import-paste-form.png](../reference/beli/122-lists-import-paste-form.png), [123-lists-import-foursquare.png](../reference/beli/123-lists-import-foursquare.png), [124-lists-import-mapstr.png](../reference/beli/124-lists-import-mapstr.png).

**Observed purpose, layout, components and data:** Want empty state includes dismissible import card, Nothing here yet and suggestion rows. Import landing has four large buttons. Google Maps form: public-list URL, unsupported My Maps note, disabled Begin Import. Paste form: city plus multiline one-place-per-line textarea and disabled Begin Import. Foursquare/Mapstr screens explain exporting files and emailing them, with Submit exported list.

**Navigation, controls and scrolling:** Want → Import → provider → back. Main Want has root tabs and pinned availability strip; import forms are standalone back-navigation pages.

**Available states:** Empty Want, blank import forms, instruction-only provider pages.

**Unknowns / inference boundary:** Import validation, review/matching, duplicates, progress/success/failure and external-email behavior not tested. No imported places or ranked imports verified.

### B11 — Reservation availability

**Evidence:** [118-place-la-pecora-reservation-tip.png](../reference/beli/118-place-la-pecora-reservation-tip.png), [125-lists-availability-form.png](../reference/beli/125-lists-availability-form.png), [137-place-don-angie-detail-a.png](../reference/beli/137-place-don-angie-detail-a.png), [207-search-curated-list-l.png](../reference/beli/207-search-curated-list-l.png).

**Observed purpose, layout, components and data:** First-use reservation tooltip overlays place. Availability sheet has horizontal party sizes, All Day time control, month navigation/calendar with selected date, Search CTA. Detail/curated entries show partner logo, horizontal time slots or no-availability text. Curated middle 207 verifies actual time-slot variant.

**Navigation, controls and scrolling:** Pinned party/date/time pencil → sheet; dismiss without search. Slot booking not used.

**Available states:** Tooltip, selected party/date, no tables, live-looking slots; bakery lacks reservation section.

**Unknowns / inference boundary:** Booking checkout, provider handoff, cancellation and time-selection behavior unknown.

### B12 — List picker and friends recommendations

**Evidence:** [126-lists-more-picker.png](../reference/beli/126-lists-more-picker.png), [127-lists-friend-recs-intro.png](../reference/beli/127-lists-friend-recs-intro.png), [128-lists-friend-recs-a.png](../reference/beli/128-lists-friend-recs-a.png), [129-lists-friend-recs-sort-menu.png](../reference/beli/129-lists-friend-recs-sort-menu.png).

**Observed purpose, layout, components and data:** More sheet uses six tiles with counts/locks: Been, Want, Recs for You, Guides, Recs from Friends, Trending. Friend-recs introduction explains friends-ranked places. Populated rows show score circle with friend-count badge, price/cuisine/location/hours, add/bookmark. Filter-chip rail, sort/search row and floating View Map sit above root tabs.

**Navigation, controls and scrolling:** More → Friend Recs → introduction Got it → rows; sort opens Score/Distance/Number of friends sheet; place row opens detail.

**Available states:** Intro and populated list, Distance sort shown.

**Unknowns / inference boundary:** Filtering eligibility, aggregation beyond tooltip description, rec algorithm, intro-repeat policy and action outcomes unknown.

### B13 — Location permission and list maps

**Evidence:** [130-lists-distance-location-prompt.png](../reference/beli/130-lists-distance-location-prompt.png), [131-lists-map-location-system-prompt.png](../reference/beli/131-lists-map-location-system-prompt.png), [133-lists-map-location-gate.png](../reference/beli/133-lists-map-location-gate.png), [230-search-explore-location-gate.png](../reference/beli/230-search-explore-location-gate.png).

**Observed purpose, layout, components and data:** Pre-permission illustration modal with Allow/Not now; native precise-location prompt with once/while-using/deny; denied Your Map and Explore pages with illustration and Open Settings. List-map gate retains View List and root chrome.

**Navigation, controls and scrolling:** Distance/map entries lead to permission surfaces; notes record native denial. Explore tab opens denied gate. Curated fixed-city maps work separately (B23).

**Available states:** Pre-permission, system prompt and denied gates.

**Unknowns / inference boundary:** Granted-location personal map, Explore controls, approximate location and Settings-return behavior not captured. Permission timing was asynchronous in notes.

### B14 — City filter

**Evidence:** [134-lists-city-filter-a.png](../reference/beli/134-lists-city-filter-a.png), [135-lists-city-filter-results.png](../reference/beli/135-lists-city-filter-results.png), [136-lists-city-filter-no-results.png](../reference/beli/136-lists-city-filter-no-results.png).

**Observed purpose, layout, components and data:** White sheet with title/X/search, current-city shortcut and alphabetic checkbox rows. Pinned Clear All/Apply; matching query narrows rows, unmatched query leaves blank choices.

**Navigation, controls and scrolling:** Friend Recs City chip → sheet → type → clear/X. No selections applied.

**Available states:** Initial, two matches, zero matches.

**Unknowns / inference boundary:** Multiselect application, city identifiers, pagination and restored selection unknown.

### B15 — Place detail and scores

**Evidence:** [137-place-don-angie-detail-a.png](../reference/beli/137-place-don-angie-detail-a.png), [143-place-rec-score-explanation.png](../reference/beli/143-place-rec-score-explanation.png), [144-place-friend-score-explanation.png](../reference/beli/144-place-friend-score-explanation.png), [145-place-average-score-locked.png](../reference/beli/145-place-average-score-locked.png), [146-place-don-angie-detail-b.png](../reference/beli/146-place-don-angie-detail-b.png), [147-place-don-angie-detail-c.png](../reference/beli/147-place-don-angie-detail-c.png), [181-place-arome-detail-b.png](../reference/beli/181-place-arome-detail-b.png), [182-place-arome-detail-c.png](../reference/beli/182-place-arome-detail-c.png), [187-place-arome-detail-a.png](../reference/beli/187-place-arome-detail-a.png).

**Observed purpose, layout, components and data:** Map-backed large serif title; back/share/overflow, add/bookmark, curated-list chips, good-for tags, price/cuisine/location and Website/Call/Directions. Horizontal score area: predicted Rec, friends score/count, locked average. Tooltips describe proprietary prediction and average of friends; invite gate for community averages. Below: optional reservation, popular-dish carousel, locked distribution, About/hours, notes accordion and friend reviews. Bakery demonstrates wrapping title, closed state and no reservation module.

**Navigation, controls and scrolling:** List/search/feed → place. Scrolling replaces expanded map hero with compact title/back/share/overflow; bottom tabs remain. Score circles open explanation overlays; locked average opens invite modal.

**Available states:** Loaded unranked places, open/closed, populated friend score, locked community histogram, photo loading placeholders. Both examples are unranked by current user.

**Unknowns / inference boundary:** Own-rated header, unlocked distribution, zero-friend score, failed-place load, predictive math and any map-hero gestures unknown.

### B16 — Place utility and edit-suggestion forms

**Evidence:** [138-place-don-angie-options.png](../reference/beli/138-place-don-angie-options.png), [139-place-suggest-edit-menu.png](../reference/beli/139-place-suggest-edit-menu.png), [140-place-suggest-cuisines-form.png](../reference/beli/140-place-suggest-cuisines-form.png), [141-place-suggest-price-form.png](../reference/beli/141-place-suggest-price-form.png), [148-place-opening-hours.png](../reference/beli/148-place-opening-hours.png), [149-place-hours-suggestion-menu.png](../reference/beli/149-place-hours-suggestion-menu.png), [150-place-hours-edit-form.png](../reference/beli/150-place-hours-edit-form.png), [170-place-call-confirm.png](../reference/beli/170-place-call-confirm.png), [171-place-directions-menu.png](../reference/beli/171-place-directions-menu.png).

**Observed purpose, layout, components and data:** Overflow utilities include Website/Directions/Call/Suggest an edit. Edit menu exposes cuisine/price, closed, wrong location/name/hours, reservation issue, duplicate and other. Cuisine form permits up to three chips with search and Cancel/Save. Price form has $, $$, $$$, $$$$ and current $$$. About expands seven-day hours including split service; hours sheet offers report or text schedule editor. Native call confirm; directions menu Apple Maps/Google Maps/Copy address.

**Navigation, controls and scrolling:** Place overflow → edit menu → form → Cancel; About hours → Suggest new hours → editor → Cancel. Phone confirmation cancelled; navigation-provider options untouched.

**Available states:** Existing cuisine/price selection, expanded hours and prefilled schedule, native call prompt.

**Unknowns / inference boundary:** Edit approval pipeline, report forms, save validation, provider-opening results and hours structure unknown. Corrects malformed price notation in flow descriptions without changing originals.

### B17 — Place notes, labels and highlights

**Evidence:** [151-place-your-notes-actions.png](../reference/beli/151-place-your-notes-actions.png), [152-place-guides-labels-form.png](../reference/beli/152-place-guides-labels-form.png), [153-place-favorite-dishes-form.png](../reference/beli/153-place-favorite-dishes-form.png), [154-place-personal-notes-form.png](../reference/beli/154-place-personal-notes-form.png).

**Observed purpose, layout, components and data:** Expanded personal accordion lists Add Photos, Add Guides and Labels, Add Notes, Add Favorite Dishes, Add Personal Notes. Guide/label form has search, Your guides/Add new and Good for checkbox rows with counts; notice says unvisited guide additions save to Want. Favorite-dish form has text entry and suggested names. Personal-notes textarea explicitly says not visible to others.

**Navigation, controls and scrolling:** Place accordion → respective form with Cancel/Done. No entry saved. Add Photos, public Add Notes and Add new guide were not opened in this snapshot.

**Available states:** Empty private note; existing highlight suggestions; empty guide ownership and label choices.

**Unknowns / inference boundary:** Public-note/post composer, photo permissions/upload, guide creation, label save effects and privacy enforcement unknown. Visibility copy is observed, enforcement not tested.

### B18 — Place reviews and comments

**Evidence:** [155-place-don-angie-reviews-d.png](../reference/beli/155-place-don-angie-reviews-d.png), [156-place-don-angie-reviews-e.png](../reference/beli/156-place-don-angie-reviews-e.png), [157-place-review-notes-expanded-a.png](../reference/beli/157-place-review-notes-expanded-a.png), [158-place-review-notes-expanded-b.png](../reference/beli/158-place-review-notes-expanded-b.png), [159-place-review-notes-expanded-c.png](../reference/beli/159-place-review-notes-expanded-c.png), [160-place-don-angie-reviews-f.png](../reference/beli/160-place-don-angie-reviews-f.png), [161-place-review-comments-loading.png](../reference/beli/161-place-review-comments-loading.png), [162-place-review-comments-detail.png](../reference/beli/162-place-review-comments-detail.png), [179-feed-ranking-detail-comments-empty.png](../reference/beli/179-feed-ranking-detail-comments-empty.png), [183-place-arome-reviews-d.png](../reference/beli/183-place-arome-reviews-d.png), [184-place-arome-reviews-e.png](../reference/beli/184-place-arome-reviews-e.png).

**Observed purpose, layout, components and data:** Friend review cards show avatar/name/handle, score, date, labels, optional horizontal photos with overflow count/favorite badge, Notes with See more, Favorite Dishes and heart/comment counts. Expanded prose grows inline. Standalone detail adds place/visit/companion metadata, larger photos, share/add/bookmark and pinned Comment or tag a friend field/Post. Existing comment has author, text, Reply, heart.

**Navigation, controls and scrolling:** See more expands within place scroll; View comment or feed comment icon opens detail. Detail back returns; root tabs replaced by composer. Place compact header stays over long expanded review.

**Available states:** Photo-only, text-only and combined reviews; collapsed/expanded notes, skeleton detail, one comment and blank comment area.

**Unknowns / inference boundary:** Comment submission/reply/tagging/like success, edit/delete/report, pagination and keyboard behavior not tested. No-comments capture shows blank space rather than an explicit empty message.

### B19 — Photos and viewer

**Evidence:** [163-place-photos-loading.png](../reference/beli/163-place-photos-loading.png), [164-place-photos-a.png](../reference/beli/164-place-photos-a.png), [165-place-photos-menu.png](../reference/beli/165-place-photos-menu.png), [166-place-photo-viewer.png](../reference/beli/166-place-photo-viewer.png), [167-place-photo-overflow.png](../reference/beli/167-place-photo-overflow.png), [168-place-photos-search-results.png](../reference/beli/168-place-photos-search-results.png), [169-place-photos-search-empty.png](../reference/beli/169-place-photos-search-empty.png).

**Observed purpose, layout, components and data:** Back/place header, dish-search field, persistent popular-dish horizontal carousel, two-column member-photo grid with captions. Menu tile becomes query. Viewer has large image, author/date/Follow, caption and overflow Report photo sheet.

**Navigation, controls and scrolling:** See all photos → grid → tile/filter → photo → back. Search changes grid while popular carousel remains. Dedicated photo page has no root tabs.

**Available states:** Skeleton grid, loaded grid, Menu filter, matching caption query, explicit No results, full image and report menu.

**Unknowns / inference boundary:** Zoom/swipe, upload/edit/favorite/report flow and pagination unverified. Image presence does not prove upload behavior.

### B20 — Rating entry

**Evidence:** [172-rate-initial-question.png](../reference/beli/172-rate-initial-question.png).

**Observed purpose, layout, components and data:** Three stacked rounded white overlay panels on dimmed place: place/price/cuisine with X; Add to my list of category dropdown; How was it with green/yellow/red circles and liked/fine/disliked labels.

**Navigation, controls and scrolling:** Place plus → entry; X dismisses. No bucket or category option selected.

**Available states:** Only initial unselected rating entry.

**Unknowns / inference boundary:** Onboarding, bucket transitions, comparisons, ties/Too tough, backtracking, score reveal, save/post linkage, rerank and delete all pending. PLAN research is not direct observation of these behaviors.

### B21 — Home feed and entry points

**Evidence:** [173-feed-home-a.png](../reference/beli/173-feed-home-a.png), [174-feed-home-b.png](../reference/beli/174-feed-home-b.png), [175-feed-milestone-and-ranking.png](../reference/beli/175-feed-milestone-and-ranking.png), [178-feed-ranking-with-notes.png](../reference/beli/178-feed-ranking-with-notes.png), [180-feed-home-e.png](../reference/beli/180-feed-home-e.png).

**Observed purpose, layout, components and data:** Pinned brand/calendar/bell badge/menu, global search and nearby/trending/friend-recs chips; invite-unlock card and featured-list carousel scroll in body. Ask your friends composer precedes feed. Milestone card contains avatar/headline/social actions; ranking card has author/place/category/location/companion/visit/score, optional photo/note, bookmark/reaction counts, share/add/bookmark and relative date.

**Navigation, controls and scrolling:** Feed tab; Trending opens B24; avatar/milestone headline opens profile; ranking body opens place; comment opens B18. Header/search/chips and tab bar remain across scroll.

**Available states:** Milestone and ranking cards; media placeholders then loaded images. No empty/error feed captured.

**Unknowns / inference boundary:** Beli feed ordering, calendar screen, request composer and publishing unverified. Chronological order is a confirmed Roam plan, not a conclusion about Beli.

### B22 — Global place and member search

**Evidence:** [188-search-restaurants-initial.png](../reference/beli/188-search-restaurants-initial.png), [189-search-typing.png](../reference/beli/189-search-typing.png), [190-search-restaurants-results.png](../reference/beli/190-search-restaurants-results.png), [191-search-dishes-locked.png](../reference/beli/191-search-dishes-locked.png), [219-search-results-loading.png](../reference/beli/219-search-results-loading.png), [220-search-restaurants-empty.png](../reference/beli/220-search-restaurants-empty.png), [221-search-restaurants-no-results.png](../reference/beli/221-search-restaurants-no-results.png), [222-search-missing-place-dialog.png](../reference/beli/222-search-missing-place-dialog.png), [223-search-city-initial.png](../reference/beli/223-search-city-initial.png), [224-search-city-suggestions.png](../reference/beli/224-search-city-suggestions.png), [225-search-members-empty.png](../reference/beli/225-search-members-empty.png), [226-search-members-contacts-gate.png](../reference/beli/226-search-members-contacts-gate.png), [227-search-members-initial.png](../reference/beli/227-search-members-initial.png), [228-search-members-loading.png](../reference/beli/228-search-members-loading.png), [229-search-members-results.png](../reference/beli/229-search-members-results.png).

**Observed purpose, layout, components and data:** Brand/X header and Restaurants/Members tabs. Places have query plus Current Location/city field, rec/trending/friend chips and suggestions. Results mix locked dish/rec entries, featured guide and places with add/bookmark. City autocomplete includes Current Location and worldwide locality rows. Members have name/handle search, contacts/invite rows, suggested/top-member carousels and avatar/name/handle/Follow results.

**Navigation, controls and scrolling:** Central Search or feed search → query/city/tab. Query can show old suggestions while typing before loading/results. Unmatched place → Load more → terminal no-results → missing-place advice dialog. Members contacts pre-prompt Allow/Not now.

**Available states:** Initial, typing, skeletons, results, transitional Load more, final empty, missing-place info; member initial/loading/results/empty/contact gate; locked dish search.

**Unknowns / inference boundary:** Search provider/ranking/debounce, invite outcome, contacts import and deeper result pagination unknown. Missing-place dialog gives advice, not a create-custom-place form.

### B23 — Featured challenge list, map and sharing

**Evidence:** [192-search-curated-list-loading.png](../reference/beli/192-search-curated-list-loading.png), [193-search-curated-list-a.png](../reference/beli/193-search-curated-list-a.png), [194-search-curated-map-loading.png](../reference/beli/194-search-curated-map-loading.png), [195-search-curated-map.png](../reference/beli/195-search-curated-map.png), [196-search-curated-map-marker.png](../reference/beli/196-search-curated-map-marker.png), [197-search-curated-list-b.png](../reference/beli/197-search-curated-list-b.png), [207-search-curated-list-l.png](../reference/beli/207-search-curated-list-l.png), [217-search-curated-list-v.png](../reference/beli/217-search-curated-list-v.png), [218-search-curated-share-sheet.png](../reference/beli/218-search-curated-share-sheet.png), [278-notifications-featured-list-detail.png](../reference/beli/278-notifications-featured-list-detail.png).

**Observed purpose, layout, components and data:** Image hero, title/description/participant count/visited progress, Bookmark all and Share. Descending numbered place entries have credited large images, metadata, add/bookmark and optional reservation slots/provider. Fixed compact title/back/share and List/Map; floating Join challenge and bottom availability strip. Map has ranked dots; selected marker enlarges and shows place card.

**Navigation, controls and scrolling:** Search featured result or notification → challenge; List/Map switch → marker selection; Share → native sheet. Top/middle/final rank captured. No bookmark/join/share target chosen.

**Available states:** List skeleton/hero loading, loaded list, map tile-grid loading, loaded map, selected marker, share sheet, reservation/no-reservation variants.

**Unknowns / inference boundary:** Challenge joining/progress update, bulk save, selection navigation, map gestures and return-position persistence unknown. Fixed-city map is observed without location grant.

### B24 — Trending and populated filters

**Evidence:** [231-lists-trending-a.png](../reference/beli/231-lists-trending-a.png), [232-lists-trending-sort.png](../reference/beli/232-lists-trending-sort.png), [233-lists-trending-filters.png](../reference/beli/233-lists-trending-filters.png), [234-lists-trending-filter-city.png](../reference/beli/234-lists-trending-filter-city.png), [235-lists-trending-filters-lower.png](../reference/beli/235-lists-trending-filters-lower.png), [236-lists-trending-filter-good-for.png](../reference/beli/236-lists-trending-filter-good-for.png), [237-lists-trending-filter-cuisine.png](../reference/beli/237-lists-trending-filter-cuisine.png), [238-lists-trending-filter-price.png](../reference/beli/238-lists-trending-filter-price.png), [239-lists-trending-filter-borough.png](../reference/beli/239-lists-trending-filter-borough.png), [240-lists-trending-filter-neighborhood.png](../reference/beli/240-lists-trending-filter-neighborhood.png), [241-lists-trending-filter-country.png](../reference/beli/241-lists-trending-filter-country.png), [242-lists-trending-overflow.png](../reference/beli/242-lists-trending-overflow.png).

**Observed purpose, layout, components and data:** Trending uses list shell with Most Trending/Distance sort, search and floating map toggle. Filters reuse categories; quick chips Reserve/Open now/Not on your list/Order. City/Good For/Cuisine/Price/Borough/Neighborhood/Country accordions have searchable checkbox lists, View more where applicable; price shows four currency levels. No Score/Number of friends accordions in this variant.

**Navigation, controls and scrolling:** Feed Trending → rows → sort/filter/overflow. Notes report opening accordions collapses prior one and scrolls selection into view. Clear all/Apply stay pinned; no changes applied.

**Available states:** Populated list; every accordion; alternate sort selection in draft form.

**Unknowns / inference boundary:** Trending formula, applied combinations, page limits, search results and list-map data after permission grant unknown.

### B25 — Other member profile and moderation

**Evidence:** [176-friend-planning-introduction.png](../reference/beli/176-friend-planning-introduction.png), [177-friend-profile-overview.png](../reference/beli/177-friend-profile-overview.png), [243-friend-profile-overflow.png](../reference/beli/243-friend-profile-overflow.png), [274-friend-suggested-people.png](../reference/beli/274-friend-suggested-people.png), [275-friend-activity-a.png](../reference/beli/275-friend-activity-a.png), [276-friend-custom-guides-grid.png](../reference/beli/276-friend-custom-guides-grid.png).

**Observed purpose, layout, components and data:** Back/name/bell/share/overflow; avatar/handle/crown/join date, city percentile badge, social links, follower/following/rank stats, Following/Subscribe/dropdown, Been/Want/shared-wants, rank/streak cards. Activity/Taste/Custom Guides tabs; custom guides use two-column image cards with Paid/share/title/count. Intro promotes shared wants. Overflow offers Mute/Block/Report/Unfollow.

**Navigation, controls and scrolling:** Feed author → intro → profile; list/stats/tab links open related screens. Dropdown reveals People you may know. Header/bottom tabs fixed; body scrolls.

**Available states:** Already-followed creator, suggestion carousel, activity, paid-guide grid, moderation menu.

**Unknowns / inference boundary:** Unfollow/block/report/bell/social-link outcomes, noncreator differences and edit rights not exercised.

### B26 — Other member Been and Want lists

**Evidence:** [244-friend-been-list-a.png](../reference/beli/244-friend-been-list-a.png), [245-friend-been-sort.png](../reference/beli/245-friend-been-sort.png), [246-friend-been-overflow.png](../reference/beli/246-friend-been-overflow.png), [247-friend-want-loading.png](../reference/beli/247-friend-want-loading.png), [248-friend-want-list-a.png](../reference/beli/248-friend-want-list-a.png).

**Observed purpose, layout, components and data:** Owner handle/back/share/overflow, category/tabs/filter rail/sort/search. Been rows include rank and personal score; All visibly mixes Beli place categories, sometimes several displayed 10.0 values. Want rows have no rank/personal score, price/category/city/hours, add/bookmark and missing-cuisine suggestion. View Map floats.

**Navigation, controls and scrolling:** Profile counts → Been/Want; sort sheet Score/Distance/Date added; overflow filter/search/full-link. Bottom tabs retained.

**Available states:** Been populated, Want skeleton then populated.

**Unknowns / inference boundary:** Beli cross-category ranking and same-rounded-score order cannot be inferred. Own populated controls may differ; do not silently substitute this as verified own state.

### B27 — Guide directory and public guides

**Evidence:** [249-friend-guides-a.png](../reference/beli/249-friend-guides-a.png), [253-friend-request-guide-a.png](../reference/beli/253-friend-request-guide-a.png), [254-friend-request-guide-sort.png](../reference/beli/254-friend-request-guide-sort.png), [255-friend-request-guide-b.png](../reference/beli/255-friend-request-guide-b.png), [256-friend-request-guide-bottom.png](../reference/beli/256-friend-request-guide-bottom.png), [257-friend-guides-b.png](../reference/beli/257-friend-guides-b.png), [258-friend-guides-c.png](../reference/beli/258-friend-guides-c.png), [259-friend-guides-bottom.png](../reference/beli/259-friend-guides-bottom.png), [260-friend-generated-guide.png](../reference/beli/260-friend-generated-guide.png), [276-friend-custom-guides-grid.png](../reference/beli/276-friend-custom-guides-grid.png).

**Observed purpose, layout, components and data:** Directory has city-count chips and horizontal Custom Guides, Ask For Recs, Top 10s, Recently updated, Most spots sections with See all. Cards use photos or gradients and spot counts. Request guide has hero/progress/title/description/author/city, attributed numbered recommendations and Most recommended/Distance/Date Added sort. Generated guide has category/city hero and scored place/photo/note. Share guide floats; List/Map and compact header.

**Navigation, controls and scrolling:** Other-member Guides → card → guide; back to directory. Profile Custom Guides is separate grid. Request guide top/middle/bottom captured; title/map/share controls persist while scrolling.

**Available states:** Paid cards in directory; accessible request and generated guides including single-item and six-item endings.

**Unknowns / inference boundary:** Authoring, collaboration, requester/recommender permissions, contribution forms, generated-guide algorithm and directory See all destinations unknown.

### B28 — Paid guide and subscription offer

**Evidence:** [250-friend-paid-guide-loading.png](../reference/beli/250-friend-paid-guide-loading.png), [251-friend-paid-guide-locked.png](../reference/beli/251-friend-paid-guide-locked.png), [252-friend-subscription-offer.png](../reference/beli/252-friend-subscription-offer.png).

**Observed purpose, layout, components and data:** Paid detail skeleton → image hero/progress/title/description/author/city/Paid badge, blurred content and Subscribers only/Subscribe. Offer shows creator intro, exclusive-content carousel, annual/monthly choices, terms checkbox, disabled CTA and in-app alternative.

**Navigation, controls and scrolling:** Paid card → detail → Subscribe → offer; back without purchase. Share guide visible on detail.

**Available states:** Loading, locked guide and unaccepted subscription terms.

**Unknowns / inference boundary:** Checkout, renewal, restoration, access enforcement and successful paid contents not captured. Displayed prices are sample capture data, not Roam pricing.

### B29 — Shared wants planning

**Evidence:** [261-friend-overlapping-bookmarks-empty.png](../reference/beli/261-friend-overlapping-bookmarks-empty.png), [262-friend-overlap-select-friends.png](../reference/beli/262-friend-overlap-select-friends.png), [263-friend-overlap-map-empty-dialog.png](../reference/beli/263-friend-overlap-map-empty-dialog.png).

**Observed purpose, layout, components and data:** Two avatars/back/add-person/share, map-backed header, List/Map, Overlapping Bookmarks explanation and empty-state links to each member’s Want list. Select friends form has Cancel/Done, query, selected chip, invite entry and checkbox rows. Empty map opens illustrated No mutual bookmarks modal.

**Navigation, controls and scrolling:** Other profile shared-wants → list; add-person → picker; Map → empty dialog; back/dismiss. No people changed.

**Available states:** Empty intersection, preselected person, map-empty modal.

**Unknowns / inference boundary:** Populated overlap, multiple-member intersection semantics, share link and selection persistence unverified.

### B30 — Notifications

**Evidence:** [277-notifications-a.png](../reference/beli/277-notifications-a.png), [278-notifications-featured-list-detail.png](../reference/beli/278-notifications-featured-list-detail.png), [279-notifications-suggested-members.png](../reference/beli/279-notifications-suggested-members.png).

**Observed purpose, layout, components and data:** Back/title; Requests push banner Allow/X; Earlier events with icon/avatar, relative dates, featured-list headlines, follow-back buttons and import entry; Suggested members with Follow/X below. 277 visibly says Earlier, not New.

**Navigation, controls and scrolling:** Feed bell → notifications → featured-list event opens challenge. Notes report viewing marks New as Earlier; that transition is reported, not independently established by screenshot 277.

**Available states:** Populated events and suggestions; no permission grant or follow performed.

**Unknowns / inference boundary:** Unread lifecycle, empty/error state, push payloads and action persistence unknown.

### B31 — Drawer and settings overview

**Evidence:** [280-misc-main-menu.png](../reference/beli/280-misc-main-menu.png), [281-settings-overview.png](../reference/beli/281-settings-overview.png).

**Observed purpose, layout, components and data:** Right-side drawer overlays feed, Menu/X, invites, unlock features, school, Settings, Reservations, Subscriptions, Dining Goal, FAQ, Home City, Dietary Restrictions, Disliked Cuisines, Import, Password, Privacy Policy, Log Out. Settings page groups Account, Notifications, Privacy, Your app, Help, Logout with icons/subtitles/chevrons.

**Navigation, controls and scrolling:** Feed/profile menu → drawer → Settings → sections; back returns. Drawer fits captured viewport.

**Available states:** Open drawer, settings root.

**Unknowns / inference boundary:** Many utility destinations and Help contact surface pending; presence of a menu item does not verify its destination.

### B32 — Account and identity forms

**Evidence:** [282-settings-account.png](../reference/beli/282-settings-account.png), [283-settings-email-form.png](../reference/beli/283-settings-email-form.png), [284-settings-phone-form.png](../reference/beli/284-settings-phone-form.png), [285-settings-password-form.png](../reference/beli/285-settings-password-form.png).

**Observed purpose, layout, components and data:** Account rows: email/phone/password/payment/school/company/privacy; deactivate/delete links. Email form with existing value/Cancel/Save. Phone form with country code, blank number, region limitation note and disabled Next. Password form has current/new/confirm, eye icon, requirements, Forgot password and disabled Save. Private contact values are not transcribed here.

**Navigation, controls and scrolling:** Settings Account → form → Cancel; no credentials entered and no reset/deactivation/deletion initiated.

**Available states:** Prefilled email and blank phone/password forms.

**Unknowns / inference boundary:** Validation, verification, recovery, account deletion/retention and session/logout transitions unknown; sign-up flow not captured.

### B33 — Payments and affiliations

**Evidence:** [286-settings-payment-loading.png](../reference/beli/286-settings-payment-loading.png), [287-settings-payment-empty.png](../reference/beli/287-settings-payment-empty.png), [288-settings-payment-add-card.png](../reference/beli/288-settings-payment-add-card.png), [289-settings-school-introduction.png](../reference/beli/289-settings-school-introduction.png), [290-settings-company-introduction.png](../reference/beli/290-settings-company-introduction.png).

**Observed purpose, layout, components and data:** Payment skeleton → card-empty illustration/copy about reservation fees and Add credit card. Add-card sheet has scan, number/expiry/CVC, country/ZIP, terms and disabled Set up/X. School/company intros use illustration, Join/Not now and leaderboard copy.

**Navigation, controls and scrolling:** Account → payment → Add card → dismiss; school/company → intro → Not now.

**Available states:** Loading, empty payment, blank card form, affiliation gates.

**Unknowns / inference boundary:** Payment tokenization, checkout, affiliation selection/verification and leaderboards not verified here.

### B34 — Privacy, blocks, mutes and cookies

**Evidence:** [291-settings-privacy.png](../reference/beli/291-settings-privacy.png), [292-settings-blocked-empty.png](../reference/beli/292-settings-blocked-empty.png), [293-settings-muted-empty.png](../reference/beli/293-settings-muted-empty.png), [294-settings-cookies.png](../reference/beli/294-settings-cookies.png).

**Observed purpose, layout, components and data:** Privacy has enabled Public Account toggle and blocked/muted/cookies rows. Empty moderation lists show illustration/explanation; blocked copy says cannot see your content, muted copy says activity hidden from feed. Cookies screen has essential-cookie notice/link, two enabled third-party/other-site toggles and Save preferences.

**Navigation, controls and scrolling:** Settings or Account Privacy → child page → back. Toggle/save untouched.

**Available states:** Public-on, empty blocked/muted, cookie preferences.

**Unknowns / inference boundary:** Private-account behavior, populated controls and enforcement unverified. Roam public profiles are already confirmed, so a private toggle is not inherited.

### B35 — Notification preferences

**Evidence:** [295-settings-notifications-a.png](../reference/beli/295-settings-notifications-a.png), [296-settings-notifications-b.png](../reference/beli/296-settings-notifications-b.png), [297-settings-notifications-bottom.png](../reference/beli/297-settings-notifications-bottom.png).

**Observed purpose, layout, components and data:** Long label/toggle list under pinned title/back. Types: follows, bookmarks from list, likes, comments, contacts joining, featured lists, restaurant news, shared reservations, weekly ranking/streak reminders; order/rank reminders after reservations and Google-synced reservations; in-app/widget prompts for both sources; followed-member recommendation requests; shared-guide joins, being added, added places. Visible toggles enabled.

**Navigation, controls and scrolling:** Settings Notifications → vertical scroll to bottom; no toggle changed.

**Available states:** Top/middle/bottom preferences.

**Unknowns / inference boundary:** Defaults for a new account, save timing, OS permission dependency, delivery cadence and opt-out persistence unknown.

### B36 — App preferences and FAQ

**Evidence:** [298-settings-app.png](../reference/beli/298-settings-app.png), [299-settings-distance-units.png](../reference/beli/299-settings-distance-units.png), [300-settings-faq-a.png](../reference/beli/300-settings-faq-a.png), [301-settings-faq-expanded.png](../reference/beli/301-settings-faq-expanded.png).

**Observed purpose, layout, components and data:** App settings has Disable vibrations off and Distance units Miles. Units child shows Miles checkmark and Kilometers. FAQ sheet has X, large serif title, search and accordion questions for import/date/category/sharing/comparison/ties/manual scores/locks/streak. Expanded import answer explains Want-only importing; body pushes following questions down.

**Navigation, controls and scrolling:** Settings Your app → units → back; Help → FAQ → expand first answer. Notes report fixed FAQ header/search/X. Exhaustive answers intentionally excluded.

**Available states:** Current units, collapsed FAQ and one expanded answer.

**Unknowns / inference boundary:** Preference mutation, FAQ search results and all other answers unknown. A question about ties is not evidence of a particular tie algorithm.

## Cross-flow routes

| Entry | Observed route | Boundary |
|---|---|---|
| Own Profile | overview → Been (Your Lists); counts → followers/following; lower tabs → Activity/Taste/Guides | Own populated states absent |
| Your Lists | More → Friend Recs/Trending; overflow → filter/search/share; Want → import | Applied filters and imports not performed |
| Place | list/search/feed → detail → score explanations, utility sheets, hours/notes/reviews/photos; plus → initial rating | Rating stops before bucket choice |
| Feed | author → member; comment → ranking detail; place body → place; featured list → challenge | Composer/posting unverified |
| Search | places/members; query + city → results; featured result → list/map → marker card | No custom-place creation observed |
| Member | Been/Want/Guides; shared wants → picker/empty map; Taste → segments/sort | Mutations/collaboration not exercised |
| Notifications/settings | bell → events → guide; drawer → settings → child forms | No account/settings changes submitted |

## Visual review ledger

**V** = visually inspected (grouped sheet and/or full-size). **R** = repeated content not individually opened, represented by the listed reviewed captures. This ledger enumerates every screenshot in the initial snapshot; it does not claim every repeated restaurant/photo/person was read.

| Screenshot | Review | Inventory |
|---|---|---|
| [01-profile-overview-a.png](../reference/beli/01-profile-overview-a.png) | V | B01, B02 |
| [02-profile-been-a.png](../reference/beli/02-profile-been-a.png) | V | B07 |
| [03-profile-been-share-options.png](../reference/beli/03-profile-been-share-options.png) | V | B08 |
| [04-profile-overview-loaded.png](../reference/beli/04-profile-overview-loaded.png) | V | B01, B02 |
| [05-profile-followers-a.png](../reference/beli/05-profile-followers-a.png) | V | B03 |
| [06-profile-following-a.png](../reference/beli/06-profile-following-a.png) | V | B03 |
| [07-profile-following-no-results.png](../reference/beli/07-profile-following-no-results.png) | V | B03 |
| [08-profile-suggested-people-a.png](../reference/beli/08-profile-suggested-people-a.png) | V | B02 |
| [09-profile-suggested-people-b.png](../reference/beli/09-profile-suggested-people-b.png) | V | B02 |
| [10-profile-suggested-people-c.png](../reference/beli/10-profile-suggested-people-c.png) | V | B02 |
| [11-profile-activity-a.png](../reference/beli/11-profile-activity-a.png) | V | B04 |
| [12-profile-activity-empty-b.png](../reference/beli/12-profile-activity-empty-b.png) | V | B04 |
| [13-profile-activity-empty-c.png](../reference/beli/13-profile-activity-empty-c.png) | V | B04 |
| [14-profile-taste-locked-a.png](../reference/beli/14-profile-taste-locked-a.png) | V | B05 |
| [15-profile-taste-locked-b.png](../reference/beli/15-profile-taste-locked-b.png) | V | B05 |
| [16-profile-taste-locked-c.png](../reference/beli/16-profile-taste-locked-c.png) | V | B05 |
| [17-profile-taste-locked-d.png](../reference/beli/17-profile-taste-locked-d.png) | V | B05 |
| [18-profile-taste-locked-e.png](../reference/beli/18-profile-taste-locked-e.png) | V | B05 |
| [19-profile-taste-locked-f.png](../reference/beli/19-profile-taste-locked-f.png) | V | B05 |
| [20-profile-taste-locked-g.png](../reference/beli/20-profile-taste-locked-g.png) | V | B05 |
| [21-profile-taste-locked-h.png](../reference/beli/21-profile-taste-locked-h.png) | V | B05 |
| [22-profile-taste-locked-i.png](../reference/beli/22-profile-taste-locked-i.png) | V | B05 |
| [23-profile-taste-cuisines-empty.png](../reference/beli/23-profile-taste-cuisines-empty.png) | V | B05 |
| [24-profile-taste-sort-menu.png](../reference/beli/24-profile-taste-sort-menu.png) | V | B05 |
| [25-profile-taste-cities-empty.png](../reference/beli/25-profile-taste-cities-empty.png) | V | B05 |
| [26-profile-taste-countries-empty.png](../reference/beli/26-profile-taste-countries-empty.png) | V | B05 |
| [27-profile-guides-empty.png](../reference/beli/27-profile-guides-empty.png) | V | B06 |
| [28-profile-goal-form.png](../reference/beli/28-profile-goal-form.png) | V | B06 |
| [29-profile-goal-cancel-confirm.png](../reference/beli/29-profile-goal-cancel-confirm.png) | V | B06 |
| [30-profile-rank-locked-dialog.png](../reference/beli/30-profile-rank-locked-dialog.png) | V | B06 |
| [31-profile-streak-card.png](../reference/beli/31-profile-streak-card.png) | V | B06 |
| [32-profile-recs-locked-dialog.png](../reference/beli/32-profile-recs-locked-dialog.png) | V | B06 |
| [33-profile-been-options.png](../reference/beli/33-profile-been-options.png) | V | B08 |
| [34-profile-been-filters-a.png](../reference/beli/34-profile-been-filters-a.png) | V | B09 |
| [35-profile-been-filters-good-for.png](../reference/beli/35-profile-been-filters-good-for.png) | V | B09 |
| [36-profile-been-filters-city.png](../reference/beli/36-profile-been-filters-city.png) | V | B09 |
| [37-profile-been-filters-score.png](../reference/beli/37-profile-been-filters-score.png) | V | B09 |
| [38-profile-been-filters-friends.png](../reference/beli/38-profile-been-filters-friends.png) | V | B09 |
| [39-profile-been-filters-cuisine.png](../reference/beli/39-profile-been-filters-cuisine.png) | V | B09 |
| [40-profile-been-filters-price.png](../reference/beli/40-profile-been-filters-price.png) | V | B09 |
| [41-profile-been-filters-borough.png](../reference/beli/41-profile-been-filters-borough.png) | V | B09 |
| [42-profile-been-filters-neighborhood.png](../reference/beli/42-profile-been-filters-neighborhood.png) | V | B09 |
| [43-profile-been-filters-country.png](../reference/beli/43-profile-been-filters-country.png) | V | B09 |
| [44-profile-been-category-restaurants.png](../reference/beli/44-profile-been-category-restaurants.png) | V | B09 |
| [45-profile-been-category-bars.png](../reference/beli/45-profile-been-category-bars.png) | V | B09 |
| [46-profile-been-category-bakeries.png](../reference/beli/46-profile-been-category-bakeries.png) | V | B09 |
| [47-profile-been-category-coffee.png](../reference/beli/47-profile-been-category-coffee.png) | V | B09 |
| [48-profile-been-category-dessert.png](../reference/beli/48-profile-been-category-dessert.png) | V | B09 |
| [49-profile-been-category-all.png](../reference/beli/49-profile-been-category-all.png) | V | B09 |
| [50-profile-been-sort-score.png](../reference/beli/50-profile-been-sort-score.png) | V | B09 |
| [51-profile-been-sort-distance.png](../reference/beli/51-profile-been-sort-distance.png) | V | B09 |
| [52-profile-been-sort-date-added.png](../reference/beli/52-profile-been-sort-date-added.png) | V | B09 |
| [53-profile-been-filter-reserve.png](../reference/beli/53-profile-been-filter-reserve.png) | V | B09 |
| [54-profile-been-filter-open-now.png](../reference/beli/54-profile-been-filter-open-now.png) | V | B09 |
| [55-profile-been-filter-order.png](../reference/beli/55-profile-been-filter-order.png) | V | B09 |
| [56-profile-been-search-empty.png](../reference/beli/56-profile-been-search-empty.png) | V | B07 |
| [57-profile-been-search-no-results.png](../reference/beli/57-profile-been-search-no-results.png) | V | B07 |
| [58-profile-been-category-sheet.png](../reference/beli/58-profile-been-category-sheet.png) | V | B09 |
| [59-profile-been-b.png](../reference/beli/59-profile-been-b.png) | V | B01, B07 |
| [60-profile-been-c.png](../reference/beli/60-profile-been-c.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [61-profile-been-d.png](../reference/beli/61-profile-been-d.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [62-profile-been-e.png](../reference/beli/62-profile-been-e.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [63-profile-been-f.png](../reference/beli/63-profile-been-f.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [64-profile-been-g.png](../reference/beli/64-profile-been-g.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [65-profile-been-h.png](../reference/beli/65-profile-been-h.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [66-profile-been-i.png](../reference/beli/66-profile-been-i.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [67-profile-been-j.png](../reference/beli/67-profile-been-j.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [68-profile-been-k.png](../reference/beli/68-profile-been-k.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [69-profile-been-l.png](../reference/beli/69-profile-been-l.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [70-profile-been-m.png](../reference/beli/70-profile-been-m.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [71-profile-been-n.png](../reference/beli/71-profile-been-n.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [72-profile-been-o.png](../reference/beli/72-profile-been-o.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [73-profile-been-p.png](../reference/beli/73-profile-been-p.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [74-profile-been-q.png](../reference/beli/74-profile-been-q.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [75-profile-been-r.png](../reference/beli/75-profile-been-r.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [76-profile-been-s.png](../reference/beli/76-profile-been-s.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [77-profile-been-t.png](../reference/beli/77-profile-been-t.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [78-profile-been-u.png](../reference/beli/78-profile-been-u.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [79-profile-been-v.png](../reference/beli/79-profile-been-v.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [80-profile-been-w.png](../reference/beli/80-profile-been-w.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [81-profile-been-x.png](../reference/beli/81-profile-been-x.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [82-profile-been-y.png](../reference/beli/82-profile-been-y.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [83-profile-been-z.png](../reference/beli/83-profile-been-z.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [84-profile-been-aa.png](../reference/beli/84-profile-been-aa.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [85-profile-been-ab.png](../reference/beli/85-profile-been-ab.png) | V | B07 |
| [86-profile-been-ac.png](../reference/beli/86-profile-been-ac.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [87-profile-been-ad.png](../reference/beli/87-profile-been-ad.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [88-profile-been-ae.png](../reference/beli/88-profile-been-ae.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [89-profile-been-af.png](../reference/beli/89-profile-been-af.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [90-profile-been-ag.png](../reference/beli/90-profile-been-ag.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [91-profile-been-ah.png](../reference/beli/91-profile-been-ah.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [92-profile-been-ai.png](../reference/beli/92-profile-been-ai.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [93-profile-been-aj.png](../reference/beli/93-profile-been-aj.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [94-profile-been-ak.png](../reference/beli/94-profile-been-ak.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [95-profile-been-al.png](../reference/beli/95-profile-been-al.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [96-profile-been-am.png](../reference/beli/96-profile-been-am.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [97-profile-been-an.png](../reference/beli/97-profile-been-an.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [98-profile-been-ao.png](../reference/beli/98-profile-been-ao.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [99-profile-been-ap.png](../reference/beli/99-profile-been-ap.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [100-profile-been-aq.png](../reference/beli/100-profile-been-aq.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [101-profile-been-ar.png](../reference/beli/101-profile-been-ar.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [102-profile-been-as.png](../reference/beli/102-profile-been-as.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [103-profile-been-at.png](../reference/beli/103-profile-been-at.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [104-profile-been-au.png](../reference/beli/104-profile-been-au.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [105-profile-been-av.png](../reference/beli/105-profile-been-av.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [106-profile-been-aw.png](../reference/beli/106-profile-been-aw.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [107-profile-been-ax.png](../reference/beli/107-profile-been-ax.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [108-profile-been-ay.png](../reference/beli/108-profile-been-ay.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [109-profile-been-az.png](../reference/beli/109-profile-been-az.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [110-profile-been-ba.png](../reference/beli/110-profile-been-ba.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [111-profile-been-bb.png](../reference/beli/111-profile-been-bb.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [112-profile-been-bc.png](../reference/beli/112-profile-been-bc.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [113-profile-been-bd.png](../reference/beli/113-profile-been-bd.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [114-profile-been-be.png](../reference/beli/114-profile-been-be.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [115-profile-been-bf.png](../reference/beli/115-profile-been-bf.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [116-profile-been-bg.png](../reference/beli/116-profile-been-bg.png) | R — B07, representatives 59 / 85 / 117 | B07 |
| [117-profile-been-bh.png](../reference/beli/117-profile-been-bh.png) | V | B07 |
| [118-place-la-pecora-reservation-tip.png](../reference/beli/118-place-la-pecora-reservation-tip.png) | V | B11 |
| [119-profile-want-to-try-empty-a.png](../reference/beli/119-profile-want-to-try-empty-a.png) | V | B10 |
| [120-lists-import-menu.png](../reference/beli/120-lists-import-menu.png) | V | B10 |
| [121-lists-import-google-maps-form.png](../reference/beli/121-lists-import-google-maps-form.png) | V | B10 |
| [122-lists-import-paste-form.png](../reference/beli/122-lists-import-paste-form.png) | V | B10 |
| [123-lists-import-foursquare.png](../reference/beli/123-lists-import-foursquare.png) | V | B10 |
| [124-lists-import-mapstr.png](../reference/beli/124-lists-import-mapstr.png) | V | B10 |
| [125-lists-availability-form.png](../reference/beli/125-lists-availability-form.png) | V | B11 |
| [126-lists-more-picker.png](../reference/beli/126-lists-more-picker.png) | V | B12 |
| [127-lists-friend-recs-intro.png](../reference/beli/127-lists-friend-recs-intro.png) | V | B12 |
| [128-lists-friend-recs-a.png](../reference/beli/128-lists-friend-recs-a.png) | V | B12 |
| [129-lists-friend-recs-sort-menu.png](../reference/beli/129-lists-friend-recs-sort-menu.png) | V | B12 |
| [130-lists-distance-location-prompt.png](../reference/beli/130-lists-distance-location-prompt.png) | V | B13 |
| [131-lists-map-location-system-prompt.png](../reference/beli/131-lists-map-location-system-prompt.png) | V | B13 |
| [132-lists-guides-locked-dialog.png](../reference/beli/132-lists-guides-locked-dialog.png) | V | B06 |
| [133-lists-map-location-gate.png](../reference/beli/133-lists-map-location-gate.png) | V | B13 |
| [134-lists-city-filter-a.png](../reference/beli/134-lists-city-filter-a.png) | V | B14 |
| [135-lists-city-filter-results.png](../reference/beli/135-lists-city-filter-results.png) | V | B14 |
| [136-lists-city-filter-no-results.png](../reference/beli/136-lists-city-filter-no-results.png) | V | B14 |
| [137-place-don-angie-detail-a.png](../reference/beli/137-place-don-angie-detail-a.png) | V | B11, B15 |
| [138-place-don-angie-options.png](../reference/beli/138-place-don-angie-options.png) | V | B16 |
| [139-place-suggest-edit-menu.png](../reference/beli/139-place-suggest-edit-menu.png) | V | B16 |
| [140-place-suggest-cuisines-form.png](../reference/beli/140-place-suggest-cuisines-form.png) | V | B16 |
| [141-place-suggest-price-form.png](../reference/beli/141-place-suggest-price-form.png) | V | B16 |
| [142-place-share-sheet.png](../reference/beli/142-place-share-sheet.png) | V |  |
| [143-place-rec-score-explanation.png](../reference/beli/143-place-rec-score-explanation.png) | V | B15 |
| [144-place-friend-score-explanation.png](../reference/beli/144-place-friend-score-explanation.png) | V | B15 |
| [145-place-average-score-locked.png](../reference/beli/145-place-average-score-locked.png) | V | B15 |
| [146-place-don-angie-detail-b.png](../reference/beli/146-place-don-angie-detail-b.png) | V | B15 |
| [147-place-don-angie-detail-c.png](../reference/beli/147-place-don-angie-detail-c.png) | V | B15 |
| [148-place-opening-hours.png](../reference/beli/148-place-opening-hours.png) | V | B16 |
| [149-place-hours-suggestion-menu.png](../reference/beli/149-place-hours-suggestion-menu.png) | V | B16 |
| [150-place-hours-edit-form.png](../reference/beli/150-place-hours-edit-form.png) | V | B16 |
| [151-place-your-notes-actions.png](../reference/beli/151-place-your-notes-actions.png) | V | B17 |
| [152-place-guides-labels-form.png](../reference/beli/152-place-guides-labels-form.png) | V | B17 |
| [153-place-favorite-dishes-form.png](../reference/beli/153-place-favorite-dishes-form.png) | V | B17 |
| [154-place-personal-notes-form.png](../reference/beli/154-place-personal-notes-form.png) | V | B17 |
| [155-place-don-angie-reviews-d.png](../reference/beli/155-place-don-angie-reviews-d.png) | V | B18 |
| [156-place-don-angie-reviews-e.png](../reference/beli/156-place-don-angie-reviews-e.png) | V | B18 |
| [157-place-review-notes-expanded-a.png](../reference/beli/157-place-review-notes-expanded-a.png) | V | B18 |
| [158-place-review-notes-expanded-b.png](../reference/beli/158-place-review-notes-expanded-b.png) | V | B18 |
| [159-place-review-notes-expanded-c.png](../reference/beli/159-place-review-notes-expanded-c.png) | V | B18 |
| [160-place-don-angie-reviews-f.png](../reference/beli/160-place-don-angie-reviews-f.png) | V | B18 |
| [161-place-review-comments-loading.png](../reference/beli/161-place-review-comments-loading.png) | V | B18 |
| [162-place-review-comments-detail.png](../reference/beli/162-place-review-comments-detail.png) | V | B18 |
| [163-place-photos-loading.png](../reference/beli/163-place-photos-loading.png) | V | B19 |
| [164-place-photos-a.png](../reference/beli/164-place-photos-a.png) | V | B19 |
| [165-place-photos-menu.png](../reference/beli/165-place-photos-menu.png) | V | B19 |
| [166-place-photo-viewer.png](../reference/beli/166-place-photo-viewer.png) | V | B19 |
| [167-place-photo-overflow.png](../reference/beli/167-place-photo-overflow.png) | V | B19 |
| [168-place-photos-search-results.png](../reference/beli/168-place-photos-search-results.png) | V | B19 |
| [169-place-photos-search-empty.png](../reference/beli/169-place-photos-search-empty.png) | V | B19 |
| [170-place-call-confirm.png](../reference/beli/170-place-call-confirm.png) | V | B16 |
| [171-place-directions-menu.png](../reference/beli/171-place-directions-menu.png) | V | B16 |
| [172-rate-initial-question.png](../reference/beli/172-rate-initial-question.png) | V | B20 |
| [173-feed-home-a.png](../reference/beli/173-feed-home-a.png) | V | B01, B21 |
| [174-feed-home-b.png](../reference/beli/174-feed-home-b.png) | V | B21 |
| [175-feed-milestone-and-ranking.png](../reference/beli/175-feed-milestone-and-ranking.png) | V | B21 |
| [176-friend-planning-introduction.png](../reference/beli/176-friend-planning-introduction.png) | V | B25 |
| [177-friend-profile-overview.png](../reference/beli/177-friend-profile-overview.png) | V | B25 |
| [178-feed-ranking-with-notes.png](../reference/beli/178-feed-ranking-with-notes.png) | V | B21 |
| [179-feed-ranking-detail-comments-empty.png](../reference/beli/179-feed-ranking-detail-comments-empty.png) | V | B18 |
| [180-feed-home-e.png](../reference/beli/180-feed-home-e.png) | V | B21 |
| [181-place-arome-detail-b.png](../reference/beli/181-place-arome-detail-b.png) | V | B15 |
| [182-place-arome-detail-c.png](../reference/beli/182-place-arome-detail-c.png) | V | B15 |
| [183-place-arome-reviews-d.png](../reference/beli/183-place-arome-reviews-d.png) | V | B18 |
| [184-place-arome-reviews-e.png](../reference/beli/184-place-arome-reviews-e.png) | V | B18 |
| [185-place-arome-suggestions-f.png](../reference/beli/185-place-arome-suggestions-f.png) | V |  |
| [186-place-arome-bottom-g.png](../reference/beli/186-place-arome-bottom-g.png) | V |  |
| [187-place-arome-detail-a.png](../reference/beli/187-place-arome-detail-a.png) | V | B15 |
| [188-search-restaurants-initial.png](../reference/beli/188-search-restaurants-initial.png) | V | B01, B22 |
| [189-search-typing.png](../reference/beli/189-search-typing.png) | V | B22 |
| [190-search-restaurants-results.png](../reference/beli/190-search-restaurants-results.png) | V | B22 |
| [191-search-dishes-locked.png](../reference/beli/191-search-dishes-locked.png) | V | B22 |
| [192-search-curated-list-loading.png](../reference/beli/192-search-curated-list-loading.png) | V | B23 |
| [193-search-curated-list-a.png](../reference/beli/193-search-curated-list-a.png) | V | B23 |
| [194-search-curated-map-loading.png](../reference/beli/194-search-curated-map-loading.png) | V | B23 |
| [195-search-curated-map.png](../reference/beli/195-search-curated-map.png) | V | B23 |
| [196-search-curated-map-marker.png](../reference/beli/196-search-curated-map-marker.png) | V | B23 |
| [197-search-curated-list-b.png](../reference/beli/197-search-curated-list-b.png) | V | B23 |
| [198-search-curated-list-c.png](../reference/beli/198-search-curated-list-c.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [199-search-curated-list-d.png](../reference/beli/199-search-curated-list-d.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [200-search-curated-list-e.png](../reference/beli/200-search-curated-list-e.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [201-search-curated-list-f.png](../reference/beli/201-search-curated-list-f.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [202-search-curated-list-g.png](../reference/beli/202-search-curated-list-g.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [203-search-curated-list-h.png](../reference/beli/203-search-curated-list-h.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [204-search-curated-list-i.png](../reference/beli/204-search-curated-list-i.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [205-search-curated-list-j.png](../reference/beli/205-search-curated-list-j.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [206-search-curated-list-k.png](../reference/beli/206-search-curated-list-k.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [207-search-curated-list-l.png](../reference/beli/207-search-curated-list-l.png) | V | B11, B23 |
| [208-search-curated-list-m.png](../reference/beli/208-search-curated-list-m.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [209-search-curated-list-n.png](../reference/beli/209-search-curated-list-n.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [210-search-curated-list-o.png](../reference/beli/210-search-curated-list-o.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [211-search-curated-list-p.png](../reference/beli/211-search-curated-list-p.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [212-search-curated-list-q.png](../reference/beli/212-search-curated-list-q.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [213-search-curated-list-r.png](../reference/beli/213-search-curated-list-r.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [214-search-curated-list-s.png](../reference/beli/214-search-curated-list-s.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [215-search-curated-list-t.png](../reference/beli/215-search-curated-list-t.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [216-search-curated-list-u.png](../reference/beli/216-search-curated-list-u.png) | R — B23, representatives 197 / 207 / 217 | B23 |
| [217-search-curated-list-v.png](../reference/beli/217-search-curated-list-v.png) | V | B23 |
| [218-search-curated-share-sheet.png](../reference/beli/218-search-curated-share-sheet.png) | V | B23 |
| [219-search-results-loading.png](../reference/beli/219-search-results-loading.png) | V | B22 |
| [220-search-restaurants-empty.png](../reference/beli/220-search-restaurants-empty.png) | V | B22 |
| [221-search-restaurants-no-results.png](../reference/beli/221-search-restaurants-no-results.png) | V | B22 |
| [222-search-missing-place-dialog.png](../reference/beli/222-search-missing-place-dialog.png) | V | B22 |
| [223-search-city-initial.png](../reference/beli/223-search-city-initial.png) | V | B22 |
| [224-search-city-suggestions.png](../reference/beli/224-search-city-suggestions.png) | V | B22 |
| [225-search-members-empty.png](../reference/beli/225-search-members-empty.png) | V | B22 |
| [226-search-members-contacts-gate.png](../reference/beli/226-search-members-contacts-gate.png) | V | B22 |
| [227-search-members-initial.png](../reference/beli/227-search-members-initial.png) | V | B22 |
| [228-search-members-loading.png](../reference/beli/228-search-members-loading.png) | V | B22 |
| [229-search-members-results.png](../reference/beli/229-search-members-results.png) | V | B22 |
| [230-search-explore-location-gate.png](../reference/beli/230-search-explore-location-gate.png) | V | B01, B13 |
| [231-lists-trending-a.png](../reference/beli/231-lists-trending-a.png) | V | B24 |
| [232-lists-trending-sort.png](../reference/beli/232-lists-trending-sort.png) | V | B24 |
| [233-lists-trending-filters.png](../reference/beli/233-lists-trending-filters.png) | V | B24 |
| [234-lists-trending-filter-city.png](../reference/beli/234-lists-trending-filter-city.png) | V | B24 |
| [235-lists-trending-filters-lower.png](../reference/beli/235-lists-trending-filters-lower.png) | V | B24 |
| [236-lists-trending-filter-good-for.png](../reference/beli/236-lists-trending-filter-good-for.png) | V | B24 |
| [237-lists-trending-filter-cuisine.png](../reference/beli/237-lists-trending-filter-cuisine.png) | V | B24 |
| [238-lists-trending-filter-price.png](../reference/beli/238-lists-trending-filter-price.png) | V | B24 |
| [239-lists-trending-filter-borough.png](../reference/beli/239-lists-trending-filter-borough.png) | V | B24 |
| [240-lists-trending-filter-neighborhood.png](../reference/beli/240-lists-trending-filter-neighborhood.png) | V | B24 |
| [241-lists-trending-filter-country.png](../reference/beli/241-lists-trending-filter-country.png) | V | B24 |
| [242-lists-trending-overflow.png](../reference/beli/242-lists-trending-overflow.png) | V | B08, B24 |
| [243-friend-profile-overflow.png](../reference/beli/243-friend-profile-overflow.png) | V | B25 |
| [244-friend-been-list-a.png](../reference/beli/244-friend-been-list-a.png) | V | B26 |
| [245-friend-been-sort.png](../reference/beli/245-friend-been-sort.png) | V | B26 |
| [246-friend-been-overflow.png](../reference/beli/246-friend-been-overflow.png) | V | B08, B26 |
| [247-friend-want-loading.png](../reference/beli/247-friend-want-loading.png) | V | B26 |
| [248-friend-want-list-a.png](../reference/beli/248-friend-want-list-a.png) | V | B26 |
| [249-friend-guides-a.png](../reference/beli/249-friend-guides-a.png) | V | B27 |
| [250-friend-paid-guide-loading.png](../reference/beli/250-friend-paid-guide-loading.png) | V | B28 |
| [251-friend-paid-guide-locked.png](../reference/beli/251-friend-paid-guide-locked.png) | V | B28 |
| [252-friend-subscription-offer.png](../reference/beli/252-friend-subscription-offer.png) | V | B28 |
| [253-friend-request-guide-a.png](../reference/beli/253-friend-request-guide-a.png) | V | B27 |
| [254-friend-request-guide-sort.png](../reference/beli/254-friend-request-guide-sort.png) | V | B27 |
| [255-friend-request-guide-b.png](../reference/beli/255-friend-request-guide-b.png) | V | B27 |
| [256-friend-request-guide-bottom.png](../reference/beli/256-friend-request-guide-bottom.png) | V | B27 |
| [257-friend-guides-b.png](../reference/beli/257-friend-guides-b.png) | V | B27 |
| [258-friend-guides-c.png](../reference/beli/258-friend-guides-c.png) | V | B27 |
| [259-friend-guides-bottom.png](../reference/beli/259-friend-guides-bottom.png) | V | B27 |
| [260-friend-generated-guide.png](../reference/beli/260-friend-generated-guide.png) | V | B27 |
| [261-friend-overlapping-bookmarks-empty.png](../reference/beli/261-friend-overlapping-bookmarks-empty.png) | V | B29 |
| [262-friend-overlap-select-friends.png](../reference/beli/262-friend-overlap-select-friends.png) | V | B29 |
| [263-friend-overlap-map-empty-dialog.png](../reference/beli/263-friend-overlap-map-empty-dialog.png) | V | B29 |
| [264-friend-taste-a.png](../reference/beli/264-friend-taste-a.png) | V | B05 |
| [265-friend-taste-cuisines.png](../reference/beli/265-friend-taste-cuisines.png) | V | B05 |
| [266-friend-taste-cities.png](../reference/beli/266-friend-taste-cities.png) | V | B05 |
| [267-friend-taste-countries.png](../reference/beli/267-friend-taste-countries.png) | V | B05 |
| [268-friend-taste-sort.png](../reference/beli/268-friend-taste-sort.png) | V | B05 |
| [269-friend-taste-average-score.png](../reference/beli/269-friend-taste-average-score.png) | V | B05 |
| [270-friend-taste-cities-middle.png](../reference/beli/270-friend-taste-cities-middle.png) | V | B05 |
| [271-friend-following-loading.png](../reference/beli/271-friend-following-loading.png) | V | B03 |
| [272-friend-following-a.png](../reference/beli/272-friend-following-a.png) | V | B03 |
| [273-friend-followers-a.png](../reference/beli/273-friend-followers-a.png) | V | B03 |
| [274-friend-suggested-people.png](../reference/beli/274-friend-suggested-people.png) | V | B25 |
| [275-friend-activity-a.png](../reference/beli/275-friend-activity-a.png) | V | B04, B25 |
| [276-friend-custom-guides-grid.png](../reference/beli/276-friend-custom-guides-grid.png) | V | B25, B27 |
| [277-notifications-a.png](../reference/beli/277-notifications-a.png) | V | B30 |
| [278-notifications-featured-list-detail.png](../reference/beli/278-notifications-featured-list-detail.png) | V | B23, B30 |
| [279-notifications-suggested-members.png](../reference/beli/279-notifications-suggested-members.png) | V | B30 |
| [280-misc-main-menu.png](../reference/beli/280-misc-main-menu.png) | V | B31 |
| [281-settings-overview.png](../reference/beli/281-settings-overview.png) | V | B31 |
| [282-settings-account.png](../reference/beli/282-settings-account.png) | V | B32 |
| [283-settings-email-form.png](../reference/beli/283-settings-email-form.png) | V | B32 |
| [284-settings-phone-form.png](../reference/beli/284-settings-phone-form.png) | V | B32 |
| [285-settings-password-form.png](../reference/beli/285-settings-password-form.png) | V | B32 |
| [286-settings-payment-loading.png](../reference/beli/286-settings-payment-loading.png) | V | B33 |
| [287-settings-payment-empty.png](../reference/beli/287-settings-payment-empty.png) | V | B33 |
| [288-settings-payment-add-card.png](../reference/beli/288-settings-payment-add-card.png) | V | B33 |
| [289-settings-school-introduction.png](../reference/beli/289-settings-school-introduction.png) | V | B33 |
| [290-settings-company-introduction.png](../reference/beli/290-settings-company-introduction.png) | V | B33 |
| [291-settings-privacy.png](../reference/beli/291-settings-privacy.png) | V | B34 |
| [292-settings-blocked-empty.png](../reference/beli/292-settings-blocked-empty.png) | V | B34 |
| [293-settings-muted-empty.png](../reference/beli/293-settings-muted-empty.png) | V | B34 |
| [294-settings-cookies.png](../reference/beli/294-settings-cookies.png) | V | B34 |
| [295-settings-notifications-a.png](../reference/beli/295-settings-notifications-a.png) | V | B35 |
| [296-settings-notifications-b.png](../reference/beli/296-settings-notifications-b.png) | V | B35 |
| [297-settings-notifications-bottom.png](../reference/beli/297-settings-notifications-bottom.png) | V | B35 |
| [298-settings-app.png](../reference/beli/298-settings-app.png) | V | B36 |
| [299-settings-distance-units.png](../reference/beli/299-settings-distance-units.png) | V | B36 |
| [300-settings-faq-a.png](../reference/beli/300-settings-faq-a.png) | V | B36 |
| [301-settings-faq-expanded.png](../reference/beli/301-settings-faq-expanded.png) | V | B36 |

Initial boundary totals: **301 screenshots; 227 visually inspected; 74 repeated-content captures represented by reviewed samples.** The 227 include the distinct reservation-slot variant in curated-list capture 207.

## Evidence discrepancies and limits

- 02 is already dimmed by the share-choice sheet; it is not a clean initial-list screenshot. 03 has a black backdrop. Later list captures establish the underlying layout.
- 83 was described as possible final rows, but subsequent captures continue the same starter list; no terminal state is established.
- 141 and 238 visibly show four price levels (`$` through `$$$$`); 141 selects `$$$`. Original flow prose has malformed currency notation.
- 55 shows the Order control without clear selected fill; do not claim a verified selected Order state.
- 277 visibly shows Earlier; automatic New → Earlier behavior is attributed to notes only.
- Counts and relative times change across captures; these are a live account, not consistent seed fixtures.
- PLAN §3 contains prior third-party ranking research. This inventory does not elevate binary-search, equal spacing, first-score defaults or tie handling into verified Beli behavior.
- No general network-error screen, write-success state, onboarding, comparison sequence or score reveal appears in the initial boundary. Posting remains pending.

## Reviewed addendum — captures 302–322

These 21 images arrived during drafting and were visually inspected in two grouped sheets. Review boundary is now **01–322: 248 visually inspected, 74 represented repeated-content files**. Capture is still ongoing; files above 322 are outside this draft boundary until reconciliation. This addendum supersedes initial missing-evidence statements about leaderboard structure, edit-profile entry forms, profile-share entry and utility empty states; mutation outcomes remain unknown.

### B37 — Member leaderboard

**Evidence:** [302-leaderboard-loading.png](../reference/beli/302-leaderboard-loading.png), [303-leaderboard-been.png](../reference/beli/303-leaderboard-been.png), [304-leaderboard-influence.png](../reference/beli/304-leaderboard-influence.png), [305-leaderboard-notes.png](../reference/beli/305-leaderboard-notes.png), [306-leaderboard-photos.png](../reference/beli/306-leaderboard-photos.png), [307-leaderboard-members-filter.png](../reference/beli/307-leaderboard-members-filter.png), [308-leaderboard-friends-photos.png](../reference/beli/308-leaderboard-friends-photos.png), [309-leaderboard-city-filter.png](../reference/beli/309-leaderboard-city-filter.png).

**Observed layout, data and states:** Back/serif Leaderboard heading; Been/Influence/Notes/Photos segmented control, metric explanation, All Members/All Cities chips and rank/avatar/handle/count rows. Skeleton and four loaded metrics observed. Influence copy attributes member referrals; Notes counts notes/favorite dishes; Photos counts restaurants photographed, not total images. Member sheet offers All Members/Friends; Friends Photos shows empty illustration and Find friends despite the account having follows, so eligibility must not be inferred. City sheet has search, All Cities/current selection, city checkboxes, X and pinned Apply.

**Navigation, scrolling and uncertainty:** Flow notes record friend Rank card → leaderboard. Tabs/filter entry states are visible; city filter was not applied. Bottom tabs persist. Populated list scroll/pagination and member eligibility, competitive ranking math, filter commit, member-row routing unknown.

### B38 — Edit profile and profile sharing

**Evidence:** [310-settings-edit-profile.png](../reference/beli/310-settings-edit-profile.png), [311-settings-profile-name-form.png](../reference/beli/311-settings-profile-name-form.png), [312-settings-profile-username-form.png](../reference/beli/312-settings-profile-username-form.png), [313-settings-profile-bio-form.png](../reference/beli/313-settings-profile-bio-form.png), [314-settings-home-city-form.png](../reference/beli/314-settings-home-city-form.png), [315-settings-profile-photo-menu.png](../reference/beli/315-settings-profile-photo-menu.png), [316-settings-social-links-locked.png](../reference/beli/316-settings-social-links-locked.png), [317-profile-share-sheet.png](../reference/beli/317-profile-share-sheet.png).

**Observed layout, data and states:** Edit profile has avatar/Edit profile photo, name, username, home city, bio, locked Instagram/TikTok and Account settings. Name form has first/last fields; username has @, validity indicator and warning that share-list link changes; bio has multiline field and 80 characters remaining. Forms have Cancel/Save. Home-city dialog has search/X/Save. Photo sheet offers library/camera/delete/cancel. Social-links invite lock requires one successful invite. Profile Share opens native link sheet.

**Navigation, scrolling and uncertainty:** Notes record own Profile → Edit profile. Visible child forms and share sheet support entry structure; no edit, upload, delete-photo, invite or share target performed. Selection/validation errors, successful rename/link redirects and photo permissions unknown. Roam stable-ID links are a deliberate proposal differing from Beli username warning.

### B39 — Referral unlock hub

**Evidence:** [318-misc-unlock-loading.png](../reference/beli/318-misc-unlock-loading.png), [319-misc-unlock-features-a.png](../reference/beli/319-misc-unlock-features-a.png), [320-misc-unlock-features-bottom.png](../reference/beli/320-misc-unlock-features-bottom.png).

**Observed layout, data and states:** Unlock features back/title, initial skeleton, then credits available (zero), Missing credits link, 0/5 status and explanation; five icon/text cards with Unlock: average scores, dish search, reservation sharing, stealth mode, social links. Invite friends stays at bottom across scroll. Stealth copy mentions hiding specific activity from newsfeed.

**Navigation, scrolling and uncertainty:** Menu Unlock entry inferred from matching drawer label; exact click path not newly reported in reviewed notes. No unlock/invite action used. Credit accounting, successful unlock, stealth controls and persistence unknown; no proof that current tracking can be private without unlocking.

### B40 — Reservation and subscription management empties

**Evidence:** [321-misc-reservations-empty.png](../reference/beli/321-misc-reservations-empty.png), [322-misc-subscriptions-empty.png](../reference/beli/322-misc-subscriptions-empty.png).

**Observed layout, data and states:** Your Reservations uses back/title and Upcoming/Past sections with no reservations. Your Subscriptions has creator eligibility/checklist, disabled application button and subscribed-accounts section with No subscriptions yet. Checklist mentions 200 ratings, 10 referrals, 3+ week streak and 30+ days membership.

**Navigation, scrolling and uncertainty:** Menu destinations match drawer labels (route inferred from visible menu/screens). No booking, application or subscription occurred. Populated management/cancel/restore/error states unknown. Captured checklist is Beli policy, not Roam scope.

### Addendum review ledger

| Screenshot | Review | Inventory |
|---|---|---|
| [302-leaderboard-loading.png](../reference/beli/302-leaderboard-loading.png) | V — grouped visual inspection | B37 |
| [303-leaderboard-been.png](../reference/beli/303-leaderboard-been.png) | V — grouped visual inspection | B37 |
| [304-leaderboard-influence.png](../reference/beli/304-leaderboard-influence.png) | V — grouped visual inspection | B37 |
| [305-leaderboard-notes.png](../reference/beli/305-leaderboard-notes.png) | V — grouped visual inspection | B37 |
| [306-leaderboard-photos.png](../reference/beli/306-leaderboard-photos.png) | V — grouped visual inspection | B37 |
| [307-leaderboard-members-filter.png](../reference/beli/307-leaderboard-members-filter.png) | V — grouped visual inspection | B37 |
| [308-leaderboard-friends-photos.png](../reference/beli/308-leaderboard-friends-photos.png) | V — grouped visual inspection | B37 |
| [309-leaderboard-city-filter.png](../reference/beli/309-leaderboard-city-filter.png) | V — grouped visual inspection | B37 |
| [310-settings-edit-profile.png](../reference/beli/310-settings-edit-profile.png) | V — grouped visual inspection | B38 |
| [311-settings-profile-name-form.png](../reference/beli/311-settings-profile-name-form.png) | V — grouped visual inspection | B38 |
| [312-settings-profile-username-form.png](../reference/beli/312-settings-profile-username-form.png) | V — grouped visual inspection | B38 |
| [313-settings-profile-bio-form.png](../reference/beli/313-settings-profile-bio-form.png) | V — grouped visual inspection | B38 |
| [314-settings-home-city-form.png](../reference/beli/314-settings-home-city-form.png) | V — grouped visual inspection | B38 |
| [315-settings-profile-photo-menu.png](../reference/beli/315-settings-profile-photo-menu.png) | V — grouped visual inspection | B38 |
| [316-settings-social-links-locked.png](../reference/beli/316-settings-social-links-locked.png) | V — grouped visual inspection | B38 |
| [317-profile-share-sheet.png](../reference/beli/317-profile-share-sheet.png) | V — grouped visual inspection | B38 |
| [318-misc-unlock-loading.png](../reference/beli/318-misc-unlock-loading.png) | V — grouped visual inspection | B39 |
| [319-misc-unlock-features-a.png](../reference/beli/319-misc-unlock-features-a.png) | V — grouped visual inspection | B39 |
| [320-misc-unlock-features-bottom.png](../reference/beli/320-misc-unlock-features-bottom.png) | V — grouped visual inspection | B39 |
| [321-misc-reservations-empty.png](../reference/beli/321-misc-reservations-empty.png) | V — grouped visual inspection | B40 |
| [322-misc-subscriptions-empty.png](../reference/beli/322-misc-subscriptions-empty.png) | V — grouped visual inspection | B40 |

## Capture recheck — 2026-10-13 (no additions)

Recursive file/hash comparison found no new reference files, no changed PNGs/brief, and no change to `flows.md` since the reviewed addendum. Boundary remains 322, with 248 unique captures visually inspected and 74 repeated-content files represented. Re-inspected 172, 151 and 162 at full size for rating/posting distinctions; no change to their observed evidence. A Post control on comment detail is a comment action, not proof of a rating publication composer.

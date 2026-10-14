# Beli capture brief

## Why you're doing this

I'm building an iOS app that is "Beli, but for travel." Beli is a restaurant app where you rank places by comparing them against places you've already been, then share those rankings with friends. My app does the same thing for travel "experiences": hikes, day trips, museums, restaurants, anything you do while traveling.

The plan is to recreate nearly every Beli screen and flow, adapted for travel. A different AI agent will build the app, and it will never see Beli. **Your screenshots and notes are its only reference.** If a screen, menu, or state isn't captured, it won't get built. So aim for complete coverage of the app's structure: layouts, navigation, components, and states. What's in my lists doesn't matter; what the screens look like and how they connect does.

## Ground rules (this is my real account)

- **Look, don't act.** Don't rate, post, follow, unfollow, like, comment, invite, bookmark, share, save edits, change settings, or grant permissions (contacts, location, notifications, photos).
- If something opens a confirm dialog, share sheet, or edit form: screenshot it, then cancel or back out.
- Don't log out. Getting back in needs a code from my phone.
- If you need a code, password, or decision, stop and ask me.

## How to capture

- Use the iPhone Mirroring app. Capture only its window, not the whole desktop. One way:
  ```
  osascript -e 'tell application "System Events" to get {position, size} of window 1 of process "iPhone Mirroring"'
  screencapture -x -R<x>,<y>,<w>,<h> <file>.png
  ```
- Save everything to `~/Desktop/projects/capstone/reference/beli/`.
- Name files `NN-area-screen[-state][-part].png`, numbered in the order you capture them, for example:
  - `01-feed-home.png`
  - `02-feed-home-b.png` (second scroll position)
  - `15-place-detail-share-sheet.png`
  - `22-search-results-empty.png`
- Use these area names: `feed`, `search`, `place`, `rate`, `lists`, `profile`, `friend`, `leaderboard`, `notifications`, `settings`, `misc`.

## What "everything" means

For every screen you reach:
- **Prioritize unique screens and flows over repeated content.** For long lists, capture the top, one representative middle position, and the bottom if readily reachable. For infinite lists, stop once every distinct item layout is captured. Skip extra positions that only repeat the same layout with different places or people. Record skipped repetitive content in the final “Not captured” section of `flows.md`.
- **Every tab and segmented control.** Screenshot each option.
- **Every `…`, filter, and sort button.** Screenshot the menu or sheet it opens.
- **Long-press** cards and list rows. Screenshot any context menu.
- **States:** empty, loading, and error states when you see them, plus "no results" in search.
- **FAQ:** capture its overview and one representative expanded answer; the user asked to skip exhaustive FAQ coverage.

## Priority order

Work through these in order, so the important ones are done even if you run out of time.

1. **Profile (mine).** Header and stats; each list (Been, Want to Try, Recs, and any others); list sort and filter options; the map view of my places; followers and following lists; badges or achievements; any taste or stats pages.
2. **Place detail page.** Pick a few places, including one I've rated and one I haven't. Capture the scores (mine, friends', overall), friends who've been, photos, notes, the map snippet, and every action button (open each, then cancel).
3. **Rating entry point.** Open "add or rate" on a place and capture the first screen, the one asking whether I liked it. **Do not tap any option**; back out. I'll capture the rest of the rating flow myself.
4. **Feed.** The home feed with each kind of feed item you can find, then open an item and capture its detail view. Look but don't like or comment.
5. **Search and discover.** The search screen before typing, while typing, results, filters, the map view of results, and any curated lists or guides.
6. **A friend's profile.** Open one from the feed and capture the same parts as my profile.
7. **Leaderboard, notifications, activity.**
8. **Settings.** Every page and sub-page, plus the edit-profile form (don't save).
9. **Anything else.** Invite or referral screens and any feature you find that isn't listed above.

## Deliverables

1. **The screenshots.**
2. **`flows.md` in the same folder**, with:
   - One line per screenshot: filename, what the screen is for, and its main parts.
   - Navigation paths written like `01-feed-home → tap avatar → 30-friend-profile`.
   - Anything a screenshot can't show: animations, swipe gestures, haptics, long-press behavior, what is pinned while scrolling.
3. **A final section in `flows.md`, "Not captured":** anything you couldn't reach and why.

# Capstone plan: Roam, "Beli, but for experiences" (iOS)

Saved 2026-10-04 from a planning session with Claude Code. This file holds everything decided so far, the workflow, and the open questions. Start a new session by asking Claude to read it (see "Resuming" at the bottom).

---

## 1. Vision

An iOS app that recreates nearly every screen and flow of **Beli** (the restaurant-ranking social app), adapted for travel.

- **Experiences instead of restaurants.** An experience can be a hike, a day trip, a restaurant, a museum, or anything else you do while traveling.
- **Ranking works like Beli.** You compare a new experience against ones you've already ranked, and that produces a 0–10 score (see §3).
- **Simple feed for v1.** Friends' posts in reverse-chronological order, with no algorithm.
- **A globe on every profile.** Like Apple Maps or Google Earth, showing everywhere the person has been.
- **Copy Beli's UX, not its brand.** Recreate flows and layout patterns, but not Beli's name, logo, icons, illustrations or copy. Don't decompile the app or use its API.

## 2. Decisions made

| Topic | Decision |
|---|---|
| Platform | Native iOS, SwiftUI, local development in Xcode |
| Maps and place search | **Apple MapKit**: `MKLocalSearch` for places (free, no API key) and SwiftUI `Map` for the globe |
| Apple Developer Program | **Already paid**, so Sign in with Apple and push notifications are available |
| Ranking scope | **Confirmed:** rank experiences within their category. Cities receive derived scores from experience ratings (2026-10-13) |
| Capturing Beli's UI | iPhone Mirroring on the Mac. A computer-use agent (Codex) does the broad sweep; you capture the sensitive flows yourself (§5) |
| Building | Spec first, then **one long build run at `/effort max`** that verifies its own work (§6) |
| Project file | **XcodeGen** (`project.yml`). Never hand-edit `.pbxproj` |
| Score visibility (D01) | **A 0–10 score shows from the first rating** in a category, unlike Beli's 10-item threshold. Scores shift as more items are ranked (2026-10-13) |
| Posting (D03) | **Every completed rating posts to followers' feeds automatically**, with notes/photos if added, like Beli (2026-10-13) |
| v1 scope (D07) | **Core + adapted only**: the Keep and Adapt items in the §6 triage. Guides, list sharing, leaderboard, imports, curated/trending discovery and city insights/city scores are deferred past v1 (city-score principles below still stand for later) (2026-10-13) |
| Sign-in (D06) | **Sign in with Apple + email.** No phone sign-in, so no SMS provider (2026-10-13) |
| Backend | **Confirmed 2026-10-13:** Supabase running locally via Docker (database, auth, photo storage, access rules for public profiles and private notes). The same code later deploys to hosted Supabase |
| Minimum iOS | **iOS 18** (2026-10-13). Wider device support; no Liquid Glass-only APIs |
| App name | **Roam**, "Beli but for experiences" (2026-10-13) |
| Categories | **7 broad categories**, each with its own ranked list: Food & Drink, Outdoors, Day Trips, Culture, Nightlife, Activities, Stays (2026-10-13) |
| What an experience is | **Always exactly one MapKit place**, like Beli. No custom multi-pin trips. A day trip is logged as its destination, e.g. the Hakone locality (2026-10-13) |
| Social model | **One-way follow, public profiles**, like Beli (2026-10-13) |
| Globe | **Pins, shaded visited countries, and an "X countries · Y cities" stat.** Friends' profiles show the same view (2026-10-13) |
| City scores | **Personal and global derived scores**, with category breakdowns and balanced contributions. More unique visitors increase confidence in the global score (2026-10-13) |

### Rating-flow fidelity (confirmed 2026-10-13)

Roam must follow Beli’s user-facing rating flow. The user authorized defining Roam’s own comparison-selection, tie and score rules **after reviewing the missing captures**, while preserving that flow. This does not approve specific score bands, first-rating defaults, permanent ties, extra confirmation steps or a different manual scoring UI. See SPEC R05 for public-source research and pending interaction details. Historical algorithm claims in §3 remain unverified implementation hypotheses.

### City scoring principles (confirmed 2026-10-13)

Users rank experiences within the seven confirmed categories; city scores are derived from those ratings rather than rated directly.

1. **Your city score:** calculated from the experiences you've ranked in that city.
2. **Global city score:** calculated from community experience ratings in that city, with more unique visitors giving the result greater weight and confidence.
3. **Category breakdown:** visible alongside the overall city score, so excellent restaurants don't hide weak outdoor experiences.
4. **Balanced contributions:** prevent one prolific reviewer or a much larger volume of ratings in one category from dominating the city score.

Favoring a large sample means increasing confidence in the quality estimate, rather than awarding a popularity bonus. A city with very few ratings should be moderated toward a baseline; enough independent ratings can support a high or low score.

The exact formula, baseline, thresholds, and contribution weights are intentionally deferred to the specification phase. These principles are approved; no numerical scoring rules have been chosen yet.

## 3. How Beli ranks today (researched 2026-10-04)

- **Separate categories.** Restaurants, bars, bakeries, coffee shops and ice cream shops each have their own ranked list. A coffee shop is only compared against coffee shops.
- **Step 1, bucket.** Pick a green "I liked it!", a yellow "It was fine" or a red "I didn't like it". This places the new item in the right part of the list.
- **Step 2, comparisons.** "Which did you like more?" against places you've already ranked. It's a binary search through the list, so roughly 4 questions at 10 items and 7 at 100.
- **"Too tough" button.** You can skip a comparison. How Beli resolves a skip isn't public.
- **Step 3, score.** List position is converted to a 0.0–10.0 score (e.g. 6.2) by spacing items evenly. Your first-ever rating gets a default score for its bucket, and scores shift as you add more.
- **Two scores per place.** A predicted score for you, and a score from your friends' ratings.
- **Not public:** the exact score range of each bucket, how a skipped comparison resolves, and whether you can re-rank later. Confirm these from the screenshots, or set our own rules in the spec.

Sources:
- [Beli (Wikipedia)](https://en.wikipedia.org/wiki/Beli_(app))
- [HackerNoon: Beli's binary search rating system](https://hackernoon.com/belis-binary-search-rating-system-explained)
- [Anson Biggs: Rating has never been so good](https://notes.ansonbiggs.com/rating-has-never-been-so-good/)
- [The Harvard Crimson, Feb 2026](https://www.thecrimson.com/article/2026/2/26/beli-inquiry/)
- [Pratt IxD design critique](https://ixd.prattsi.org/2022/02/design-critique-beli-ios-app/)

**Note:** Beli is also on Google Play (`com.beliapp.myapp`), so an Android emulator could run it. We chose iPhone Mirroring because we want the iOS screens.

## 4. Environment (checked 2026-10-04)

**Already installed:**
- macOS 15.7.9 on Apple Silicon
- Xcode 26.3 with the iOS 26.2 simulator
- Homebrew, Docker, ffmpeg, Node, git

**Still to do:**
- `brew install xcodegen xcbeautify` (XcodeGen generates the Xcode project from `project.yml`; xcbeautify makes build output readable)
- `brew install supabase/tap/supabase` (if we confirm Supabase)
- `git init` in this folder (it isn't a git repo yet)
- Add **XcodeBuildMCP** to Claude Code (check its README for the current `claude mcp add …` command). It lets Claude build, launch, tap through and screenshot the simulator, which is the verification loop. Fallback without it: `xcrun simctl io booted screenshot`.
- Find your **Team ID** (developer.apple.com → Membership) and choose a **bundle ID**, like `com.daniellarkin.<appname>`.

## 5. Phase 0: capturing Beli (done 2026-10-13)

- **Brief for the agent:** `reference/beli/CAPTURE_BRIEF.md`. It covers why the capture matters, the look-but-don't-act rules, naming, what counts as full coverage, the priority order, and the deliverables.
- **Prompt to give Codex:** "Read ~/Desktop/projects/capstone/reference/beli/CAPTURE_BRIEF.md and follow it exactly. Start with the priority list and keep going until everything is covered." If Codex can't read local files, paste the brief's contents instead.
- **Before Codex starts:**
  - Open iPhone Mirroring with Beli on the feed.
  - Give Codex Screen Recording permission (System Settings → Privacy & Security → Screen Recording).
  - Check the first 2–3 screenshots before leaving it to run.
- **What you capture yourself:** record on the iPhone itself (Control Center screen recording), because mirroring keeps the phone locked. Then AirDrop the videos to `reference/beli/`.
  - **The full rating flow:** bucket choice → each comparison → the "too tough" button → score reveal. Rate a place you've really been to; you can delete it afterward.
  - **Sign-up and onboarding.** Logging out only shows the welcome and phone-number screens, because entering your number logs you back into your existing account. Fill the gap with the App Store screenshots, a YouTube walkthrough, or a second phone number.
- **Processing:** Claude splits the videos into frames with ffmpeg, removes duplicate frames, and adds them to the inventory.

## 6. Workflow after capture

1. **Inventory (Claude).** From the screenshots and `flows.md`, write `docs/beli-inventory.md`: every screen with its purpose, components, data shown, and how you get in and out.
2. **Translation (together).** Map each Beli screen to the travel version: keep, adapt or drop. Answer the open questions in §9.
3. **Spec (Claude).** Write these files:
   - `SPEC.md`: screens, flows, data model, ranking algorithm, globe, feed
   - `MILESTONES.md`: ordered milestones, each with acceptance criteria
   - `CLAUDE.md`: build, test and run commands, conventions, the verification loop, "never edit pbxproj"
   - `DECISIONS.md`: starts empty; the build agent logs its own judgment calls here
4. **Build run at `/effort max`** with the prompt in §8.
5. **Review** with `/code-review` (or `/code-review ultra` for a multi-agent cloud review), then iterate.

**Why this works:** no setting can turn one paragraph into about 40 screens plus a backend. A single long run succeeds when it has:
- a detailed spec with acceptance criteria for every screen,
- reference screenshots,
- a build-and-check loop the agent runs itself,
- milestones, so it's never stuck in a broken state.

### Feature triage (proposed 2026-10-13; v1 = Keep + Adapt, confirmed 2026-10-13)

The test for each feature: does it help someone remember, rank or discover experiences, or see where friends have been? Only Keep and Adapt go into `SPEC.md`.

- **Keep:** bucket → comparisons → 0–10 score (per category); Been / Want to Try lists (rename, e.g. "Bucket List"); reverse-chronological feed with post detail and comments; follow, followers/following, friend profile; place detail with your score and friend score; search for places and members; notifications; edit profile and settings (trimmed).
- **Adapt:** places map → the globe; taste profile → travel profile (categories, cities, countries); streak and yearly goal → "new experiences this year"; places you both want to try → shared bucket list.
- **Later:** featured/curated lists and guides; leaderboard; Rec Score (predicted score); import from Google Maps / Mapstr.
- **Drop:** popular dishes, dish search, reservations, hours editing; invite-to-unlock credits, subscriptions, paid guides, stealth mode.

## 7. Draft milestones and technical approach

1. **Skeleton:** XcodeGen project, tab bar, design system (colors, type, components), local Supabase running, and a quick test that the MapKit globe renders in the simulator.
2. **Auth and onboarding:** Sign in with Apple, plus email or phone sign-in. Local Supabase has test codes, so no SMS provider is needed.
3. **Experiences:** MapKit search, custom experiences (e.g. "Day trip to Hakone" with one or more pins), detail page.
4. **Ranking flow and scoring logic:** buckets → comparisons → "too tough" → score. Written as plain Swift and unit-tested.
5. **Lists and profile:** Been / Want to Go lists and the profile globe.
6. **Social:** following, friend profiles, the reverse-chronological feed.
7. **Secondary screens:** leaderboard, notifications (push now possible), settings, sharing.
8. **Polish:** empty, loading and error states. Also a seed script with fake friends and experiences, so the feed and globes aren't empty.

**Globe.**
- **Plan:** SwiftUI `Map` with `.mapStyle(.imagery(elevation: .realistic))` or `.hybrid(elevation: .realistic)`. Zoomed out, MapKit draws a real 3D globe.
  - Add a pin per experience; tapping it opens the experience.
  - Shade visited countries using `MapPolygon` overlays built from a bundled country-outline file (Natural Earth GeoJSON).
  - Show a mini globe in the profile header that expands to full screen.
- **Alternative:** a custom-built stylized globe (SceneKit or RealityKit). More work.

**Stack:** SwiftUI, `@Observable`, `supabase-swift` via Swift Package Manager, code organized by feature.

## 8. Build prompt (run at `/effort max` once the spec files exist)

```
Read CLAUDE.md, SPEC.md, MILESTONES.md and docs/beli-inventory.md.
Reference screenshots are in reference/beli/.

Build the app one milestone at a time, in order. For each milestone:
1. Implement it per SPEC.md.
2. Run xcodegen, build, and run the unit tests. Fix all errors before moving on.
3. Launch in the simulator, go through every screen in the milestone,
   and save a screenshot of each to screenshots/<milestone>/.
4. Check each screen against its acceptance criteria and the matching
   reference screenshot. Fix what doesn't match.
5. Commit, naming the milestone.

Don't stop between milestones to ask me. If the spec is unclear, pick the
option closest to Beli's behavior, log it in DECISIONS.md, and keep going.
At the end, summarize what was built, what's left, and every DECISIONS.md entry.
```

## 9. Open questions (answer before or during the spec phase)

**Decided 2026-10-13 (see §2):** #1 (name), #4 (iOS 18), #5 (categories), #10 (one place per experience), #12 (one-way public follow), #15 (globe contents).

**Setup and identity**
1. **App name:** decided 2026-10-13: **Roam**. Proposed bundle ID `com.daniellarkin.roam`.
2. **Team ID and bundle ID.**
3. **Backend:** confirm Supabase running locally. The alternatives are Firebase or CloudKit; CloudKit makes friend and feed queries awkward.
4. **Minimum iOS:** iOS 18, for wider device support and newer MapKit place categories; or iOS 26 only, to use the new Liquid Glass design throughout.

**Ranking**

5. **Category list.** Proposed: Food & Drink, Outdoors (hikes, parks, beaches), Day Trips, Culture (museums, landmarks), Nightlife, Activities, Stays. Can a user rank in a category with only one item? Should Food & Drink be split the way Beli does (restaurants, bars, coffee)?
6. **"All experiences" list on the profile.** Show one combined list across categories? If so, how is it ordered, given each category's scores are separate? Sorting by score is the simplest option.
7. **Score range for each bucket.** Confirm from captures, or define our own. Proposed: liked it 6.7–10, fine 3.4–6.6, didn't like 0–3.3.
8. **"Too tough" behavior.** Proposed: treat it as a tie and place the new item right next to the one it was compared with.
9. **Re-ranking and deleting.** Can a user re-rank an experience later? Proposed: yes, by removing it and running the comparisons again.

**Experiences**

10. **What an experience is.** Must every experience have at least one pin? Can a day trip or multi-day trip have several pins? Should there be visit dates, and can someone log the same place more than once?
11. **Want to Go list.** The travel version of Beli's "Want to Try." Name it, e.g. "Bucket List."

**Social**

12. **Relationship model.** One-way follow like Beli, or mutual friends? Are profiles public or friends-only?
13. **What a post contains.** Rating, notes, photos? Likes and comments in v1, or later?
14. **Beli features to drop or postpone:** reservations, predicted "rec" score and taste matching, city leaderboards, invite and referral rewards. Decide during translation.

**Globe and sign-up**

15. **What the globe shows:** pins only, or pins plus shaded countries and stats like "X countries, Y cities"? Does the globe on a friend's profile show the same as on your own?
16. **Sign-in methods:** Sign in with Apple plus phone? Real phone codes need an SMS provider (e.g. Twilio) eventually; local development uses test codes.
17. **Photos:** upload size limits and how many photos per post.

## 10. Status and next steps

- [x] Plan agreed (this file)
- [x] `reference/beli/` created with `CAPTURE_BRIEF.md`
- [x] Codex captures screenshots and `flows.md` → `reference/beli/` (01–322)
- [x] Rating flow and onboarding captured on a new test account → `reference/beli/nc001`–`nc053` (screenshots, not video)
- [x] Install tools, `git init`, add XcodeBuildMCP (done 2026-10-13: xcodegen 2.46.0, xcbeautify 3.2.1, supabase 2.120.0; MCP is now named MobileBuildMCP, pinned to 2.7.1, project-scoped)
- [x] Inventory and drafts written: `docs/beli-inventory.md`, `docs/roam-*.md`, `docs/capture-gaps.md`, `SPEC.md`, `MILESTONES.md`
- [ ] Resolve the remaining decisions (§9 leftovers and D01–D12 in `docs/capture-gaps.md` / end of `SPEC.md`)
- [ ] Trim scope to the triage in §6, write `CLAUDE.md`, mark `SPEC.md` ready to build
- [ ] Build run at `/effort max`

## Resuming

Start a new Claude Code session in this folder and say:

> Read PLAN.md, SPEC.md, MILESTONES.md and docs/capture-gaps.md. Captures are done and the spec is drafted. Walk me through the remaining decisions (D01–D12) and the scope trim, then update the spec, write CLAUDE.md and mark it ready to build.

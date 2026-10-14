# Capture gaps and product decisions — draft

Review boundary: original screenshots 01–322 (initial 01–301 plus reviewed addendum 302–322), captured 2026-10-13; see [inventory](beli-inventory.md) for exact filenames and visual-review ledger. A later, user-authorized new-account session produced [53 additional reviewed local captures](beli-live-capture-addendum.md), now stored in `reference/beli/` as `nc001`–`nc053`. The original 01–322 files are unchanged.

## A. Missing evidence: prioritize additional captures

These are remaining reference gaps, not instructions to create more ratings. The user explicitly declined adding seven more test ratings to reach the score threshold.

| Priority / gap | Available evidence | Missing capture / ambiguity | Spec impact |
|---|---|---|---|
| P1 G01 — onboarding variants | B41 new-account sequence, nc001–nc030 in `reference/beli/`, plus B32 settings forms | One path now captured through first-use list. Alternate sign-in/provider, validation errors, permission-granted states, import success, returning user, and other first-run variants remain missing. | R02 can use Beli's observed sequence/layout; Roam provider and gating choices remain decisions. |
| P1 G02 — comparison variants | B42–B43 show first-item no-comparison, a two-item Too tough path, and a third-item preference path; Undo/Too tough/Skip controls visible | Effects of Undo and Skip, larger candidate sets, opposite sentiments, repeated Too tough, cancellation/back and category switching remain unseen. | R05 has current control/layout evidence but comparison-selection and tie math remain Roam-owned TBDs. |
| P0 G03 — numeric score reveal | B42 first-rank celebration explicitly states scores appear after 10 category spots; B43 has ranked #1–#3 with locked numeric scores | User chose to stop at three ratings. Tenth-rating transition, numeric reveal, changed prior scores, score labels and final CTA remain missing. | R05 must distinguish ordinal rank from locked numeric score; Roam's threshold is TBD. |
| P0 G04 — public posting | B42–B44 show optional enrichment before comparison, no separate composer in first three ratings, and own feed still empty | What followers see, whether notes/photos change publication, tenth-rating handoff, public/private note semantics, standalone post composer, and successful post remain unverified. | R10 uses observed enrichment order but cannot assert public activity timing. |
| P1 G05 — personal rated variants | B44 now shows own Been 3, rated detail, ordinal without score, Delete rating and confirmation | Rerank, revisit, numeric own score after threshold, populated filters and unlock transition remain unseen. | R03–R05 can use B44 for low-count rated state; later states remain TBD. |
| P1 G06 — Explore and personal maps | Denied gates 130–133/230; fixed-city map 194–196 | Granted Explore layout/filter tools, populated own maps, clustering, search-this-area, recenter, approximate location, selected-pin routing. Do not grant permission in this task. | R06 manual-city fallback is a Roam proposal. |
| P1 G07 — sharing/list creation | 03/33 share choices, native sheets 142/218, guides 249–260 | Selected-place share editor, generated image/link, recipient-open behavior, empty list link, custom-guide creation/edit/reorder, collaboration/invites/roles. | R11 link/selection/editor rules require own contract. |
| P1 G08 — pending utility capture | 280 drawer; 302–322 now cover leaderboard metrics/filters, edit-profile forms/share, unlock hub and reservation/subscription empty states | Successful profile edits/validation/photo selection, leaderboard eligibility/applied filters, unlocked own stats/calendar/recs, home-city autocomplete/preferences, invite/unlock outcomes, populated reservations/subscriptions management. | R08/R13 and optional parity scope. Reconcile late references before finalizing. |
| P2 G09 — social mutations/moderation | Follow/like/comment/report controls and empty block/mute lists | Confirmation, successful/failed follow, comment/reply/tagging, report form, populated moderation lists, recovery/unblock, blocked-profile presentation. | R09/R10 behavior is product/security design, not verified by an icon. |
| P2 G10 — permission/media/import flows | Contact pre-prompt 226; gallery 163–169; import blanks 120–124 | Photo picker/limited access, cancelled selection, upload progress/failure, matching/duplicates/import review, bad URL/file and import completion. | R10/R12 operational states must be specified independently. |
| P2 G11 — loading/errors/transitions | Several skeletons; blank results; share anomaly 03 | Offline/server timeout/retry, expired session, unavailable/deleted place, pagination failure, write failure, deep-link failure, skeleton timeout, saved-form feedback. | Cross-cutting R00 states are new Roam requirements, not Beli observations. |
| P2 G12 — subtle interactions | Scroll pairs and flow notes | Swipe-back, pull-to-refresh, sheet detents/drag dismissal, keyboard/CTA avoidance, VoiceOver, Dynamic Type, haptics, reduced motion, rotation. | Native accessibility/interaction design and validation remain necessary. |

B41–B44 now verify one onboarding path and comparison entry/Too tough in a two-item list. **Numeric score reveal, larger-list comparison rules and posting remain pending.** The user declined creating seven more temporary ratings just to cross Beli's ten-item score threshold.

## B. Product decisions we can make without more Beli captures

Captures can inspire UI, but cannot answer Roam policy or private-algorithm questions.

| Priority / decision | Draft recommendation or unresolved options | Owner / dependency |
|---|---|---|
| D01 — ranking semantics | User authorized Roam-owned comparison/tie/score rules constrained to Beli’s user-facing flow. B43 now establishes controls and two low-count outcomes; B42 establishes Beli's ten-per-category score gate. Exact candidate algorithm, Too tough/Skip/Undo semantics, score threshold for Roam, spacing and rounding remain TBD; Too tough is not proven to be a permanent tie. | Product/algorithm contract; G02 variants and G03 reveal remain unobserved. |
| D02 — category assignment/revisits | Propose one canonical category per experience, user confirms before ranking; revisit logs attach to existing user/place rating without duplicating ranking or city contribution. Cross-category reuse/change policy TBD. | Product; affects schema and migrations. |
| D03 — posting and social scope | Match Beli’s captured completion/publication flow; automatic activity vs explicit post action remains unknown. Earlier separate Save/Share and preview proposals are alternatives only. Keep private notes separate; likes/comments proposed v1. | G03/G04 establish sequence and commit/publication boundary; confirm any intentional Roam deviation. |
| D04 — All experiences and saved naming | Propose “Want to Go”; All defaults to recent activity or grouped categories, not global ordinal across incompatible category ranks. | Product. |
| D05 — city calculations | Confirmed balance by person/category and independent visitors; formula, priors, sparse-category treatment, thresholds, outliers, confidence labels, city assignment and rounding intentionally deferred. Choose a documented Roam formula later, with invariance tests. | Scoring design milestone, not capture-dependent. |
| D06 — technical platform | Native SwiftUI/MapKit/XcodeGen confirmed. Supabase recommendation only; minimum iOS 18 vs 26, auth methods, bundle/team IDs, hosting and link domain TBD. No friends-only backend rules. | Technical approval before implementation. |
| D07 — release scope | Preserve free custom lists/guides, sharing, shared wants, discovery and social. Proposed deferred: billing/subscriptions, restaurant booking/order integrations, referral gates, predictive recs, school/company boards, automatic photo extraction. Goals/streak/calendar/challenges/collaboration phase assignment TBD. | Product; use complete mapping, not arbitrary deletion. |
| D08 — guide/share rules | Public links and preview; copy/cancel native share; selected-subset snapshots vs live lists; owner edits, contributors, invite/member removal; guide-save auto-bookmark and bulk-save undo. | Product/security. |
| D09 — geography and globe | Ranked experiences count as visited, bookmarks do not (proposal). Canonical city/country assignment for remote places, localities, disputed boundaries, duplicates and missing metadata; polygon source/license and map feasibility TBD. | Product/technical spike. |
| D10 — social/privacy and deletion | Public follows/profiles confirmed. Specify private notes, block visibility, mute feed effects, reporting, moderation operation, deleted-account content and public-link behavior. | Product/backend authorization. |
| D11 — discovery data | Roam trending window, unique-user contribution, cold start, followed-score formula and minimum data; source for photos/hours/prices/tags. MapKit usage does not promise every metadata field. | Product/data feasibility. |
| D12 — media and imports | Photo count/size/compression limits, captions, upload retries, storage policy; paste-first import with explicit MapKit matching and partial-success report. | Product/technical. |

## C. Known evidence cautions

- Live counts/timestamps vary. Do not turn the reference account’s specific names, email, phone number or photos into fixtures.
- Screenshot names/descriptions are indexing aids. Visual corrections are recorded in inventory (price levels, share overlay, Earlier label, unselected Order ambiguity).
- Personal Been suggestions are not ranked personal content. Member profiles are not proof of current-account write controls.
- Public average lock, personal-rank lock and guide lock have different Beli triggers; do not collapse them into a generic loading state.
- Calendar/map/stat locks prove only the blocked presentation. Flat Beli map does not verify Roam’s globe feasibility.
- FAQ question text does not establish its answer. Other FAQ answers intentionally excluded; repeated list contents do not require exhaustive capture.

## D. Reconciliation and finalization gate

1. Keep initial filenames/review dispositions intact. When capture ends, enumerate new files and changed `flows.md` notes; do not overwrite or rename originals. Snapshot hashes for this review are in `docs/beli-reference-snapshot.json`.
2. Visually inspect every new distinct screen/state; select top/middle/bottom for repeated rows and explicitly record sampled files. For user videos, extract review frames outside `reference/beli/` unless separately authorized, retaining provenance/time offsets.
3. Add new B IDs or update existing entries with exact filenames; resolve observed-vs-inferred conflicts without erasing uncertainty. Distinguish direct app capture from external walkthrough material.
4. Reconcile map rows, R requirements and milestone criteria together. Preserve confirmed decisions when Beli differs. Record accepted deferrals and changed proposals.
5. Resolve P0 product questions. Missing behavior may become an explicit Roam design decision, but must not be relabeled “verified Beli.” Exact city formula can remain deferred to the dedicated scoring-design gate; it must be approved before numerical scoring ships.
6. Only then label the specification ready for implementation. This draft does not start or authorize a build. No background monitor or other-chat message has been created.

## Addendum reconciliation (302–322)

B37–B40 close the missing basic leaderboard, edit-profile, profile native-share, unlock-hub and management-empty layouts. They did not resolve onboarding or comparisons; the later B41–B44 local session now covers one path of each. Numeric score reveal and public posting remain unverified. Profile username warning demonstrates Beli link coupling; Roam stable-ID links remain a deliberate proposal. Other files arriving after 322 remain pending the final reconciliation gate.

## Original-folder recheck and later local capture — 2026-10-13

At the time of this check, `reference/beli/` held the original 322 PNGs; the 53 new-account captures were added there later as `nc001`–`nc053`. `flows.md` matches its last reviewed addendum hash. Original 172, 151 and 162 establish initial rating entry, separate place-level note/photo actions and comment submission respectively. The later [new-account captures](beli-live-capture-addendum.md) (now `reference/beli/nc*`) establish one onboarding path and low-count comparisons. G02 remains open for variants and larger lists; G03 numeric reveal and G04 posting remain open. No unsupported Save/Share fork or preview screen is required.

# Beli new-account capture addendum — 2026-10-13

This is a **direct, visually reviewed iPhone Mirroring session**, saved in [`reference/beli/`](../reference/beli/) as `nc001`–`nc053` (moved there 2026-10-13 from `docs/captures/`), alongside the original 01–322 set. Screenshots are sequential samples, not continuous video. They contain private signup/contact information and should not be published. The user entered the new password on the phone; no password screenshot or password value was captured. The test account used no profile photo. The three temporary restaurant ratings were deleted, and the final Following count was verified at zero.

## B41 — New-account onboarding and first-use education

**Observed sequence:** [welcome](../reference/beli/nc001-welcome-track.png) → [phone](../reference/beli/nc002-signup-phone-empty.png) → inviter acknowledgement → [email](../reference/beli/nc006-onboarding-after-get-started.png) → [password requirements](../reference/beli/nc008-signup-after-email.png) → name → [username](../reference/beli/nc010-signup-username.png) → [optional photo](../reference/beli/nc011-signup-profile-photo-skip.png) → [default city](../reference/beli/nc012-signup-default-city.png) → [location explanation and skip warning](../reference/beli/nc015-signup-location-skip-confirm.png) → [optional import](../reference/beli/nc016-signup-import-lists.png) → [contacts explanation and skip prompt](../reference/beli/nc022-signup-contacts-skip-confirm.png) → [suggested follows](../reference/beli/nc023-signup-suggested-follows.png) → [four bonus invites and give-up warning](../reference/beli/nc025-signup-invite-skip-confirm.png) → [notifications explanation and skip warning](../reference/beli/nc027-signup-notifications-skip-confirm.png) → [optional Gmail reservation sync](../reference/beli/nc028-signup-sync-reservations.png) → [Been-list teaching card](../reference/beli/nc029-first-run-been-list-prompt.png) → [starter list](../reference/beli/nc030-first-run-starter-list.png).

**Layout and controls:** Setup uses one large serif question/illustration per screen, simple full-width primary CTA, back where available, and optional Not now/Skip. Phone and email have disabled/enabled Continue states. Username shows a validity mark and says it can change later. Profile photo's Continue is disabled without an image but Not now advances. City choices are a vertical list; selection gains a check and enables Continue. Import offers Google Maps public-list URL, paste with city plus one place per line, and Foursquare/Mapstr export instructions. This session opened all four import branches but submitted no list or file. The location, contacts and notification skips each triggered an explanatory confirmation. The contacts warning displayed a number of alleged existing friends; its source was not verified. Suggested follows showed preselected people; after onboarding, three had become followed despite an attempted continue-without-adding action. They were manually unfollowed. The inviter follow was also later removed at the user's request. The bonus-invite warning said the bonus would expire if skipped; the user chose to give it up. No invitation was sent.

**First-use transition:** Skipping reservation sync landed in Your Lists → Been behind a modal introducing the ranked list. “Let's rank!” dismissed the modal into a starter recommendation list with plus (rank), bookmark (Want to Try) and X (dismiss suggestion) controls. A one-time tip explained the plus. These are observed entry states, not proof of how future sessions launch. The full city catalogue, alternate signup paths, permission-granted screens, successful imports and list matching are still unknown.

## B42 — First rating and enrichment

From a starter-list plus, a modal sheet identified the restaurant and list category, then asked **“How was it?”** with liked/fine/disliked choices ([entry](../reference/beli/nc031-rating-first-sentiment.png)). Selecting liked revealed optional rows for companions, labels/guides, notes, favorite dishes, photos, visit date and a locked Stealth mode toggle, with **Okay** at the bottom ([details](../reference/beli/nc032-rating-first-visit-details.png)). The category selector remained visible above sentiment. Notes, companion tags, guide labels and date opened separate sheets ([notes](../reference/beli/nc033-rating-notes-entry.png), [people](../reference/beli/nc034-rating-tag-friends.png), [labels](../reference/beli/nc035-rating-guides-labels.png), [calendar](../reference/beli/nc036-rating-visit-date.png)); each could be cancelled. No notes, companions, labels or photos were added. The date picker visibly selected the current date by default, but cancellation left whether a date was committed unknown.

After **Okay**, the first restaurant appeared at #1 with no comparison. A celebration card said that after ranking the first **10 spots within a category**, each gets an automatic score out of 10 based on list position ([result](../reference/beli/nc037-rating-first-result-list.png)). This is Beli's product copy, not a verified private formula. The list showed a locked numeric-score icon before ten ratings.

## B43 — Subsequent comparison and ranking

The second liked rating again presented visit details **before** comparisons ([second details](../reference/beli/nc039-rating-second-visit-details.png)). **Okay** opened **“Which do you prefer?”** with equal-sized new/existing restaurant cards, an OR divider, and **Undo / Too tough / Skip** along the bottom ([comparison](../reference/beli/nc040-rating-comparison-second.png)). Choosing **Too tough** ended the only comparison and placed the new item at #2 ([result](../reference/beli/nc041-rating-too-tough-result.png)). This single outcome does not establish that Too tough means equality or always places below.

The third liked rating repeated the same structure ([details](../reference/beli/nc043-rating-third-visit-details.png), [comparison](../reference/beli/nc044-rating-third-comparison-one.png)). Preferring the new restaurant over the shown prior restaurant ended comparison and put it at #1. The other two shifted down; all three still displayed locked numeric scores. The number and choice of comparison candidates in larger lists, Undo/Skip effects, sentiment differences, ties and score generation remain unobserved.

## B44 — Own rated detail, feed and cleanup

With three ratings, the own profile showed Been 3 and locked Rank/Recs ([profile](../reference/beli/nc046-own-profile-three-ratings.png)). A rated place showed **Rank again**, a checked ranked state, and **Your Beli Rating** with its ordinal but locked numeric score ([detail](../reference/beli/nc049-own-rated-detail.png)). Its overflow exposed **Delete your rating** ([menu](../reference/beli/nc050-own-rated-detail-delete-option.png)); confirmation said removal from Been **would not delete notes or photos** ([confirmation](../reference/beli/nc051-rating-delete-confirm.png)). The feed remained in its follow-friends empty state after three ratings ([feed](../reference/beli/nc048-feed-after-three-ratings-empty.png)). That does not establish what followers saw or whether a rating with notes/photos would generate a post. The three ratings were removed one by one; the profile then showed Been 0 ([verified](../reference/beli/nc052-profile-after-test-rating-cleanup.png)). The remaining inviter follow was removed at the user's request, then a refreshed Following list showed 0 and its empty state ([verified](../reference/beli/nc053-profile-zero-following.png)). No independent public post or post composer appeared, so no separate post was deleted.

## Capture review ledger

Every file below was visually inspected during the live session. `T` means the screenshot was a transition/loading/partial-entry state; `V` means a settled distinct layout or state. A later settled screenshot takes precedence over transitional geometry when interpreting control placement. `009` shows name entry in progress; its partial text is not a product requirement.

| Screenshot | Review |
|---|---|
| [nc001-welcome-track.png](../reference/beli/nc001-welcome-track.png) | V |
| [nc002-signup-phone-empty.png](../reference/beli/nc002-signup-phone-empty.png) | V |
| [nc003-signup-phone-entered.png](../reference/beli/nc003-signup-phone-entered.png) | V |
| [nc004-signup-after-phone-submit.png](../reference/beli/nc004-signup-after-phone-submit.png) | T |
| [nc005-signup-phone-submit-result.png](../reference/beli/nc005-signup-phone-submit-result.png) | V |
| [nc006-onboarding-after-get-started.png](../reference/beli/nc006-onboarding-after-get-started.png) | V |
| [nc007-signup-email-entered.png](../reference/beli/nc007-signup-email-entered.png) | V |
| [nc008-signup-after-email.png](../reference/beli/nc008-signup-after-email.png) | V |
| [nc009-signup-name-in-progress.png](../reference/beli/nc009-signup-name-in-progress.png) | T |
| [nc010-signup-username.png](../reference/beli/nc010-signup-username.png) | V |
| [nc011-signup-profile-photo-skip.png](../reference/beli/nc011-signup-profile-photo-skip.png) | V |
| [nc012-signup-default-city.png](../reference/beli/nc012-signup-default-city.png) | V |
| [nc013-signup-default-city-selected.png](../reference/beli/nc013-signup-default-city-selected.png) | V |
| [nc014-signup-location-prompt.png](../reference/beli/nc014-signup-location-prompt.png) | V |
| [nc015-signup-location-skip-confirm.png](../reference/beli/nc015-signup-location-skip-confirm.png) | V |
| [nc016-signup-import-lists.png](../reference/beli/nc016-signup-import-lists.png) | V |
| [nc017-signup-import-paste.png](../reference/beli/nc017-signup-import-paste.png) | V |
| [nc018-signup-import-google-maps.png](../reference/beli/nc018-signup-import-google-maps.png) | V |
| [nc019-signup-import-foursquare.png](../reference/beli/nc019-signup-import-foursquare.png) | V |
| [nc020-signup-import-mapstr.png](../reference/beli/nc020-signup-import-mapstr.png) | V |
| [nc021-signup-contacts-prompt.png](../reference/beli/nc021-signup-contacts-prompt.png) | V |
| [nc022-signup-contacts-skip-confirm.png](../reference/beli/nc022-signup-contacts-skip-confirm.png) | V |
| [nc023-signup-suggested-follows.png](../reference/beli/nc023-signup-suggested-follows.png) | V |
| [nc024-signup-nominate-friends.png](../reference/beli/nc024-signup-nominate-friends.png) | V |
| [nc025-signup-invite-skip-confirm.png](../reference/beli/nc025-signup-invite-skip-confirm.png) | V |
| [nc026-signup-notifications-prompt.png](../reference/beli/nc026-signup-notifications-prompt.png) | V |
| [nc027-signup-notifications-skip-confirm.png](../reference/beli/nc027-signup-notifications-skip-confirm.png) | V |
| [nc028-signup-sync-reservations.png](../reference/beli/nc028-signup-sync-reservations.png) | V |
| [nc029-first-run-been-list-prompt.png](../reference/beli/nc029-first-run-been-list-prompt.png) | V |
| [nc030-first-run-starter-list.png](../reference/beli/nc030-first-run-starter-list.png) | V |
| [nc031-rating-first-sentiment.png](../reference/beli/nc031-rating-first-sentiment.png) | V |
| [nc032-rating-first-visit-details.png](../reference/beli/nc032-rating-first-visit-details.png) | V |
| [nc033-rating-notes-entry.png](../reference/beli/nc033-rating-notes-entry.png) | V |
| [nc034-rating-tag-friends.png](../reference/beli/nc034-rating-tag-friends.png) | V |
| [nc035-rating-guides-labels.png](../reference/beli/nc035-rating-guides-labels.png) | V |
| [nc036-rating-visit-date.png](../reference/beli/nc036-rating-visit-date.png) | V |
| [nc037-rating-first-result-list.png](../reference/beli/nc037-rating-first-result-list.png) | V |
| [nc038-rating-second-sentiment.png](../reference/beli/nc038-rating-second-sentiment.png) | V |
| [nc039-rating-second-visit-details.png](../reference/beli/nc039-rating-second-visit-details.png) | V |
| [nc040-rating-comparison-second.png](../reference/beli/nc040-rating-comparison-second.png) | V |
| [nc041-rating-too-tough-result.png](../reference/beli/nc041-rating-too-tough-result.png) | V |
| [nc042-rating-third-sentiment.png](../reference/beli/nc042-rating-third-sentiment.png) | V |
| [nc043-rating-third-visit-details.png](../reference/beli/nc043-rating-third-visit-details.png) | V |
| [nc044-rating-third-comparison-one.png](../reference/beli/nc044-rating-third-comparison-one.png) | V |
| [nc045-rating-third-result-list.png](../reference/beli/nc045-rating-third-result-list.png) | V |
| [nc046-own-profile-three-ratings.png](../reference/beli/nc046-own-profile-three-ratings.png) | V |
| [nc047-own-profile-following-after-onboarding.png](../reference/beli/nc047-own-profile-following-after-onboarding.png) | V |
| [nc048-feed-after-three-ratings-empty.png](../reference/beli/nc048-feed-after-three-ratings-empty.png) | V |
| [nc049-own-rated-detail.png](../reference/beli/nc049-own-rated-detail.png) | V |
| [nc050-own-rated-detail-delete-option.png](../reference/beli/nc050-own-rated-detail-delete-option.png) | V |
| [nc051-rating-delete-confirm.png](../reference/beli/nc051-rating-delete-confirm.png) | V |
| [nc052-profile-after-test-rating-cleanup.png](../reference/beli/nc052-profile-after-test-rating-cleanup.png) | V |
| [nc053-profile-zero-following.png](../reference/beli/nc053-profile-zero-following.png) | V |

# App Store review preparation

Prepared on `codex/app_store_review` for **Roam: Places & Memories**, bundle
`com.daniellarkin.roam`, App Store Connect app `6822982847`. This is a draft for
review, not a claim that version 1.0 is ready to submit. The November 9 build 6
is the latest valid build in the **internal** TestFlight group (checked through
App Store Connect on November 12); an internal build is not a public App
Review approval. The release option is currently automatic after approval;
change it to **Manually release this version** if Daniel wants a separate
decision before public launch.

## Live App Store Connect check — November 12, 2026

Version 1.0 is `PREPARE_FOR_SUBMISSION`. No build is selected for App Review,
and the English (Canada) localization has no screenshots, description, keywords,
or support URL. The app localization has no privacy policy URL or subtitle.
App Review details do not exist yet. An age-rating declaration record exists,
but its answers were not audited. The App Privacy questionnaire could not be
verified through this API check. The version's release option is currently
`AFTER_APPROVAL` (automatic). A marketing URL and privacy-choices URL are
optional; their absence alone is not a blocker.

## Filled in App Store Connect — November 12, 2026

Set through the API with `scripts/app-store-listing.mjs`, `scripts/app-store-screenshots.mjs`,
`scripts/app-store-age-rating.mjs` and `scripts/app-store-review-details.mjs` (none of them submit):
description, keywords, promotional text, subtitle, copyright, category Travel, support and
privacy policy URLs, release type **Manual**, five 6.9" iPhone screenshots (fixture data),
age rating answers (user content, comments, social feed; 13+ override to match the Terms), and
App Review contact (Daniel Larkin, +1 780 381 5182, dxxxx441@gmail.com). Still empty: review
demo account and notes, App Privacy questionnaire (web only), build selection.

## Blocking checks before submitting

| Item | Current evidence | Ready when |
|---|---|---|
| Real iPhone run | **Done (team-reported, November 12):** the team tested the TestFlight build on iPhones | Re-check only what changes in build 7: Settings › Safety/Support rows and links, and Apple account deletion once revocation is deployed |
| iOS 18 compatibility | **Accepted (team decision, November 12):** the team considers its TestFlight testing sufficient; no iOS 18 simulator run is recorded | Raise the minimum OS if an iOS 18 problem is reported |
| Hosted account deletion and media cleanup | Database queues jobs; hosted worker schedule is prepared in `.github/workflows/roam-maintenance.yml` | Add `ROAM_BETA_SERVICE_ROLE_KEY` as a GitHub Actions secret, merge/enable the workflow, run it manually, and verify a disposable account and orphaned photo are removed. Never test with a real member. |
| Sign in with Apple revocation | The dedicated key `CP8L433922` was created and downloaded on November 12 (see `docs/apple-deployment-setup.md`). The branch contains `delete-account` Edge code and a migration, but neither has been deployed or provider-verified; build 6 still uses the old path | Configure the hosted Apple secrets, deploy the function and migration, upload a new build, and complete a real-device deletion/revocation test |
| Email signup and recovery | Hosted SMTP and templates are deferred | Configure SMTP, apply the prepared templates, verify confirmation and recovery from non-team email addresses |
| Public policy and support | The app now links to them: Settings › Support/Terms email `ROAM_SUPPORT_EMAIL`, Settings › Privacy opens `ROAM_PRIVACY_POLICY_URL`. Release builds fail until both are set in `Config/Beta.xcconfig`. Both are set locally: support dxxxx441@gmail.com, policy https://larkindaniel.github.io/roam-site/privacy.html. The pages are published from the public `larkindaniel/roam-site` repo (copy of `site/`) via GitHub Pages | In App Store Connect, set Privacy Policy URL to https://larkindaniel.github.io/roam-site/privacy.html and Support URL to https://larkindaniel.github.io/roam-site/ . Keep `site/` and `roam-site` in sync when the text changes |
| User content safety | Members can report, block and mute; Settings › Safety again lists Blocked people, Muted people and Your reports (they were unreachable after the Settings trim); reports are stored for operator review | Daniel Larkin monitors the report queue, has a reachable contact channel, and documents content filtering and response actions |
| Content/data rights | Place photos can come from Google; app uses MapKit and Wikipedia imagery | Check provider terms and required attributions against the released UI and selected territories |

The hosted worker deliberately accepts only `https://xnjzuotytfzyppubjcfi.supabase.co`
when `ROAM_WORKER_ENV=hosted` and requires its service key from the process environment.
The key must never be put in the iOS app, repository, or workflow file. GitHub
scheduled workflows run only from the repository's default branch; this branch
does not activate the schedule on its own. Check workflow run history after merge.
Draft public wording is in `docs/app-store-public-copy.md`. It contains explicit
contact and publication fields because no public inbox or domain was supplied;
do not submit a placeholder URL to Apple.

## App Store Connect packet

- **Name:** Roam: Places & Memories (existing app record).
- **Version:** 1.0. Build 7 is reserved in `project.yml` for the next binary; verify it is unused immediately before upload.
- **Draft subtitle:** Keep track of where you go.
- **Draft description:** "Save places you want to visit, plan trips by city, and keep a record of places you have been. Add notes and photos to your visits, rank your favourites, and see what friends share with you. Choose who can see each visit."
- **Category:** select after checking the current product page; likely Travel.
- **Screenshots:** capture the shipping build with fictional, rights-cleared content. At least one current-size iPhone screenshot is required; provide a useful sequence showing My Places, a city, a visit and the Friends tab. Do not use Beli reference images or internal fixture screenshots with misleading content.
- **App privacy:** complete the questionnaire from the inventory below and publish a public policy URL. A bundled `.xcprivacy` file does not fill the App Store privacy questionnaire.
- **Age rating:** answer the current questionnaire with user-generated posts/photos and social features in mind. Do not guess a rating.
- **Review account:** provide a stable, preverified email/password account with sample content and working backend access; do not send a fixture account pointing to local Docker. Explain Apple sign-in and the audience controls in review notes.
- **Review notes:** explain that Roam is a social travel log, uses Supabase for account/data storage, MapKit for maps/search, and Google Places/Wikipedia for some place imagery. Include tested device/OS versions, any regional differences, and a support contact.
- **Other Connect fields:** support URL, description/keywords, copyright, content rights, country availability, export compliance, and the chosen manual release option. Complete any agreement or regional declaration that App Store Connect specifically requests.

### Data inventory for App Privacy answers

Roam **does collect data** in Apple's terminology because its hosted backend
stores information tied to members. The owner should verify the precise App
Store Connect categories and purposes against the shipping build and provider
contracts before publishing the label.

| Data | Evidence and use |
|---|---|
| Email address and Apple sign-in identity | Supabase Auth account, login, confirmation and recovery |
| User ID, handle, display name, bio, avatar and home city | Account and member profile |
| Visits, place/city history, ratings, notes, photos, saved places, trip plans and taste answers | Core travel log and planning features; each visit has an audience setting |
| Friends, trip membership, companions, direct shares, likes, comments, posts and notifications | Social features |
| Reports, blocks and mutes | Safety and moderation; reports retain an anonymized record after account deletion |
| App settings | Units, haptics and in-app notification preferences |
| Device location | Requested for nearby search/sorting. Check actual transmission to MapKit and any server endpoint before answering the precise-location question. The app works without permission. |
| Third-party content requests | MapKit, Google Places server-side, and Wikipedia imagery; confirm any IP/logging or image caching disclosures with their current terms |
| Optional AI prompt handoff | The app builds a prompt from taste answers and liked places locally. The member can edit and copy it, then open ChatGPT or Claude. The prompt is not sent to either service until the member chooses to paste it there. |

The code search found no ad SDK or analytics integration. That does **not** make
the answer to Apple's "Do you collect data?" question "No." Do not choose "No"
while these account and user-content records are stored in Supabase.

## Submission sequence

1. Finish the blocking checks and upload a signed build containing the fixes.
2. Fill the app version and App Privacy fields; upload truthful screenshots and provide a working review account.
3. Select the build, choose **Manually release this version**, then **Add for Review** and **Submit for Review**.
4. Respond to App Review messages. After acceptance, verify the hosted services again before manually releasing the version.

If the intended next step is **external TestFlight** instead, create an external
testing group, provide beta description/feedback/review information, add a build,
and submit that build to TestFlight App Review. This does not submit the app for
public App Store distribution.

Apple references: [submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app),
[complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/),
[app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/),
[screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications),
[age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating),
[manual release](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option),
[external TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

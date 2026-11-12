# App Store review preparation

Prepared on `codex/app_store_review` for **Roam: Places & Memories**, bundle
`com.daniellarkin.roam`, App Store Connect app `6822982847`. This is a draft for
review, not a claim that version 1.0 is ready to submit. The November 6 build 5
is in the **internal** TestFlight group; an internal build is not a public App
Review approval. Keep release set to **Manually release this version** so an
approval does not publish the app automatically.

## Blocking checks before submitting

| Item | Current evidence | Ready when |
|---|---|---|
| Real iPhone run | Build 5 processed as valid; no recorded phone walkthrough | Apple sign-in, return sign-in, photo upload, logging, friends, reporting, deletion and recovery pass on a device |
| iOS 18 compatibility | Deployment target is 18.0; local UI runs were on iOS 26.2 | Run core journeys on an iOS 18 simulator or device, or raise the minimum OS honestly |
| Hosted account deletion and media cleanup | Database queues jobs; hosted worker schedule is prepared in `.github/workflows/roam-maintenance.yml` | Add `ROAM_BETA_SERVICE_ROLE_KEY` as a GitHub Actions secret, merge/enable the workflow, run it manually, and verify a disposable account and orphaned photo are removed. Never test with a real member. |
| Sign in with Apple revocation | The branch contains `delete-account` Edge code and a migration, but neither has been deployed or provider-verified; build 5 still uses the old path | Create a separate Sign in with Apple key, deploy the function and migration, upload a new build, and complete a real-device deletion/revocation test |
| Email signup and recovery | Hosted SMTP and templates are deferred | Configure SMTP, apply the prepared templates, verify confirmation and recovery from non-team email addresses |
| Public policy and support | In-app Help text has no public URL or contact destination | Publish accurate privacy policy, terms and support page; add privacy/support URLs to App Store Connect and links in the app |
| User content safety | Members can report and block; reports are stored for operator review | Daniel Larkin monitors the report queue, has a reachable contact channel, and documents content filtering and response actions |
| Content/data rights | Place photos can come from Google; app uses MapKit and Wikipedia imagery | Check provider terms and required attributions against the released UI and selected territories |

The hosted worker deliberately accepts only `https://xnjzuotytfzyppubjcfi.supabase.co`
when `ROAM_WORKER_ENV=hosted` and requires its service key from the process environment.
The key must never be put in the iOS app, repository, or workflow file. GitHub
scheduled workflows run only from the repository's default branch; this branch
does not activate the schedule on its own. Check workflow run history after merge.

## App Store Connect packet

- **Name:** Roam: Places & Memories (existing app record).
- **Version:** 1.0. Choose a new build number for any binary changed after build 5.
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
| Visits, place/city history, ratings, notes, photos, saved places and trip plans | Core travel log and sharing features; each visit has an audience setting |
| Friends, likes, comments, posts and notifications | Social features |
| Reports, blocks and mutes | Safety and moderation; reports retain an anonymized record after account deletion |
| App settings | Units, haptics and in-app notification preferences |
| Device location | Requested for nearby search/sorting. Check actual transmission to MapKit and any server endpoint before answering the precise-location question. The app works without permission. |
| Third-party content requests | MapKit, Google Places server-side, and Wikipedia imagery; confirm any IP/logging or image caching disclosures with their current terms |

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

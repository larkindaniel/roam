// Create or update the App Review contact details for Roam's editable version. Never submits for review.
// The demo account comes from ignored .env.review (scripts/create-review-account.py).
import { readFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const m = `${enc({ alg: 'ES256', kid: process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA', typ: 'JWT' })}.${enc({ iss: process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee', iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
const key = createPrivateKey(await readFile(process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8'));
const jwt = `${m}.${sign('sha256', Buffer.from(m), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
async function api(route, method = 'GET', body) {
  const r = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, { method,
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); const j = t ? JSON.parse(t) : {};
  if (!r.ok) throw new Error(`Apple API ${method} ${route} ${r.status}: ${JSON.stringify(j.errors)}`);
  return j;
}

const contact = {
  contactFirstName: 'Daniel',
  contactLastName: 'Larkin',
  contactPhone: '+1 780 381 5182',
  contactEmail: 'dxxxx441@gmail.com',
};

const review = existsSync('.env.review') ? Object.fromEntries(readFileSync('.env.review', 'utf8').split('\n')
  .filter(l => l.includes('=') && !l.startsWith('#')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])) : {};
if (review.ROAM_REVIEW_EMAIL && review.ROAM_REVIEW_PASSWORD) {
  Object.assign(contact, { demoAccountRequired: true, demoAccountName: review.ROAM_REVIEW_EMAIL, demoAccountPassword: review.ROAM_REVIEW_PASSWORD });
}
contact.notes = `Roam is a social travel log: people log places they've visited, rank them, plan trips, and share visits with friends.

SIGNING IN
Tap "Continue with email" and sign in with the demo account above (it already has a profile). Sign in with Apple also works with any Apple Account.

THINGS TO TRY
- Discover tab: search for any place or city (e.g. "Eiffel Tower"), open it, and tap Log to record a visit with a note, photos and an audience (Only me / Friends / Everyone). Logging asks you to compare the place with your others to rank it.
- My Places: your saved and visited places, trips, and the globe of places you've been.
- Friends: the feed of friends' visits. It is empty for a new account until you add friends (search people from the add-friend button).

USER-GENERATED CONTENT AND SAFETY
- Report: every post, comment, photo, place and profile has Report. Reports are reviewed by the developer, who acts within 24 hours.
- Block and mute: on any profile. Settings > Safety lists blocked and muted people (undo there) and the status of your reports.
- The Terms of Use (Settings > Terms of use, and https://larkindaniel.github.io/roam-site/terms.html) prohibit objectionable content and abusive users.
- Contact: Settings > Support emails ${contact.contactEmail}.

ACCOUNT DELETION
Settings > Delete account. It hides the profile immediately and deletes all data; Sign in with Apple accounts re-authenticate with Apple so the app can revoke its Apple token.

OTHER
- Location permission is optional and used only to search/sort near you.
- Maps and place search use Apple MapKit; some place photos come from Google Places (via our server) and Wikipedia.
- The app has no ads, purchases or tracking.`;

const [version] = (await api(`/apps/${appID}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data;
const existing = await api(`/appStoreVersions/${version.id}/appStoreReviewDetail`).catch(() => ({ data: null }));
let detail;
if (existing.data) {
  detail = (await api(`/appStoreReviewDetails/${existing.data.id}`, 'PATCH', { data: { type: 'appStoreReviewDetails', id: existing.data.id, attributes: contact } })).data;
} else {
  detail = (await api('/appStoreReviewDetails', 'POST', { data: { type: 'appStoreReviewDetails', attributes: contact,
    relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } })).data;
}
const { demoAccountPassword, notes, ...shown } = detail.attributes;
console.log(JSON.stringify({ ...shown, demoAccountPassword: demoAccountPassword ? '(set)' : null, notes: notes ? `${notes.length} chars` : null }, null, 1));

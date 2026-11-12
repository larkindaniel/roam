// Create or update the App Review contact details for Roam's editable version. Never submits for review.
// The demo account and notes are added once the review account exists.
import { readFile } from 'node:fs/promises';
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

const [version] = (await api(`/apps/${appID}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data;
const existing = await api(`/appStoreVersions/${version.id}/appStoreReviewDetail`).catch(() => ({ data: null }));
let detail;
if (existing.data) {
  detail = (await api(`/appStoreReviewDetails/${existing.data.id}`, 'PATCH', { data: { type: 'appStoreReviewDetails', id: existing.data.id, attributes: contact } })).data;
} else {
  detail = (await api('/appStoreReviewDetails', 'POST', { data: { type: 'appStoreReviewDetails', attributes: contact,
    relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } })).data;
}
const { demoAccountPassword, ...shown } = detail.attributes;
console.log(JSON.stringify(shown, null, 1));

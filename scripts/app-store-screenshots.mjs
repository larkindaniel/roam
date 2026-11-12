// Upload Roam's 6.9-inch iPhone screenshots to the editable App Store version, replacing that set.
// Usage: node scripts/app-store-screenshots.mjs <png> [<png> ...]   (in display order)
import { readFile, stat } from 'node:fs/promises';
import { basename } from 'node:path';
import { createHash, createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const keyID = process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA';
const issuer = process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee';
const keyPath = process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8';
const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const message = `${enc({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${enc({ iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })}`;
const key = createPrivateKey(await readFile(keyPath));
const jwt = `${message}.${sign('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;

async function api(route, method = 'GET', body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, {
    method, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const result = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`Apple API ${method} ${route} ${response.status}: ${JSON.stringify(result.errors)}`);
  return result;
}

const files = process.argv.slice(2);
if (!files.length) throw new Error('Pass the screenshot PNGs in display order.');
const displayType = 'APP_IPHONE_67'; // Apple's 6.7"/6.9" slot; accepts 1320x2868.

const versions = (await api(`/apps/${appID}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data;
if (versions.length !== 1) throw new Error('Expected one version in Prepare for Submission.');
const [loc] = (await api(`/appStoreVersions/${versions[0].id}/appStoreVersionLocalizations`)).data;
const sets = (await api(`/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`)).data;
let set = sets.find(s => s.attributes.screenshotDisplayType === displayType);
if (set) {
  for (const old of (await api(`/appScreenshotSets/${set.id}/appScreenshots`)).data) await api(`/appScreenshots/${old.id}`, 'DELETE');
} else {
  set = (await api('/appScreenshotSets', 'POST', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: displayType },
    relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } })).data;
}
for (const file of files) {
  const bytes = await readFile(file);
  const reserved = (await api('/appScreenshots', 'POST', { data: { type: 'appScreenshots',
    attributes: { fileName: basename(file), fileSize: (await stat(file)).size },
    relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } } } })).data;
  for (const op of reserved.attributes.uploadOperations) {
    const headers = Object.fromEntries(op.requestHeaders.map(h => [h.name, h.value]));
    const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`Upload part failed ${res.status}`);
  }
  await api(`/appScreenshots/${reserved.id}`, 'PATCH', { data: { type: 'appScreenshots', id: reserved.id,
    attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') } } });
  console.log(`uploaded ${basename(file)}`);
}
await new Promise(r => setTimeout(r, 8000));
const result = (await api(`/appScreenshotSets/${set.id}/appScreenshots`)).data;
console.log(result.map(s => `${s.attributes.fileName}: ${s.attributes.assetDeliveryState?.state}`).join('\n'));

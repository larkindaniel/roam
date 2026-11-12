// Wait for a processed build, then select it for the editable App Store version and add it to
// Roam Internal on TestFlight. Never submits for review. Usage: node scripts/app-store-select-build.mjs 7
import { readFile } from 'node:fs/promises';
import { createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const number = process.argv[2];
if (!number) throw new Error('Pass the build number.');
const keyPem = await readFile(process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8');
function token() {
  const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const m = `${enc({ alg: 'ES256', kid: process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA', typ: 'JWT' })}.${enc({ iss: process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee', iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
  return `${m}.${sign('sha256', Buffer.from(m), { key: createPrivateKey(keyPem), dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
}
async function api(route, method = 'GET', body) {
  const r = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, { method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); const j = t ? JSON.parse(t) : {};
  if (!r.ok) throw new Error(`Apple API ${method} ${route} ${r.status}: ${JSON.stringify(j.errors)}`);
  return j;
}

let build;
for (let i = 0; i < 60; i++) {
  build = (await api(`/builds?filter[app]=${appID}&filter[version]=${number}&filter[preReleaseVersion.version]=1.0`)).data[0];
  const state = build?.attributes.processingState ?? 'NOT_YET_LISTED';
  console.log(`${new Date().toISOString()} build ${number}: ${state}`);
  if (state === 'VALID') break;
  if (['FAILED', 'INVALID'].includes(state)) throw new Error(`Build ${number} is ${state}.`);
  await new Promise(r => setTimeout(r, 60000));
}
if (build?.attributes.processingState !== 'VALID') throw new Error('Timed out waiting for processing.');

const [version] = (await api(`/apps/${appID}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION`)).data;
await api(`/appStoreVersions/${version.id}/relationships/build`, 'PATCH', { data: { type: 'builds', id: build.id } });
console.log(`Selected build ${number} for version ${version.attributes.versionString}.`);
const group = (await api(`/apps/${appID}/betaGroups`)).data.find(g => g.attributes.name === 'Roam Internal' && g.attributes.isInternalGroup);
if (group) {
  await api(`/betaGroups/${group.id}/relationships/builds`, 'POST', { data: [{ type: 'builds', id: build.id }] });
  console.log('Added to Roam Internal on TestFlight.');
}

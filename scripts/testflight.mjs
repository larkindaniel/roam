// Manage only Roam's internal TestFlight build group after deployment authorization.
import { readFile } from 'node:fs/promises';
import { createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const keyID = process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA';
const issuer = process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee';
const keyPath = process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8';
const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const message = `${enc({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${enc({ iss: issuer, iat: now, exp: now + 300, aud: 'appstoreconnect-v1' })}`;
const key = createPrivateKey(await readFile(keyPath));
const jwt = `${message}.${sign('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;

async function api(route, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const result = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`Apple API ${response.status}: ${JSON.stringify(result.errors)}`);
  return result;
}

const action = process.argv[2] ?? 'status';
if (!['status', 'create-internal', 'add-build'].includes(action)) throw new Error('Use status, create-internal, or add-build <build-id>.');
let groups = (await api(`/apps/${appID}/betaGroups`)).data;
if (action === 'create-internal' && !groups.some(g => g.attributes.name === 'Roam Internal' && g.attributes.isInternalGroup)) {
  const result = await api('/betaGroups', { data: {
    type: 'betaGroups', attributes: { name: 'Roam Internal', isInternalGroup: true },
    relationships: { app: { data: { type: 'apps', id: appID } } },
  } });
  groups.push(result.data);
}
const builds = (await api(`/builds?filter[app]=${appID}&limit=100`)).data;
if (action === 'add-build') {
  const build = builds.find(b => b.id === process.argv[3]);
  const group = groups.find(g => g.attributes.name === 'Roam Internal' && g.attributes.isInternalGroup);
  if (!build || !group || build.attributes.processingState !== 'VALID') throw new Error('A processed Roam build and internal group are required.');
  await api(`/betaGroups/${group.id}/relationships/builds`, { data: [{ type: 'builds', id: build.id }] });
  console.log('Added build to Roam Internal.');
}
console.log(JSON.stringify({
  groups: groups.map(g => ({ id: g.id, name: g.attributes.name, internal: g.attributes.isInternalGroup })),
  builds: builds.map(b => ({ id: b.id, version: b.attributes.version, state: b.attributes.processingState, uploaded: b.attributes.uploadedDate })),
}, null, 2));

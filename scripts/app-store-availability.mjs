// Make Roam available in every App Store territory except mainland China (which needs an ICP filing),
// and declare third-party content (Google Places and Wikipedia imagery). Never submits for review.
import { readFile } from 'node:fs/promises';
import { createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const excluded = new Set(['CHN']);
const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const m = `${enc({ alg: 'ES256', kid: process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA', typ: 'JWT' })}.${enc({ iss: process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee', iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
const key = createPrivateKey(await readFile(process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8'));
const jwt = `${m}.${sign('sha256', Buffer.from(m), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
async function api(route, method = 'GET', body, base = 'v1') {
  const r = await fetch(`https://api.appstoreconnect.apple.com/${base}${route}`, { method,
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); const j = t ? JSON.parse(t) : {};
  if (!r.ok) throw new Error(`Apple API ${method} ${route} ${r.status}: ${JSON.stringify(j.errors)}`);
  return j;
}

await api(`/apps/${appID}`, 'PATCH', { data: { type: 'apps', id: appID, attributes: { contentRightsDeclaration: 'USES_THIRD_PARTY_CONTENT' } } });
console.log('Content rights: uses third-party content.');

// Apple needs every territory listed; excluded ones are marked unavailable.
const all = (await api('/territories?limit=200')).data.map(t => t.id);
const territories = all.filter(id => !excluded.has(id));
const included = all.map((id, i) => ({ type: 'territoryAvailabilities', id: `\${t${i}}`, attributes: { available: !excluded.has(id) },
  relationships: { territory: { data: { type: 'territories', id } } } }));
const result = await api('/appAvailabilities', 'POST', { data: { type: 'appAvailabilities',
  attributes: { availableInNewTerritories: true },
  relationships: { app: { data: { type: 'apps', id: appID } },
    territoryAvailabilities: { data: included.map(t => ({ type: t.type, id: t.id })) } } }, included }, 'v2');
console.log(`Available in ${territories.length} territories (excluding ${[...excluded].join(', ')}); availability ${result.data.id}.`);

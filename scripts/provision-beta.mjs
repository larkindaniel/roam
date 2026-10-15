// Create/reuse the app's App Store profile using an existing local distribution identity.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createPrivateKey, sign, X509Certificate } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const keyPath = process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8';
const keyID = process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA';
const issuer = process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee';
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${encode({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${encode({ iss: issuer, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
const privateKey = createPrivateKey(await readFile(keyPath));
const jwt = `${unsigned}.${sign('sha256', Buffer.from(unsigned), { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;

async function api(route, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com/v1${route}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const result = await response.json();
  if (!response.ok) throw new Error(`Apple API ${response.status}: ${JSON.stringify(result.errors?.map(e => ({ code: e.code, detail: e.detail })))}`);
  return result;
}

const bundle = (await api('/bundleIds?filter[identifier]=com.daniellarkin.roam')).data[0];
if (!bundle) throw new Error('Registered Roam bundle ID not found.');
const localIdentities = execFileSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' });
const certificates = (await api('/certificates?filter[certificateType]=DISTRIBUTION&limit=200')).data;
const certificate = certificates.find(cert => {
  const x509 = new X509Certificate(Buffer.from(cert.attributes.certificateContent, 'base64'));
  return localIdentities.includes(x509.fingerprint.replaceAll(':', ''))
    && new Date(cert.attributes.expirationDate) > new Date();
});
if (!certificate) throw new Error('No valid distribution certificate matches a private signing identity on this Mac.');
const profileName = 'Roam TestFlight';
let profile = (await api('/profiles?filter[name]=Roam%20TestFlight&include=certificates,bundleId&limit=200')).data.find(p =>
  p.attributes.profileState === 'ACTIVE' && p.attributes.profileType === 'IOS_APP_STORE'
  && p.relationships.bundleId.data.id === bundle.id
  && p.relationships.certificates.data.some(c => c.id === certificate.id));
if (!profile) {
  profile = (await api('/profiles', { data: {
    type: 'profiles', attributes: { name: profileName, profileType: 'IOS_APP_STORE' },
    relationships: {
      bundleId: { data: { type: 'bundleIds', id: bundle.id } },
      certificates: { data: [{ type: 'certificates', id: certificate.id }] },
    },
  } })).data;
}
const destination = resolve(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles');
await mkdir(destination, { recursive: true });
await writeFile(resolve(destination, `${profile.attributes.uuid}.mobileprovision`), Buffer.from(profile.attributes.profileContent, 'base64'), { mode: 0o600 });
const configPath = resolve(root, 'Config/Beta.xcconfig');
const config = (await readFile(configPath, 'utf8')).replace(/^ROAM_DISTRIBUTION_PROFILE_UUID\s*=.*\n?/gm, '');
await writeFile(configPath, `${config.trimEnd()}\nROAM_DISTRIBUTION_PROFILE_UUID = ${profile.attributes.uuid}\n`);
console.log(`Installed ${profileName}: ${profile.attributes.uuid}`);
console.log(`Profile expires: ${profile.attributes.expirationDate}`);

// Read or fill Roam's App Store listing text in App Store Connect. Never submits for review.
// Usage: node scripts/app-store-listing.mjs [status|apply]
import { readFile } from 'node:fs/promises';
import { createPrivateKey, sign } from 'node:crypto';

const appID = '6822982847';
const keyID = process.env.ROAM_ASC_KEY_ID ?? '2W7C5ZMNHA';
const issuer = process.env.ROAM_ASC_ISSUER_ID ?? '1b06d6de-7ee5-409f-9a2f-e21fbd621fee';
const keyPath = process.env.ROAM_ASC_KEY_PATH ?? '/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8';
const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const message = `${enc({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${enc({ iss: issuer, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' })}`;
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

const listing = {
  subtitle: 'Keep track of where you go',
  privacyPolicyUrl: 'https://larkindaniel.github.io/roam-site/privacy.html',
  supportUrl: 'https://larkindaniel.github.io/roam-site/',
  copyright: '2026 Daniel Larkin',
  keywords: 'travel,journal,places,map,trip,planner,ranking,friends,cities,countries,wishlist,memories,log',
  promotionalText: 'Rank the places you loved, plan trips by city, and see where your friends have been.',
  description: `Roam is your travel memory. Log the places you've been, rank your favourites, and plan where to go next, with friends.

LOG PLACES AND CITIES
Search any café, museum, hike or hotel and log a visit with the date, a note and photos. Log whole cities and countries too, and watch your globe fill in.

RANK WHAT YOU LOVED
Say whether you liked a place, then compare it with a few of your others. Roam turns your choices into a score from 0 to 10, separately for Food & Drink, Outdoors, Culture, Nightlife, Activities, Day Trips and Stays.

PLAN TRIPS
Save places you want to visit, group them by city, and build trips with dates. Plan with AI writes a prompt from your tastes that you can take to ChatGPT or Claude.

TRAVEL WITH FRIENDS
Add friends, see where they've been by country and city, send each other places, and like or comment on visits. Join each other's trips.

YOU CHOOSE WHO SEES WHAT
Every visit can be shared with everyone, friends only, or just you. Photos have their location data removed before upload. Report, block or mute anyone, and delete your account at any time in Settings.`,
};

const action = process.argv[2] ?? 'status';
if (!['status', 'apply'].includes(action)) throw new Error('Use status or apply.');

const versions = (await api(`/apps/${appID}/appStoreVersions?filter[platform]=IOS&limit=10`)).data;
const version = versions.find(v => ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'].includes(v.attributes.appStoreState));
if (!version) throw new Error(`No editable version: ${versions.map(v => `${v.attributes.versionString} ${v.attributes.appStoreState}`).join(', ')}`);
const versionLocs = (await api(`/appStoreVersions/${version.id}/appStoreVersionLocalizations`)).data;
const infos = (await api(`/apps/${appID}/appInfos`)).data;
const info = infos.find(i => i.attributes.appStoreState !== 'READY_FOR_SALE') ?? infos[0];
const infoLocs = (await api(`/appInfos/${info.id}/appInfoLocalizations`)).data;
const category = await api(`/appInfos/${info.id}/primaryCategory`).catch(() => ({ data: null }));

if (action === 'apply') {
  await api(`/appStoreVersions/${version.id}`, 'PATCH', { data: { type: 'appStoreVersions', id: version.id,
    attributes: { releaseType: 'MANUAL', copyright: listing.copyright } } });
  for (const loc of versionLocs) {
    await api(`/appStoreVersionLocalizations/${loc.id}`, 'PATCH', { data: { type: 'appStoreVersionLocalizations', id: loc.id,
      attributes: { description: listing.description, keywords: listing.keywords, supportUrl: listing.supportUrl, promotionalText: listing.promotionalText } } });
  }
  for (const loc of infoLocs) {
    await api(`/appInfoLocalizations/${loc.id}`, 'PATCH', { data: { type: 'appInfoLocalizations', id: loc.id,
      attributes: { subtitle: listing.subtitle, privacyPolicyUrl: listing.privacyPolicyUrl } } });
  }
  await api(`/appInfos/${info.id}`, 'PATCH', { data: { type: 'appInfos', id: info.id,
    relationships: { primaryCategory: { data: { type: 'appCategories', id: 'TRAVEL' } } } } });
  console.log('Listing updated. Nothing was submitted.');
}

const refreshed = action === 'apply' ? {
  version: (await api(`/appStoreVersions/${version.id}`)).data,
  versionLocs: (await api(`/appStoreVersions/${version.id}/appStoreVersionLocalizations`)).data,
  infoLocs: (await api(`/appInfos/${info.id}/appInfoLocalizations`)).data,
  category: (await api(`/appInfos/${info.id}/primaryCategory`)).data,
} : { version, versionLocs, infoLocs, category: category.data };
const short = s => (s == null ? null : s.length > 60 ? `${s.slice(0, 60)}… (${s.length} chars)` : s);
console.log(JSON.stringify({
  version: { id: refreshed.version.id, ...refreshed.version.attributes },
  category: refreshed.category?.id ?? null,
  versionLocalizations: refreshed.versionLocs.map(l => ({ locale: l.attributes.locale, description: short(l.attributes.description),
    keywords: l.attributes.keywords, supportUrl: l.attributes.supportUrl, promotionalText: short(l.attributes.promotionalText) })),
  appInfoLocalizations: refreshed.infoLocs.map(l => ({ locale: l.attributes.locale, name: l.attributes.name, subtitle: l.attributes.subtitle,
    privacyPolicyUrl: l.attributes.privacyPolicyUrl })),
}, null, 2));

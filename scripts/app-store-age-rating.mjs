// Answer Roam's age rating questionnaire in App Store Connect. Never submits for review.
// Roam: a travel log with member posts, comments and a friends feed; no mature content of its own.
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
  if (!r.ok) throw new Error(`Apple API ${method} ${route} ${r.status}: ${JSON.stringify(j.errors, null, 1)}`);
  return j;
}

const answers = {
  // Content Roam itself contains: none of these.
  alcoholTobaccoOrDrugUseOrReferences: 'NONE',
  gamblingSimulated: 'NONE',
  horrorOrFearThemes: 'NONE',
  matureOrSuggestiveThemes: 'NONE',
  medicalOrTreatmentInformation: 'NONE',
  profanityOrCrudeHumor: 'NONE',
  sexualContentGraphicAndNudity: 'NONE',
  sexualContentOrNudity: 'NONE',
  violenceCartoonOrFantasy: 'NONE',
  violenceRealistic: 'NONE',
  violenceRealisticProlongedGraphicOrSadistic: 'NONE',
  gunsOrOtherWeapons: 'NONE',
  contests: 'NONE',
  // Features.
  advertising: false,
  gambling: false,
  lootBox: false,
  healthOrWellnessTopics: false,
  parentalControls: false,
  ageAssurance: false,
  unrestrictedWebAccess: false,
  userGeneratedContent: true, // visits, notes, photos, comments
  messagingAndChat: true,     // comments between members
  socialMedia: true,          // friends feed and profiles
  // The Terms of Use require members to be 13 or older.
  ageRatingOverrideV2: 'THIRTEEN_PLUS',
};

const [info] = (await api(`/apps/${appID}/appInfos`)).data.filter(i => i.attributes.appStoreState === 'PREPARE_FOR_SUBMISSION');
const decl = (await api(`/appInfos/${info.id}/ageRatingDeclaration`)).data;
if (process.argv[2] === 'apply') {
  await api(`/ageRatingDeclarations/${decl.id}`, 'PATCH', { data: { type: 'ageRatingDeclarations', id: decl.id, attributes: answers } });
  console.log('Age rating answers saved.');
}
const after = (await api(`/apps/${appID}/appInfos`)).data.find(i => i.id === info.id);
console.log(JSON.stringify({ rating: after.attributes.appStoreAgeRating, declaration: (await api(`/appInfos/${info.id}/ageRatingDeclaration`)).data.attributes }, null, 1));

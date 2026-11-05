// Looks places up on Google Places (New) for their photo and star rating, and saves them on the place.
// The Google key stays here on the server. Places checked in the last week are skipped, so each place costs
// one search and one photo request about once a week, however often it is viewed.
// Sent { country, name } instead, it returns that country's Google photo, kept the same way; with a region too
// ({ country, region, name }), that state or province's.

const url = Deno.env.get("SUPABASE_URL")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const googleKey = Deno.env.get("GOOGLE_PLACES_KEY");
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/// A Google result further than this from our place is a different place with the same name...
const matchMeters = 750;
/// ...unless its name matches ours: parks, mountains and other big places have centres kilometres from our pin.
const sameNameMeters = 25_000;
const normalize = (text: string) => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
function sameName(ours: string, theirs: string | undefined) {
  if (!theirs) return false;
  const a = normalize(ours), b = normalize(theirs);
  return a === b || a.includes(b) || b.includes(a);
}

type Target = { experienceID: string; name: string; locality: string | null; latitude: number; longitude: number; fresh: boolean };
type Lookup = { googlePlaceID: string | null; rating: number | null; ratingCount: number | null; photoURL: string | null; photoCredit: string | null };

function metersBetween(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const r = 6_371_000, rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

async function rpc(name: string, body: unknown) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST", headers: { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`${name} failed: ${response.status}`);
  return response.status === 204 ? null : await response.json();
}

/// The best Google match for the place: by name and town first, then by name alone (the town can steer Google to
/// something else, like a viewpoint named after it).
async function find(target: Target) {
  for (const query of [[target.name, target.locality].filter(Boolean).join(", "), target.name]) {
    const place = await search(target, query);
    const distance = place?.location ? metersBetween(target, place.location) : Infinity;
    if (place && (distance <= matchMeters || (distance <= sameNameMeters && sameName(target.name, place.displayName?.text)))) return place;
    if (!target.locality) break;
  }
  return null;
}

async function search(target: Target, query: string) {
  const search = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json", "X-Goog-Api-Key": googleKey!,
      "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.rating,places.userRatingCount,places.photos",
    },
    body: JSON.stringify({
      textQuery: query,
      pageSize: 1,
      locationBias: { circle: { center: { latitude: target.latitude, longitude: target.longitude }, radius: 500 } },
    }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!search.ok) throw new Error(`Google search failed: ${search.status} ${await search.text()}`);
  return (await search.json()).places?.[0] ?? null;
}

async function lookUp(target: Target): Promise<Lookup> {
  const place = await find(target);
  if (!place) {
    return { googlePlaceID: null, rating: null, ratingCount: null, photoURL: null, photoCredit: null };
  }
  let photoURL: string | null = null, photoCredit: string | null = null;
  const photo = place.photos?.[0];
  if (photo?.name) {
    const media = await fetch(`https://places.googleapis.com/v1/${photo.name}/media?maxWidthPx=1200&skipHttpRedirect=true`, {
      headers: { "X-Goog-Api-Key": googleKey! }, signal: AbortSignal.timeout(15_000),
    });
    if (media.ok) {
      photoURL = (await media.json()).photoUri ?? null;
      photoCredit = photo.authorAttributions?.[0]?.displayName ?? null;
    }
  }
  return {
    googlePlaceID: place.id ?? null,
    rating: typeof place.rating === "number" ? Math.round(place.rating * 10) / 10 : null,
    ratingCount: typeof place.userRatingCount === "number" ? place.userRatingCount : null,
    photoURL, photoCredit: photoCredit ? `${photoCredit} via Google` : null,
  };
}

/// A country's (or a state's) photo: the first landscape-shaped one on its own Google entry.
async function areaPhoto(code: string, name: string, region: string | null) {
  const key = region ? `${code}|${region}` : code;
  const cached = region ? await rpc("region_photo", { p_key: key }) : await rpc("country_photo", { p_code: code });
  if (cached?.fresh) return { photoURL: cached.photoURL ?? null, photoCredit: cached.photoCredit ?? null };
  const search = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": googleKey!, "X-Goog-FieldMask": "places.types,places.photos" },
    body: JSON.stringify({ textQuery: name, pageSize: 1 }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!search.ok) throw new Error(`Google search failed: ${search.status} ${await search.text()}`);
  const place = (await search.json()).places?.[0];
  let photoURL: string | null = null, photoCredit: string | null = null;
  if (place?.types?.includes(region ? "administrative_area_level_1" : "country")) {
    const photos: { name?: string; widthPx?: number; heightPx?: number; authorAttributions?: { displayName?: string }[] }[] = place.photos ?? [];
    const photo = photos.find(p => (p.widthPx ?? 0) > (p.heightPx ?? 0)) ?? photos[0];
    if (photo?.name) {
      const media = await fetch(`https://places.googleapis.com/v1/${photo.name}/media?maxWidthPx=1600&skipHttpRedirect=true`, {
        headers: { "X-Goog-Api-Key": googleKey! }, signal: AbortSignal.timeout(15_000),
      });
      if (media.ok) {
        photoURL = (await media.json()).photoUri ?? null;
        const author = photo.authorAttributions?.[0]?.displayName;
        photoCredit = author ? `${author} via Google` : null;
      }
    }
  }
  if (region) await rpc("save_region_photo", { p_key: key, p_url: photoURL, p_credit: photoCredit });
  else await rpc("save_country_photo", { p_code: code, p_name: name, p_url: photoURL, p_credit: photoCredit });
  return { photoURL, photoCredit };
}

Deno.serve(async request => {
  if (request.method !== "POST") return json({ message: "Use POST." }, 405);
  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ message: "roam:not_signed_in" }, 401);
    const auth = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: authorization }, signal: AbortSignal.timeout(15_000) });
    if (!auth.ok) return json({ message: "roam:not_signed_in" }, 401);
    // Without a key there's nothing to look up; the app keeps showing visit photos and maps.
    if (!googleKey) return json({ updated: [], photoURL: null });

    let input;
    try { input = await request.json(); } catch { return json({ message: "roam:validation:Send experienceIDs." }, 400); }
    if (typeof input?.country === "string") {
      const code = input.country.toUpperCase();
      if (!/^[A-Z]{2}$/.test(code) || typeof input.name !== "string" || !input.name.trim()) {
        return json({ message: "roam:validation:Send a country code and name." }, 400);
      }
      const region = typeof input.region === "string" && input.region.trim() ? input.region.trim().slice(0, 80) : null;
      return json(await areaPhoto(code, input.name.trim(), region));
    }
    const ids: string[] = Array.isArray(input?.experienceIDs) ? input.experienceIDs.filter((id: unknown) => typeof id === "string" && uuid.test(id)) : [];
    if (ids.length === 0 || ids.length > 30) return json({ message: "roam:validation:Send 1 to 30 experienceIDs." }, 400);

    const targets: Target[] = await rpc("google_lookup_targets", { p_experience_ids: ids });
    const due = targets.filter(target => !target.fresh);
    const updated: string[] = [];
    await Promise.all(due.map(async target => {
      try {
        const found = await lookUp(target);
        await rpc("save_google_lookup", {
          p_experience_id: target.experienceID, p_google_place_id: found.googlePlaceID, p_rating: found.rating,
          p_rating_count: found.ratingCount, p_photo_url: found.photoURL, p_photo_credit: found.photoCredit,
        });
        if (found.googlePlaceID) updated.push(target.experienceID);
      } catch (error) {
        // One place failing doesn't stop the rest; it's tried again next time it's viewed.
        console.error(target.experienceID, error instanceof Error ? error.message : error);
      }
    }));
    return json({ updated });
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    return json({ message: "Google details are unavailable right now." }, 503);
  }
});

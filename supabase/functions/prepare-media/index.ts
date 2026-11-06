import { inspectJPEG } from "./inspector.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Transient failures are retryable with the same upload attempt; only inspection results are rejections.
const unavailable = () => json({ message: "Photo checking is unavailable right now. Retry the same upload." }, 503);

Deno.serve(async request => {
  if (request.method !== "POST") return json({ message: "Use POST." }, 405);
  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ message: "roam:not_signed_in" }, 401);
    const auth = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: authorization }, signal: AbortSignal.timeout(15_000) });
    if (auth.status === 401 || auth.status === 403) return json({ message: "roam:not_signed_in" }, 401);
    if (!auth.ok) return unavailable();
    const user = await auth.json();
    if (!uuid.test(user.id)) return json({ message: "roam:not_signed_in" }, 401);
    let input;
    try { input = await request.json(); } catch { return json({ message: "roam:validation:Use a valid upload request." }, 400); }
    if (!input || typeof input !== "object" || Object.keys(input).some(x => !["uploadAttemptID", "purpose", "sha256"].includes(x))
      || !uuid.test(input.uploadAttemptID) || !["visit", "avatar"].includes(input.purpose) || !/^[a-f0-9]{64}$/.test(input.sha256)) return json({ message: "roam:validation:Check the upload attempt." }, 400);
    const bucket = input.purpose === "avatar" ? "avatars" : "visit-media";
    const attempt = input.uploadAttemptID.toLowerCase();
    const path = `${user.id.toLowerCase()}/${attempt}.jpg`;
    // Caller-authenticated download prevents inspecting another member's private staging folder.
    const object = await fetch(`${url}/storage/v1/object/authenticated/${bucket}/${path}`, { headers: { apikey: anon, Authorization: authorization }, signal: AbortSignal.timeout(20_000) });
    if (object.status === 400 || object.status === 404) return json({ message: "roam:validation:The photo has not finished uploading." }, 400);
    if (object.status === 401 || object.status === 403) return json({ message: "roam:not_signed_in" }, 401);
    if (!object.ok) return unavailable();
    const etag = object.headers.get("etag");
    if (!etag) return unavailable();
    if (Number(object.headers.get("content-length")) > 3 * 1024 * 1024) return json({ message: "roam:validation:Photos must be 3 MB or smaller." }, 400);
    let inspection;
    try { inspection = await inspectJPEG(new Uint8Array(await object.arrayBuffer())); }
    catch (error) { return json({ message: `roam:validation:${error instanceof Error ? error.message : "The photo could not be inspected."}` }, 400); }
    if (inspection.sha256 !== input.sha256) return json({ message: "roam:operation_conflict", code: "23505" }, 409);
    const finalized = await fetch(`${url}/rest/v1/rpc/finalize_media_inspection`, {
      method: "POST", headers: { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(20_000),
      body: JSON.stringify({ p_actor: user.id, p_attempt: attempt, p_purpose: input.purpose, p_width: inspection.width,
        p_height: inspection.height, p_byte_size: inspection.byteSize, p_sha256: inspection.sha256, p_etag: etag })
    });
    if (finalized.status >= 500) return unavailable();
    return json(await finalized.json(), finalized.status);
  } catch {
    // Network, timeout and malformed upstream responses: nothing was rejected, so retry is safe.
    return unavailable();
  }
});

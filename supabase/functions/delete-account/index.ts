// A recently reauthenticated Apple member submits Apple's one-use authorization code.
// The code and exchanged tokens stay in this request only; no credential is logged or stored.
import { appleSubject, clientSecret, exchangeCode, revokeToken } from "./apple.mjs";

const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body),
  { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

async function rpc(name: string, body: unknown, bearer: string, key: string) {
  return await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST", headers: { apikey: key, Authorization: bearer, "Content-Type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15_000),
  });
}

Deno.serve(async request => {
  if (request.method !== "POST") return json({ message: "Use POST." }, 405);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ message: "Sign in again." }, 401);
  let code: unknown;
  try {
    const body = await request.json();
    if (!body || Object.keys(body).some(key => key !== "authorizationCode")) return json({ message: "Invalid request." }, 400);
    code = body.authorizationCode;
  } catch { return json({ message: "Invalid request." }, 400); }
  if (typeof code !== "string" || code.length < 8 || code.length > 4096) return json({ message: "Sign in with Apple again." }, 400);
  const teamID = Deno.env.get("APPLE_TEAM_ID"), keyID = Deno.env.get("APPLE_SIGN_IN_KEY_ID"), pem = Deno.env.get("APPLE_SIGN_IN_PRIVATE_KEY");
  if (!teamID || !keyID || !pem) return json({ message: "Apple account deletion is unavailable. Try again later." }, 503);
  try {
    const userResponse = await fetch(`${url}/auth/v1/user`,
      { headers: { apikey: anon, Authorization: authorization }, signal: AbortSignal.timeout(15_000) });
    if (!userResponse.ok) return json({ message: "Sign in again." }, 401);
    const user = await userResponse.json();
    const subjects = (user.identities ?? []).filter((identity: { provider?: string }) => identity.provider === "apple")
      .map((identity: { provider_id?: string; identity_data?: { sub?: string } }) => identity.identity_data?.sub ?? identity.provider_id);
    if (!user.id || subjects.length === 0) return json({ message: "This account has no Apple sign-in." }, 403);
    const secret = await clientSecret(teamID, keyID, pem);
    const tokens = await exchangeCode(code, secret);
    const subject = appleSubject(tokens.id_token);
    if (!subject || !subjects.includes(subject)) return json({ message: "The Apple account does not match. Sign in again." }, 403);

    // The caller's own JWT supplies the recent-sign-in proof and actor identity.
    const deletion = await rpc("request_account_deletion", {}, authorization, anon);
    if (!deletion.ok) return json({ message: "Could not start deletion. Sign in again and retry." }, deletion.status);
    const status = await deletion.json();
    let revocation: "completed" | "failed" = "failed";
    try { await revokeToken(tokens.refresh_token, secret); revocation = "completed"; } catch { /* Account deletion still proceeds. */ }
    const recorded = await rpc("set_account_deletion_apple_revocation",
      { p_user: user.id, p_state: revocation }, `Bearer ${service}`, service);
    if (!recorded.ok || await recorded.json() !== true) return json({ ...status, appleRevocation: "pending" }, 202);
    return json({ ...status, appleRevocation: revocation });
  } catch {
    // No Apple codes, tokens, private keys, or provider error bodies enter logs or responses.
    return json({ message: "Apple account deletion is unavailable. Try again." }, 503);
  }
});

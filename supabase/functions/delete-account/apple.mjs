const clientID = "com.daniellarkin.roam";
const appleURL = "https://appleid.apple.com";

function base64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function encoded(value) {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

export async function clientSecret(teamID, keyID, pem, now = Math.floor(Date.now() / 1000)) {
  if (!/^[A-Z0-9]{10}$/.test(teamID) || !/^[A-Z0-9]{10}$/.test(keyID)) throw new Error("Apple key configuration is invalid.");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${encoded({ alg: "ES256", kid: keyID })}.${encoded({ iss: teamID, iat: now, exp: now + 300,
    aud: appleURL, sub: clientID })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

async function postApple(route, fields, fetcher = fetch) {
  const response = await fetcher(`${appleURL}/auth/${route}`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields), signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`Apple ${route} returned ${response.status}.`);
  return response;
}

export async function exchangeCode(code, secret, fetcher = fetch) {
  const response = await postApple("token", { client_id: clientID, client_secret: secret,
    code, grant_type: "authorization_code" }, fetcher);
  const token = await response.json();
  if (typeof token.refresh_token !== "string" || typeof token.id_token !== "string") throw new Error("Apple returned incomplete tokens.");
  return token;
}

export async function revokeToken(token, secret, fetcher = fetch) {
  await postApple("revoke", { client_id: clientID, client_secret: secret,
    token, token_type_hint: "refresh_token" }, fetcher);
}

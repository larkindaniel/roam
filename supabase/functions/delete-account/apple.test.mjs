import assert from "node:assert/strict";
import { test } from "node:test";
import { clientSecret, exchangeCode, revokeToken } from "./apple.mjs";

function decode(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

test("client secret is a short-lived ES256 token for the native App ID", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${der.toString("base64")}\n-----END PRIVATE KEY-----`;
  const jwt = await clientSecret("H5V24G3F3D", "1234567890", pem, 1_800_000_000);
  const [header, payload, signature] = jwt.split(".");
  assert.deepEqual(decode(header), { alg: "ES256", kid: "1234567890" });
  assert.deepEqual(decode(payload), {
    iss: "H5V24G3F3D", iat: 1_800_000_000, exp: 1_800_000_300,
    aud: "https://appleid.apple.com", sub: "com.daniellarkin.roam",
  });
  assert.equal(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey,
    Buffer.from(signature, "base64url"), new TextEncoder().encode(`${header}.${payload}`)), true);
});

test("authorization code is exchanged, then only the refresh token is revoked", async () => {
  const requests = [];
  const fetcher = async (url, init) => {
    requests.push({ url, fields: Object.fromEntries(init.body) });
    return new Response(url.endsWith("/token")
      ? JSON.stringify({ id_token: "identity", refresh_token: "refresh", access_token: "access" }) : null,
    { status: 200 });
  };
  const tokens = await exchangeCode("one-use-code", "client-secret", fetcher);
  await revokeToken(tokens.refresh_token, "client-secret", fetcher);
  assert.equal(requests[0].url, "https://appleid.apple.com/auth/token");
  assert.deepEqual(requests[0].fields, { client_id: "com.daniellarkin.roam", client_secret: "client-secret",
    code: "one-use-code", grant_type: "authorization_code" });
  assert.equal(requests[1].url, "https://appleid.apple.com/auth/revoke");
  assert.equal(requests[1].fields.token, "refresh");
  assert.equal(requests[1].fields.token_type_hint, "refresh_token");
});

test("failed Apple exchange stops before deletion", async () => {
  await assert.rejects(exchangeCode("bad-code", "secret", async () => new Response(null, { status: 400 })),
    /Apple token returned 400/);
});

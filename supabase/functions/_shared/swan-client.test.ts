// Tests unitaires _shared/swan-client.ts + swan-sign-s2s.ts
//
// Lancement local :
//   deno test --allow-env --allow-net=oauth.swan.io supabase/functions/_shared/swan-client.test.ts
//
// Ces tests valident la logique pure (PEM parsing, cache token, signature
// ECDSA) sans appel réseau réel à SWAN. Le cache token est testé via mock
// fetch global.

import { assertEquals, assertRejects, assert } from "https://deno.land/std@0.218.0/assert/mod.ts";
import { getSwanAccessToken, resetSwanTokenCache, SwanAuthError, swanEnv } from "./swan-client.ts";
import { signSwanS2S, resetSwanS2SKeyCache, SwanS2SSignError } from "./swan-sign-s2s.ts";

const originalFetch = globalThis.fetch;
const originalEnv = { ...Deno.env.toObject() };

function restoreEnv() {
  for (const key of Object.keys(Deno.env.toObject())) {
    if (key.startsWith("SWAN_")) Deno.env.delete(key);
  }
  for (const [k, v] of Object.entries(originalEnv)) {
    if (k.startsWith("SWAN_")) Deno.env.set(k, v);
  }
}

Deno.test("swanEnv : valeurs par défaut", () => {
  restoreEnv();
  Deno.env.delete("SWAN_OAUTH_URL");
  Deno.env.delete("SWAN_ENVIRONMENT");
  const env = swanEnv();
  assertEquals(env.oauthUrl, "https://oauth.swan.io");
  assertEquals(env.environment, "sandbox");
  assertEquals(env.isLive, false);
});

Deno.test("swanEnv : lit SWAN_ENVIRONMENT=live", () => {
  Deno.env.set("SWAN_ENVIRONMENT", "live");
  const env = swanEnv();
  assertEquals(env.environment, "live");
  assertEquals(env.isLive, true);
  Deno.env.delete("SWAN_ENVIRONMENT");
});

Deno.test("getSwanAccessToken : erreur si client_id manquant", async () => {
  resetSwanTokenCache();
  Deno.env.delete("SWAN_CLIENT_ID");
  Deno.env.delete("SWAN_CLIENT_SECRET");
  await assertRejects(
    () => getSwanAccessToken(),
    SwanAuthError,
    "SWAN_CLIENT_ID",
  );
});

Deno.test("getSwanAccessToken : cache le token entre 2 appels", async () => {
  resetSwanTokenCache();
  Deno.env.set("SWAN_CLIENT_ID", "test_client");
  Deno.env.set("SWAN_CLIENT_SECRET", "test_secret");

  let fetchCount = 0;
  globalThis.fetch = ((..._args: unknown[]) => {
    fetchCount++;
    return Promise.resolve(new Response(
      JSON.stringify({ access_token: "tok_abc", token_type: "Bearer", expires_in: 3600 }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    ));
  }) as typeof fetch;

  try {
    const t1 = await getSwanAccessToken();
    const t2 = await getSwanAccessToken();
    assertEquals(t1, "tok_abc");
    assertEquals(t2, "tok_abc");
    assertEquals(fetchCount, 1, "Le token doit être servi depuis le cache au 2e appel");
  } finally {
    globalThis.fetch = originalFetch;
    resetSwanTokenCache();
  }
});

Deno.test("getSwanAccessToken : erreur si OAuth endpoint répond 401", async () => {
  resetSwanTokenCache();
  Deno.env.set("SWAN_CLIENT_ID", "test_client");
  Deno.env.set("SWAN_CLIENT_SECRET", "wrong_secret");

  globalThis.fetch = (() => Promise.resolve(new Response(
    JSON.stringify({ error: "invalid_client" }),
    { status: 401 },
  ))) as typeof fetch;

  try {
    await assertRejects(
      () => getSwanAccessToken(),
      SwanAuthError,
      "401",
    );
  } finally {
    globalThis.fetch = originalFetch;
    resetSwanTokenCache();
  }
});

Deno.test("signSwanS2S : erreur si clé manquante", async () => {
  resetSwanS2SKeyCache();
  Deno.env.delete("SWAN_S2S_PRIVATE_KEY_PEM");
  await assertRejects(
    () => signSwanS2S("payload"),
    SwanS2SSignError,
    "manquant",
  );
});

Deno.test("signSwanS2S : erreur si PEM invalide", async () => {
  resetSwanS2SKeyCache();
  Deno.env.set("SWAN_S2S_PRIVATE_KEY_PEM", "not a pem");
  await assertRejects(
    () => signSwanS2S("payload"),
    SwanS2SSignError,
    "PKCS#8",
  );
  Deno.env.delete("SWAN_S2S_PRIVATE_KEY_PEM");
});

Deno.test("signSwanS2S : signe correctement avec une clé PKCS#8 valide", async () => {
  resetSwanS2SKeyCache();
  // Génère une clé ECDSA P-256 PKCS#8 PEM via SubtleCrypto
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8Buf = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const pkcs8B64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8Buf)));
  // Découpe 64 char/ligne
  const lines: string[] = [];
  for (let i = 0; i < pkcs8B64.length; i += 64) lines.push(pkcs8B64.slice(i, i + 64));
  const pem = `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;

  Deno.env.set("SWAN_S2S_PRIVATE_KEY_PEM", pem);

  const sig = await signSwanS2S("mon-payload");
  assert(typeof sig === "string");
  assert(sig.length > 50, "La signature doit avoir une longueur raisonnable");

  // Vérif round-trip : la signature doit être vérifiable avec la clé publique
  const sigBytes = Uint8Array.from(atob(sig), c => c.charCodeAt(0));
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    sigBytes,
    new TextEncoder().encode("mon-payload"),
  );
  assertEquals(ok, true);

  Deno.env.delete("SWAN_S2S_PRIVATE_KEY_PEM");
  resetSwanS2SKeyCache();
});

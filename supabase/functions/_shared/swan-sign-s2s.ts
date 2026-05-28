// _shared/swan-sign-s2s.ts — Signature ECDSA P-256 pour Server-to-Server consent SWAN
//
// Foundation Sprint 17-A Phase A.
//
// SWAN S2S consent : le représentant légal Jolene SASU (Gabrielle) a installé
// la clé publique ECDSA P-256 dans le SWAN Dashboard > Server Consent. Toutes
// les mutations soumises à consent (initiateCreditTransfers, etc.) doivent
// être accompagnées d'une signature ECDSA P-256 SHA-256 du corps de la requête,
// signée avec la clé privée correspondante (SWAN_S2S_PRIVATE_KEY_PEM).
//
// Variable d'environnement :
//   SWAN_S2S_PRIVATE_KEY_PEM — clé privée PKCS#8 PEM
//                              (-----BEGIN PRIVATE KEY-----...)
//
// La paire de clés est générée hors-ligne via :
//   openssl ecparam -name prime256v1 -genkey -noout -out priv.pem
//   openssl pkcs8 -topk8 -nocrypt -in priv.pem -out priv-pkcs8.pem
//   openssl ec -in priv-pkcs8.pem -pubout -out pub.pem
//
// La clé publique est collée dans SWAN Dashboard. La privée reste dans
// Supabase Secrets, jamais en clair en dehors.

let _cachedKey: CryptoKey | null = null;

export class SwanS2SSignError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SwanS2SSignError";
  }
}

/**
 * Convertit une chaîne PEM PKCS#8 en ArrayBuffer.
 * Strip les bordures `-----BEGIN/END PRIVATE KEY-----` + line breaks.
 */
function pemPkcs8ToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

/**
 * Charge la clé privée S2S depuis SWAN_S2S_PRIVATE_KEY_PEM, cache en mémoire.
 */
async function loadPrivateKey(): Promise<CryptoKey> {
  if (_cachedKey) return _cachedKey;
  const pem = Deno.env.get("SWAN_S2S_PRIVATE_KEY_PEM") || "";
  if (!pem) throw new SwanS2SSignError("SWAN_S2S_PRIVATE_KEY_PEM manquant");
  if (!pem.includes("BEGIN PRIVATE KEY")) {
    throw new SwanS2SSignError(
      "SWAN_S2S_PRIVATE_KEY_PEM doit être au format PKCS#8 PEM (BEGIN PRIVATE KEY)",
    );
  }
  const keyData = pemPkcs8ToArrayBuffer(pem);
  _cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return _cachedKey;
}

/** Reset du cache (utile pour tests / rotation manuelle). */
export function resetSwanS2SKeyCache() {
  _cachedKey = null;
}

/**
 * Signe un payload (body GraphQL JSON) avec ECDSA P-256 SHA-256.
 * Retourne la signature en base64 standard.
 */
export async function signSwanS2S(payload: string | Uint8Array): Promise<string> {
  const key = await loadPrivateKey();
  const data = typeof payload === "string"
    ? new TextEncoder().encode(payload)
    : payload;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    data,
  );
  // base64 standard
  const bytes = new Uint8Array(sig);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

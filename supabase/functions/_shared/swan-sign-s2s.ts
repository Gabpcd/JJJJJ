// _shared/swan-sign-s2s.ts — Signature ECDSA P-256 pour Server-to-Server consent SWAN
//
// Foundation Sprint 17-A Phase A.
//
// SWAN S2S consent : après une mutation sensible, Swan renvoie un consent et
// son challenge. Le serveur signe un JWT ES256 contenant uniquement ce
// challenge, puis appelle `grantConsentWithServerSignature`. Il ne faut jamais
// signer le corps GraphQL ni inventer un header de signature propriétaire.
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
 * Signe le challenge Swan sous la forme JWT ES256 officielle :
 * base64url({alg:"ES256",typ:"JWT"}).base64url({challenge}).base64url(signature).
 */
export async function signSwanS2S(challenge: string): Promise<string> {
  if (
    typeof challenge !== "string" || challenge.length < 8 ||
    challenge.length > 4096
  ) {
    throw new SwanS2SSignError("Challenge SWAN invalide");
  }
  const key = await loadPrivateKey();
  const base64Url = (source: Uint8Array): string => {
    let binary = "";
    for (let index = 0; index < source.length; index += 1) {
      binary += String.fromCharCode(source[index]);
    }
    return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(
      /\//g,
      "_",
    );
  };
  const encoder = new TextEncoder();
  const header = base64Url(
    encoder.encode(JSON.stringify({ alg: "ES256", typ: "JWT" })),
  );
  const payload = base64Url(encoder.encode(JSON.stringify({ challenge })));
  const signingInput = `${header}.${payload}`;
  const source = encoder.encode(signingInput);
  // Deno 2.9 / TypeScript 6 distingue ArrayBuffer de SharedArrayBuffer dans
  // BufferSource. Une copie dédiée garantit ici un Uint8Array<ArrayBuffer>.
  const data = new Uint8Array(source.byteLength);
  data.set(source);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    data,
  );
  const bytes = new Uint8Array(sig);
  return `${signingInput}.${base64Url(bytes)}`;
}

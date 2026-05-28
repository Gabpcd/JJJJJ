// _shared/apns-client.ts — Push iOS via APNs direct (HTTP/2), sans Firebase
//
// Auth : JWT ES256 signé avec la clé .p8 APNs (Apple Developer), PAS de
// service account Google. Contourne l'org policy GCP qui bloque la création
// de clés service account Firebase.
//
// Variables d'environnement (secrets Supabase) :
//   APNS_KEY_P8       — contenu de la clé .p8 (PKCS#8 PEM, BEGIN PRIVATE KEY)
//   APNS_KEY_ID       — Key ID (10 caractères, Apple Developer > Keys)
//   APNS_TEAM_ID      — Team ID (10 caractères, visible en haut du compte)
//   APNS_BUNDLE_ID    — bundle id app (défaut: app.jolene)
//   APNS_ENVIRONMENT  — "production" (défaut) | "sandbox" (builds debug Xcode)

let _cachedJwt: { token: string; iat: number } | null = null;
let _cachedKey: CryptoKey | null = null;

const JWT_TTL_SECONDS = 3000; // 50 min (APNs exige < 60 min)

export function apnsConfigured(): boolean {
  return !!(Deno.env.get("APNS_KEY_P8") && Deno.env.get("APNS_KEY_ID") && Deno.env.get("APNS_TEAM_ID"));
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

async function loadApnsKey(): Promise<CryptoKey> {
  if (_cachedKey) return _cachedKey;
  const p8 = Deno.env.get("APNS_KEY_P8") || "";
  if (!p8.includes("BEGIN PRIVATE KEY")) {
    throw new Error("APNS_KEY_P8 doit être au format PKCS#8 PEM (BEGIN PRIVATE KEY)");
  }
  _cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return _cachedKey;
}

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_cachedJwt && now - _cachedJwt.iat < JWT_TTL_SECONDS) {
    return _cachedJwt.token;
  }
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const key = await loadApnsKey();

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${payload}`;

  // Web Crypto ECDSA → signature au format JOSE (r||s, 64 octets) = exactement ce qu'attend JWT
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${base64url(new Uint8Array(sig))}`;
  _cachedJwt = { token, iat: now };
  return token;
}

export interface ApnsResult {
  ok: boolean;
  expired: boolean;
  error?: string;
}

/**
 * Envoie une notification push via APNs HTTP/2.
 * @param deviceToken token APNs hex (depuis @capacitor/push-notifications)
 */
export async function sendApns(opts: {
  deviceToken: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<ApnsResult> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") || "app.jolene";
  const env = Deno.env.get("APNS_ENVIRONMENT") || "production";
  const host = env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

  const jwt = await getApnsJwt();

  const payload = JSON.stringify({
    aps: {
      alert: { title: opts.title, body: opts.body },
      sound: "default",
    },
    ...(opts.data || {}),
  });

  const res = await fetch(`https://${host}/3/device/${opts.deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: payload,
  });

  if (res.status === 200) return { ok: true, expired: false };

  // 410 = token désinscrit/expiré ; 400 BadDeviceToken = invalide
  let reason = "";
  try { reason = (await res.json())?.reason || ""; } catch { /* ignore */ }
  const expired = res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered";
  return { ok: false, expired, error: `APNs ${res.status}: ${reason || "unknown"}` };
}

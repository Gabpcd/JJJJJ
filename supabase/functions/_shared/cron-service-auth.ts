/**
 * Authentification commune des Edge Functions déclenchées par pg_cron.
 *
 * Les fonctions cron ont `verify_jwt = false` car le secret d'automatisation
 * n'est pas un JWT utilisateur. Elles doivent donc toutes appeler ce helper
 * avant la moindre lecture ou écriture métier.
 *
 * Ordre de transition :
 *   1. `x-jolene-cron-secret` : secret dédié stocké dans Vault
 *      (`cron_automations_key`) — voie recommandée ;
 *   2. `apikey` : clé secrète Supabase nommée `automations`, si configurée ;
 *   3. `Authorization: Bearer …` : compatibilité avec les anciens jobs et les
 *      appels Edge -> Edge déjà déployés.
 *
 * Important : toutes les sources de secrets sont comparées. Une variable
 * d'environnement présente mais différente ne doit jamais masquer le secret
 * Vault — c'était la cause du 401 de `litige-escalation-cron`.
 */

export type CronAuthChannel =
  | "x-jolene-cron-secret"
  | "apikey"
  | "authorization";

export type CronServiceAuthResult =
  | { ok: true; channel: CronAuthChannel }
  | { ok: false; status: 401 | 500; error: string };

type SupabaseRpcClient = {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error?: { message?: string } | null }>;
};

type CronServiceAuthOptions = {
  /** Injection réservée aux tests unitaires. */
  expectedSecrets?: readonly string[];
  /** Désactive les lectures d'environnement/Vault dans les tests unitaires. */
  loadConfiguredSecrets?: boolean;
};

const encoder = new TextEncoder();
const VAULT_CACHE_TTL_MS = 5 * 60_000;
let vaultCache: { values: string[]; expiresAt: number } | null = null;

function normalizedSecret(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function uniqueNonEmpty(values: readonly unknown[]): string[] {
  return [...new Set(values.map(normalizedSecret).filter(Boolean))];
}

function parseNamedAutomationSecrets(raw: string): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return uniqueNonEmpty([
      parsed.automations,
      parsed.cron,
      parsed.default,
    ]);
  } catch {
    // Une configuration JSON invalide échoue fermée : elle n'est jamais
    // interprétée comme une clé brute.
    return [];
  }
}

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(value)),
  );
}

/** Comparaison sur empreintes de longueur fixe, sans `includes()` de secrets. */
export async function timingSafeSecretEqual(
  presented: string,
  expected: string,
): Promise<boolean> {
  const [left, right] = await Promise.all([digest(presented), digest(expected)]);
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left[index] ^ right[index];
  }
  return mismatch === 0;
}

async function readVaultSecrets(admin: SupabaseRpcClient | null): Promise<string[]> {
  if (!admin) return [];
  if (vaultCache && vaultCache.expiresAt > Date.now()) return vaultCache.values;

  const values: string[] = [];
  for (const rpc of ["fn_lire_secret_cron_automations", "fn_lire_secret_cron"]) {
    try {
      const { data, error } = await admin.rpc(rpc);
      if (!error && typeof data === "string" && data.trim()) values.push(data.trim());
    } catch {
      // La compatibilité avec une base n'ayant pas encore la nouvelle RPC est
      // volontaire. L'absence de toute autre clé fera échouer l'authentification.
    }
  }

  const normalized = uniqueNonEmpty(values);
  // Cache court : une rotation/révocation Vault doit prendre effet sans
  // attendre le recyclage de l'isolate Edge.
  vaultCache = {
    values: normalized,
    expiresAt: Date.now() + VAULT_CACHE_TTL_MS,
  };
  return normalized;
}

async function configuredSecrets(
  admin: SupabaseRpcClient | null,
  options: CronServiceAuthOptions,
): Promise<string[]> {
  const injected = uniqueNonEmpty(options.expectedSecrets ?? []);
  if (options.loadConfiguredSecrets === false) return injected;

  const named = parseNamedAutomationSecrets(
    Deno.env.get("SUPABASE_SECRET_KEYS") || "",
  );
  const env = uniqueNonEmpty([
    Deno.env.get("CRON_AUTOMATIONS_SECRET"),
    Deno.env.get("CRON_SECRET"),
    Deno.env.get("SUPABASE_SECRET_KEY"),
    Deno.env.get("SB_SECRET_KEY"),
    // Compatibilité transitoire avec les appels internes existants.
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    ...named,
  ]);
  const vault = await readVaultSecrets(admin);
  return uniqueNonEmpty([...injected, ...env, ...vault]);
}

function presentedTokens(
  req: Request,
): Array<{ channel: CronAuthChannel; value: string }> {
  const authorization = req.headers.get("authorization") || "";
  const bearer = authorization.replace(/^Bearer\s+/i, "").trim();
  return [
    {
      channel: "x-jolene-cron-secret",
      value: normalizedSecret(req.headers.get("x-jolene-cron-secret")),
    },
    {
      channel: "apikey",
      value: normalizedSecret(req.headers.get("apikey")),
    },
    { channel: "authorization", value: bearer },
  ].filter((entry) => entry.value);
}

export async function verifyCronServiceAuth(
  req: Request,
  admin: SupabaseRpcClient | null,
  options: CronServiceAuthOptions = {},
): Promise<CronServiceAuthResult> {
  const presented = presentedTokens(req);
  if (presented.length === 0) {
    return { ok: false, status: 401, error: "Authentification cron manquante" };
  }

  const expected = await configuredSecrets(admin, options);
  if (expected.length === 0) {
    console.error("[cron-auth] aucun secret d'automatisation configuré");
    return { ok: false, status: 500, error: "Configuration cron indisponible" };
  }

  for (const candidate of presented) {
    for (const secret of expected) {
      if (await timingSafeSecretEqual(candidate.value, secret)) {
        return { ok: true, channel: candidate.channel };
      }
    }
  }

  return { ok: false, status: 401, error: "Authentification cron invalide" };
}

export function cronAuthErrorResponse(
  result: Extract<CronServiceAuthResult, { ok: false }>,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify({ error: result.error }), {
    status: result.status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

/** Sonde sans effet métier, utilisable après déploiement avant réactivation. */
export function isCronAuthProbe(req: Request): boolean {
  return req.headers.get("x-jolene-cron-probe") === "auth-only";
}

export function cronAuthProbeResponse(
  result: Extract<CronServiceAuthResult, { ok: true }>,
): Response {
  return new Response(JSON.stringify({
    authenticated: true,
    channel: result.channel,
  }), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

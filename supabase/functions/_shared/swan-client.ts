// _shared/swan-client.ts — Client SWAN API (OAuth2 + GraphQL)
//
// Foundation Sprint 17-A Phase A.
//
// Usage :
//   const result = await swanGraphQL(`query { accounts(first: 1) { ... } }`, {});
//   if (result.ok) console.log(result.data);
//
// Authentification : OAuth2 client_credentials → access token mis en cache
// jusqu'à 60s avant expiration. Pas de scope demandé (les permissions sont
// attachées au projet côté SWAN Dashboard).
//
// Variables d'environnement :
//   SWAN_OAUTH_URL     — base URL OAuth (défaut: https://oauth.swan.io)
//   SWAN_CLIENT_ID     — Client ID OAuth (Dashboard SWAN > Developers > API)
//   SWAN_CLIENT_SECRET — Client Secret OAuth
//   SWAN_GRAPHQL_URL   — URL endpoint GraphQL (sandbox ou live)
//   SWAN_ENVIRONMENT   — "sandbox" | "live" (informatif, pour logs)

interface SwanTokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

interface CachedToken {
  token: string;
  expiresAt: number; // epoch ms
}

let _cachedToken: CachedToken | null = null;

const TOKEN_REFRESH_MARGIN_MS = 60_000;

export function swanEnv() {
  const env = Deno.env.get("SWAN_ENVIRONMENT") || "sandbox";
  return {
    oauthUrl: Deno.env.get("SWAN_OAUTH_URL") || "https://oauth.swan.io",
    clientId: Deno.env.get("SWAN_CLIENT_ID") || "",
    clientSecret: Deno.env.get("SWAN_CLIENT_SECRET") || "",
    graphqlUrl: Deno.env.get("SWAN_GRAPHQL_URL") || "",
    accountId: Deno.env.get("SWAN_ACCOUNT_ID") || "",
    environment: env,
    isLive: env === "live",
  };
}

export class SwanAuthError extends Error {
  constructor(message: string, public statusCode?: number) {
    super(message);
    this.name = "SwanAuthError";
  }
}

export class SwanGraphQLError extends Error {
  constructor(message: string, public errors?: unknown) {
    super(message);
    this.name = "SwanGraphQLError";
  }
}

/**
 * Récupère un access token SWAN via OAuth2 client_credentials.
 * Cache en mémoire jusqu'à 60s avant expiration.
 */
export async function getSwanAccessToken(
  options?: { signal?: AbortSignal },
): Promise<string> {
  const now = Date.now();
  if (_cachedToken && _cachedToken.expiresAt > now + TOKEN_REFRESH_MARGIN_MS) {
    return _cachedToken.token;
  }

  const env = swanEnv();
  if (!env.clientId || !env.clientSecret) {
    throw new SwanAuthError("SWAN_CLIENT_ID ou SWAN_CLIENT_SECRET manquant");
  }

  const formData = new FormData();
  formData.append("grant_type", "client_credentials");
  formData.append("client_id", env.clientId);
  formData.append("client_secret", env.clientSecret);

  const res = await fetch(`${env.oauthUrl}/oauth2/token`, {
    method: "POST",
    headers: { Accept: "application/json" },
    body: formData,
    signal: options?.signal ?? AbortSignal.timeout(2_500),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new SwanAuthError(
      `OAuth2 token endpoint ${res.status}: ${text.slice(0, 500)}`,
      res.status,
    );
  }

  const json: SwanTokenResponse = await res.json();
  if (!json.access_token) {
    throw new SwanAuthError("Token endpoint OK mais access_token absent");
  }

  const expiresInMs = (json.expires_in || 3600) * 1000;
  _cachedToken = {
    token: json.access_token,
    expiresAt: now + expiresInMs,
  };

  return json.access_token;
}

/** Reset du cache token (utile pour tests / rotation manuelle). */
export function resetSwanTokenCache() {
  _cachedToken = null;
}

export interface SwanGraphQLResult<T = unknown> {
  ok: boolean;
  data?: T;
  errors?: unknown;
  httpStatus?: number;
}

/**
 * Exécute une mutation/query GraphQL contre l'API SWAN partner.
 * Authentification automatique via getSwanAccessToken (Bearer).
 *
 * Les mutations sensibles exigent ensuite le flux de consentement Swan :
 * challenge signé en JWT ES256 puis `grantConsentWithServerSignature`.
 * Il ne s'agit pas d'une signature ajoutée au corps de cette requête.
 */
export async function swanGraphQL<T = unknown>(
  query: string,
  variables: Record<string, unknown>,
  options?: { extraHeaders?: Record<string, string>; signal?: AbortSignal },
): Promise<SwanGraphQLResult<T>> {
  const env = swanEnv();
  if (!env.graphqlUrl) {
    throw new SwanGraphQLError("SWAN_GRAPHQL_URL manquant");
  }

  const token = await getSwanAccessToken({ signal: options?.signal });

  const res = await fetch(env.graphqlUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      "Accept": "application/json",
      ...(options?.extraHeaders || {}),
    },
    body: JSON.stringify({ query, variables }),
    signal: options?.signal,
  });

  const json = await res.json().catch(() => ({
    errors: [{ message: "Invalid JSON response" }],
  }));

  if (!res.ok) {
    return {
      ok: false,
      errors: json?.errors || [{ message: `HTTP ${res.status}` }],
      httpStatus: res.status,
    };
  }

  if (json?.errors) {
    return {
      ok: false,
      errors: json.errors,
      data: json.data as T,
      httpStatus: res.status,
    };
  }

  return { ok: true, data: json.data as T, httpStatus: res.status };
}

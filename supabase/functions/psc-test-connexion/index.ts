// Pro Santé Connect — outil de diagnostic admin.
// Réservé aux administrateurs plateforme. Vérifie la configuration PSC sans
// jamais logger ni exposer la valeur des secrets. Critique le jour de la bascule prod :
// permet de valider en 1 clic que les credentials ANS sont bien en place et que
// l'environnement OIDC répond.
//
// Réponse JSON :
// {
//   env: "production" | "sandbox",
//   secrets_ok: boolean,                    // tous les secrets requis présents
//   missing_secrets: string[],              // noms des secrets absents
//   discovery_ok: boolean,                  // .well-known/openid-configuration joignable
//   discovery_status: number | null,        // code HTTP de la découverte
//   endpoints_match: boolean,               // les endpoints du discovery correspondent au hardcode
//   endpoints_diff: string[],               // détails des éventuelles divergences
//   duration_ms: number,
// }

import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders, preflightResponse } from "../_shared/cors.ts";

// Endpoints hardcodés dans psc-authorize/psc-callback. Le test compare la
// découverte OIDC à ces valeurs : si l'ANS modifie un endpoint, on le détecte.
const PSC_HARDCODED = {
  sandbox: {
    issuer: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet",
    authorization_endpoint: "https://wallet.bas.esw.esante.gouv.fr/auth",
    token_endpoint: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    userinfo_endpoint: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
    end_session_endpoint: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    authorization_endpoint: "https://wallet.esw.esante.gouv.fr/auth",
    token_endpoint: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/token",
    userinfo_endpoint: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/userinfo",
    end_session_endpoint: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
  },
};

const REQUIRED_SECRETS = [
  "PSC_ENVIRONMENT",
  "PSC_CLIENT_ID",
  "PSC_CLIENT_SECRET",
  "PSC_REDIRECT_URI",
  "PSC_FRONTEND_URL",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }

  const t0 = Date.now();

  // ── Auth admin standardisée ──
  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) {
    return new Response(JSON.stringify({ error: auth.error }), {
      status: auth.status, headers: corsHeaders(req),
    });
  }

  // ── 1. Vérification des secrets (sans jamais les logger) ──
  const env = (Deno.env.get("PSC_ENVIRONMENT") || "sandbox") as "sandbox" | "production";
  const missingSecrets: string[] = [];
  for (const name of REQUIRED_SECRETS) {
    const value = Deno.env.get(name);
    if (!value || value.trim() === "") missingSecrets.push(name);
  }
  const secretsOk = missingSecrets.length === 0;

  // ── 2. Découverte OIDC (.well-known) ──
  const issuer = PSC_HARDCODED[env].issuer;
  const discoveryUrl = `${issuer}/.well-known/wallet-openid-configuration`;
  let discoveryOk = false;
  let discoveryStatus: number | null = null;
  let discoveredEndpoints: Record<string, string> = {};
  try {
    const res = await fetch(discoveryUrl, {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(5000),
    });
    discoveryStatus = res.status;
    if (res.ok) {
      const json = await res.json().catch(() => ({} as Record<string, unknown>));
      discoveryOk = typeof json.issuer === "string";
      discoveredEndpoints = {
        issuer: String(json.issuer || ""),
        authorization_endpoint: String(json.authorization_endpoint || ""),
        token_endpoint: String(json.token_endpoint || ""),
        userinfo_endpoint: String(json.userinfo_endpoint || ""),
        end_session_endpoint: String(json.end_session_endpoint || ""),
      };
    }
  } catch (e) {
    console.warn("PSC discovery failed:", e instanceof Error ? e.message : e);
  }

  // ── 3. Comparaison hardcode vs discovery ──
  const expected = PSC_HARDCODED[env];
  const endpointsDiff: string[] = [];
  if (discoveryOk) {
    for (const key of Object.keys(expected) as Array<keyof typeof expected>) {
      const exp = expected[key];
      const found = discoveredEndpoints[key];
      if (found && exp !== found) {
        endpointsDiff.push(`${key}: hardcoded="${exp}" discovered="${found}"`);
      } else if (!found) {
        endpointsDiff.push(`${key}: missing in discovery`);
      }
    }
  }
  const endpointsMatch = discoveryOk && endpointsDiff.length === 0;

  return new Response(JSON.stringify({
    env,
    secrets_ok: secretsOk,
    missing_secrets: missingSecrets,
    discovery_ok: discoveryOk,
    discovery_status: discoveryStatus,
    discovery_url: discoveryUrl,
    endpoints_match: endpointsMatch,
    endpoints_diff: endpointsDiff,
    duration_ms: Date.now() - t0,
  }), {
    status: 200,
    headers: corsHeaders(req),
  });
});

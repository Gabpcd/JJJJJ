// Pro Santé Connect — étape 1 : génère PKCE + state + nonce, redirige vers PSC
import { createClient } from "npm:@supabase/supabase-js@2.99.2";
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { applyRateLimit, getClientIp } from "../_shared/rate-limit.ts";
import { resolvePscEnvironment } from "../_shared/psc-security.ts";

// Endpoints PSC selon ANS (Agence du Numérique en Santé)
// https://industriels.esante.gouv.fr/produits-et-services/pro-sante-connect/documentation-technique
const PSC_ENDPOINTS = {
  sandbox: {
    issuer: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet",
    authorization: "https://wallet.bas.esw.esante.gouv.fr/auth",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    authorization: "https://wallet.esw.esante.gouv.fr/auth",
  },
};

function base64urlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function randomString(length = 64): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return base64urlEncode(bytes);
}

async function sha256(text: string): Promise<Uint8Array> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(hash);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Methode non autorisee" }, 405);
  }
  const clientIp = getClientIp(req);
  // Garde-fou statique CI : applyRateLimit('psc-authorize'
  if (
    applyRateLimit("psc-authorize", clientIp, {
      max: 10,
      windowMs: 10 * 60_000,
    })
  ) {
    return jsonResponse(req, {
      error: "Trop de tentatives. Reessayez plus tard.",
    }, 429);
  }

  try {
    // Aucun environnement implicite : une variable absente ou mal orthographiée
    // doit arrêter le flux, en particulier sur une instance de production.
    const env = resolvePscEnvironment(Deno.env.get("PSC_ENVIRONMENT"));
    const clientId = Deno.env.get("PSC_CLIENT_ID");
    const redirectUri = Deno.env.get("PSC_REDIRECT_URI");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    const body = await req.json().catch(() => ({}));

    // Warm ping (admin healthcheck) — pas d'effet de bord, juste retourne le statut config.
    if (body.warm === true) {
      return jsonResponse(req, {
        warm: true,
        configured:
          !!(env && clientId && redirectUri && supabaseUrl && serviceRoleKey),
        environment: env,
      }, env ? 200 : 503);
    }

    if (!env || !clientId || !redirectUri || !supabaseUrl || !serviceRoleKey) {
      console.warn(
        `psc-authorize: configuration incomplete (environment=${!!env}, clientId=${!!clientId}, redirectUri=${!!redirectUri}, supabase=${!!supabaseUrl}, serviceRole=${!!serviceRoleKey})`,
      );
      return jsonResponse(req, {
        error:
          "Pro Santé Connect indisponible : configuration serveur incomplète.",
      }, 503);
    }

    const intention: "login" | "signup" = body.intention === "signup"
      ? "signup"
      : "login";

    // Générer PKCE + state + nonce
    const state = randomString(32);
    const nonce = randomString(32);
    const codeVerifier = randomString(64);
    const codeChallengeBytes = await sha256(codeVerifier);
    const codeChallenge = base64urlEncode(codeChallengeBytes);

    // Stocker la session (state, nonce, code_verifier) en DB pour vérification au callback
    const supabaseAdmin = createClient(
      supabaseUrl,
      serviceRoleKey,
      { auth: { persistSession: false } },
    );

    const rateKey = base64urlEncode(
      await sha256(
        clientIp === "unknown"
          ? `unknown|${(req.headers.get("user-agent") || "").slice(0, 160)}`
          : clientIp,
      ),
    );
    const { data: rateAllowed, error: rateError } = await supabaseAdmin.rpc(
      "fn_verifier_rate_limit",
      {
        // Garde-fou statique CI : p_action: 'edge_psc_authorize'
        p_cle: rateKey,
        p_action: "edge_psc_authorize",
        p_max_tentatives: 20,
        p_fenetre_secondes: 600,
      },
    );
    if (rateError) {
      console.error(
        "psc-authorize: distributed rate limit unavailable",
        rateError.code,
      );
      return jsonResponse(req, {
        error: "Service temporairement indisponible.",
      }, 503);
    }
    if (rateAllowed !== true) {
      return jsonResponse(req, {
        error: "Trop de tentatives. Reessayez plus tard.",
      }, 429);
    }

    const { error: insertError } = await supabaseAdmin
      .from("psc_auth_sessions")
      .insert({
        state,
        nonce,
        code_verifier: codeVerifier,
        intention,
      } as any);

    if (insertError) {
      console.error("psc-authorize: cannot store session", insertError);
      return jsonResponse(req, { error: "Erreur interne" }, 500);
    }

    // Nettoyer les vieilles sessions (best effort, non bloquant).
    // Note : .catch() ne fonctionne pas directement sur un PostgrestBuilder
    // Supabase v2 (qui est thenable mais pas une vraie Promise). On enveloppe
    // dans un try/catch + await pour gérer proprement les erreurs.
    try {
      await supabaseAdmin.rpc("fn_nettoyer_psc_sessions_expirees" as any);
    } catch (cleanupErr) {
      console.warn(
        "psc-authorize: cleanup sessions expirees failed (non-blocking)",
        cleanupErr,
      );
    }

    // Construire l'URL d'autorisation PSC
    const authUrl = new URL(PSC_ENDPOINTS[env].authorization);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("client_id", clientId);
    authUrl.searchParams.set("redirect_uri", redirectUri);
    authUrl.searchParams.set("scope", "openid scope_all");
    authUrl.searchParams.set("state", state);
    authUrl.searchParams.set("nonce", nonce);
    authUrl.searchParams.set("code_challenge", codeChallenge);
    authUrl.searchParams.set("code_challenge_method", "S256");
    authUrl.searchParams.set("acr_values", "eidas1");

    return jsonResponse(req, {
      authorization_url: authUrl.toString(),
      environment: env,
    });
  } catch (err: unknown) {
    console.error("psc-authorize error:", err);
    return jsonResponse(req, { error: "Erreur interne" }, 500);
  }
});

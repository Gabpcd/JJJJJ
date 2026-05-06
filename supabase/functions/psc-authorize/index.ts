// Pro Santé Connect — étape 1 : génère PKCE + state + nonce, redirige vers PSC
import { createClient } from "npm:@supabase/supabase-js@2";

// Endpoints PSC selon ANS (Agence du Numérique en Santé)
// https://industriels.esante.gouv.fr/produits-et-services/pro-sante-connect/documentation-technique
const PSC_ENDPOINTS = {
  sandbox: {
    issuer: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet",
    authorization: "https://auth.bas.psc.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/auth",
  },
  production: {
    issuer: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet",
    authorization: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/auth",
  },
};

function base64urlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowed = [
    "https://jolene.app",
    "https://www.jolene.app",
    "http://localhost:5173",
    "http://localhost:8080",
  ];
  const allowedOrigin = allowed.includes(origin) ? origin : "https://jolene.app";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const env = (Deno.env.get("PSC_ENVIRONMENT") || "sandbox") as "sandbox" | "production";
    const clientId = Deno.env.get("PSC_CLIENT_ID");
    const redirectUri = Deno.env.get("PSC_REDIRECT_URI");

    if (!clientId || !redirectUri) {
      console.warn(`psc-authorize: configuration incomplete (clientId=${!!clientId}, redirectUri=${!!redirectUri})`);
      return new Response(JSON.stringify({
        error: "Pro Santé Connect indisponible : configuration serveur incomplète.",
      }), { status: 503, headers: corsHeaders(req) });
    }

    const body = await req.json().catch(() => ({}));
    const intention: "login" | "signup" = body.intention === "signup" ? "signup" : "login";

    // Générer PKCE + state + nonce
    const state = randomString(32);
    const nonce = randomString(32);
    const codeVerifier = randomString(64);
    const codeChallengeBytes = await sha256(codeVerifier);
    const codeChallenge = base64urlEncode(codeChallengeBytes);

    // Stocker la session (state, nonce, code_verifier) en DB pour vérification au callback
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

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
      return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
    }

    // Nettoyer les vieilles sessions
    await supabaseAdmin.rpc("fn_nettoyer_psc_sessions_expirees" as any).catch(() => {});

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

    return new Response(JSON.stringify({
      authorization_url: authUrl.toString(),
      environment: env,
    }), { status: 200, headers: corsHeaders(req) });
  } catch (err: unknown) {
    console.error("psc-authorize error:", err);
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});

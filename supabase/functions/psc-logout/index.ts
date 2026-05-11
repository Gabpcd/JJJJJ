// Pro Santé Connect — déconnexion propre via end_session_endpoint ANS.
// Appelée par le frontend quand un utilisateur connecté via PSC clique "Se déconnecter".
// Retourne l'URL end_session de PSC à laquelle le navigateur doit naviguer.
// PSC redirigera ensuite vers post_logout_redirect_uri (= https://jolene.app/connexion?logout=psc).
import { createClient } from "npm:@supabase/supabase-js@2";

// Endpoints PSC end_session selon ANS
const PSC_END_SESSION = {
  sandbox: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
  production: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
};

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
    const appUrl = Deno.env.get("PSC_FRONTEND_URL") || "https://jolene.app";
    const postLogoutRedirectUri = `${appUrl}/connexion?logout=psc`;

    // Best-effort : si PSC_CLIENT_ID absent (avant réception credentials ANS),
    // on retourne juste l'URL frontend de retour. Le frontend fera le signOut local.
    if (!clientId) {
      return new Response(JSON.stringify({
        configured: false,
        post_logout_redirect_uri: postLogoutRedirectUri,
      }), { status: 200, headers: corsHeaders(req) });
    }

    // Récupérer optionnellement l'id_token_hint depuis le body (best-effort)
    const body = await req.json().catch(() => ({}));
    const idTokenHint: string | undefined = typeof body.id_token_hint === "string" && body.id_token_hint.length > 0
      ? body.id_token_hint
      : undefined;

    // Vérifier que l'utilisateur est authentifié (pour éviter un endpoint ouvert)
    const authHeader = req.headers.get("Authorization") || "";
    const bearerToken = authHeader.replace(/^Bearer\s+/i, "");
    if (!bearerToken) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401, headers: corsHeaders(req),
      });
    }

    const supabaseAuth = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { auth: { persistSession: false } }
    );
    const { data: userData, error: userErr } = await supabaseAuth.auth.getUser(bearerToken);
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401, headers: corsHeaders(req),
      });
    }

    // Construire l'URL end_session PSC
    // Voir spec OIDC RP-Initiated Logout 1.0 :
    // https://openid.net/specs/openid-connect-rpinitiated-1_0.html
    const endSessionUrl = new URL(PSC_END_SESSION[env]);
    endSessionUrl.searchParams.set("client_id", clientId);
    endSessionUrl.searchParams.set("post_logout_redirect_uri", postLogoutRedirectUri);
    if (idTokenHint) {
      endSessionUrl.searchParams.set("id_token_hint", idTokenHint);
    }

    return new Response(JSON.stringify({
      configured: true,
      end_session_url: endSessionUrl.toString(),
      post_logout_redirect_uri: postLogoutRedirectUri,
      environment: env,
    }), { status: 200, headers: corsHeaders(req) });
  } catch (err: unknown) {
    console.error("psc-logout error:", err);
    return new Response(JSON.stringify({ error: "Erreur interne" }), {
      status: 500, headers: corsHeaders(req),
    });
  }
});

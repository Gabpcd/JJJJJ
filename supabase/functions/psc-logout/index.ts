// Pro Santé Connect — déconnexion propre via end_session_endpoint ANS.
// Appelée par le frontend quand un utilisateur connecté via PSC clique "Se déconnecter".
// Retourne l'URL end_session de PSC à laquelle le navigateur doit naviguer.
// PSC redirigera ensuite vers post_logout_redirect_uri (= https://jolene.app/connexion?logout=psc).
import { jsonResponse, preflightResponse } from "../_shared/cors.ts";
import { verifyUserOrServiceRole } from "../_shared/admin-auth.ts";

// Endpoints PSC end_session selon ANS
const PSC_END_SESSION = {
  sandbox: "https://auth.bas.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
  production: "https://auth.esw.esante.gouv.fr/auth/realms/esante-wallet/protocol/openid-connect/logout",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return preflightResponse(req);
  }
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);

  try {
    const auth = await verifyUserOrServiceRole(req);
    if (!auth.ok) return jsonResponse(req, { error: auth.error }, auth.status);
    if (auth.isServiceRole || !auth.userId) {
      return jsonResponse(req, { error: 'Deconnexion utilisateur uniquement' }, 403);
    }

    const env = (Deno.env.get("PSC_ENVIRONMENT") || "sandbox") as "sandbox" | "production";
    const clientId = Deno.env.get("PSC_CLIENT_ID");
    const appUrl = Deno.env.get("PSC_FRONTEND_URL") || "https://jolene.app";
    const postLogoutRedirectUri = `${appUrl}/connexion?logout=psc`;

    // Best-effort : si PSC_CLIENT_ID absent (avant réception credentials ANS),
    // on retourne juste l'URL frontend de retour. Le frontend fera le signOut local.
    if (!clientId) {
      return jsonResponse(req, {
        configured: false,
        post_logout_redirect_uri: postLogoutRedirectUri,
      });
    }

    // Récupérer optionnellement l'id_token_hint depuis le body (best-effort)
    const body = await req.json().catch(() => ({}));
    const idTokenHint: string | undefined = typeof body.id_token_hint === "string"
      && body.id_token_hint.length > 0 && body.id_token_hint.length <= 4096
      ? body.id_token_hint
      : undefined;

    // Construire l'URL end_session PSC
    // Voir spec OIDC RP-Initiated Logout 1.0 :
    // https://openid.net/specs/openid-connect-rpinitiated-1_0.html
    const endSessionUrl = new URL(PSC_END_SESSION[env]);
    endSessionUrl.searchParams.set("client_id", clientId);
    endSessionUrl.searchParams.set("post_logout_redirect_uri", postLogoutRedirectUri);
    if (idTokenHint) {
      endSessionUrl.searchParams.set("id_token_hint", idTokenHint);
    }

    return jsonResponse(req, {
      configured: true,
      end_session_url: endSessionUrl.toString(),
      post_logout_redirect_uri: postLogoutRedirectUri,
      environment: env,
    });
  } catch (err: unknown) {
    console.error("psc-logout error:", err);
    return jsonResponse(req, { error: "Erreur interne" }, 500);
  }
});

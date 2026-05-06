/**
 * test-piste-credentials — Diagnostic credentials PISTE/Chorus Pro
 *
 * Teste étape par étape que les secrets configurés permettent de :
 * 1. Obtenir un access_token OAuth2 (valide PISTE_CLIENT_ID + PISTE_CLIENT_SECRET)
 * 2. Appeler l'API structures Chorus Pro avec CHORUS_TECH_USER_LOGIN/PASSWORD
 *
 * Appel :
 *   curl -X POST https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/test-piste-credentials \
 *     -H "Authorization: Bearer <service_role_key>"
 *
 * Réponse structurée avec les étapes et diagnostic.
 * NE STOCKE RIEN ni dans la DB, juste retour JSON.
 */

const PISTE_URLS = {
  sandbox: {
    oauth: 'https://sandbox-oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://sandbox-api.piste.gouv.fr',
  },
  prod: {
    oauth: 'https://oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://api.piste.gouv.fr',
  },
};

// CORS standardisé : import depuis le helper partagé _shared/cors.ts
import { corsHeaders } from '../_shared/cors.ts';
// Auth admin standardisée : JWT user + check rôle ADMIN_PLATEFORME (avec
// bypass service_role pour les appels server-to-server type cron / admin-invoke).
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';

interface Diagnostic {
  step: string;
  status: 'OK' | 'FAIL' | 'SKIP';
  detail?: string;
  http_status?: number;
  duration_ms?: number;
}

/** Décode (sans vérifier la signature) le payload d'un JWT pour diagnostic.
 * Retourne les claims utiles (iss/aud/exp/scope/sub) sans jamais exposer
 * le token complet. Utilisé uniquement par cette fonction de diagnostic. */
function decodeJwtPayload(token: string | undefined): Record<string, unknown> | null {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '='.repeat((4 - b64.length % 4) % 4);
    return JSON.parse(atob(padded));
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });

  const diagnostics: Diagnostic[] = [];
  const start = Date.now();

  try {
    // Auth admin : JWT user (depuis frontend admin) ou service_role (server-to-server)
    const auth = await verifyAdminOrServiceRole(req);
    if (!auth.ok) {
      return new Response(JSON.stringify({ error: auth.error }), {
        status: auth.status, headers: corsHeaders(req),
      });
    }

    // ─── Étape 1 : Lecture des secrets ───
    // Support double naming (PISTE_* préféré, fallback CHORUS_PRO_* pour compat)
    const clientId = Deno.env.get('PISTE_CLIENT_ID') ?? Deno.env.get('CHORUS_PRO_CLIENT_ID');
    const clientSecret = Deno.env.get('PISTE_CLIENT_SECRET') ?? Deno.env.get('CHORUS_PRO_CLIENT_SECRET');
    const apiKey = Deno.env.get('PISTE_API_KEY');
    const techLogin = Deno.env.get('CHORUS_TECH_USER_LOGIN');
    const techPassword = Deno.env.get('CHORUS_TECH_USER_PASSWORD');
    const env = Deno.env.get('PISTE_ENV') ?? (Deno.env.get('CHORUS_PRO_SANDBOX') === 'false' ? 'prod' : 'sandbox');
    const isSandbox = env === 'sandbox';
    const urls = isSandbox ? PISTE_URLS.sandbox : PISTE_URLS.prod;

    diagnostics.push({
      step: '1. Secrets présents',
      status: (clientId && clientSecret) ? 'OK' : 'FAIL',
      detail: JSON.stringify({
        PISTE_CLIENT_ID: clientId ? `${clientId.slice(0, 6)}... (${clientId.length} chars)` : 'MISSING',
        PISTE_CLIENT_SECRET: clientSecret ? `***${clientSecret.slice(-4)} (${clientSecret.length} chars)` : 'MISSING',
        PISTE_API_KEY: apiKey ? `${apiKey.slice(0, 6)}... (${apiKey.length} chars)` : 'MISSING (optionnel)',
        CHORUS_TECH_USER_LOGIN: techLogin ? `${techLogin.slice(0, 4)}...@... (${techLogin.length} chars)` : 'MISSING',
        CHORUS_TECH_USER_PASSWORD: techPassword ? `*** (${techPassword.length} chars)` : 'MISSING',
        PISTE_ENV: env,
      }),
    });

    if (!clientId || !clientSecret) {
      return new Response(JSON.stringify({
        success: false,
        summary: 'PISTE_CLIENT_ID ou PISTE_CLIENT_SECRET manquant. Configurer dans Supabase Dashboard → Edge Functions → Secrets.',
        diagnostics,
      }), { status: 200, headers: corsHeaders(req) });
    }

    // ─── Étape 2 : OAuth2 client_credentials ───
    let accessToken: string | undefined;
    {
      const oauthStart = Date.now();
      try {
        const oauthBody = new URLSearchParams({
          grant_type: 'client_credentials',
          client_id: clientId,
          client_secret: clientSecret,
          scope: 'openid',
        });
        // OAuth endpoint = oauth.piste.gouv.fr (séparé de l'API Manager).
        // KeyId N'EST PAS attendu ici, contrairement aux endpoints API métier.
        // L'envoyer peut être rejeté par certains plans PISTE après recréation
        // d'app prod. On garde donc OAuth strictement minimal.
        const oauthHeaders: Record<string, string> = {
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        };
        const oauthRes = await fetch(urls.oauth, {
          method: 'POST',
          headers: oauthHeaders,
          body: oauthBody.toString(),
        });
        const oauthText = await oauthRes.text();
        let oauthData: any;
        try { oauthData = JSON.parse(oauthText); } catch { oauthData = { raw: oauthText }; }

        if (!oauthRes.ok) {
          diagnostics.push({
            step: '2. OAuth2 token request',
            status: 'FAIL',
            http_status: oauthRes.status,
            duration_ms: Date.now() - oauthStart,
            detail: `${urls.oauth} → ${oauthRes.status}: ${oauthData?.error || oauthData?.error_description || oauthText.slice(0, 200)}`,
          });
          return new Response(JSON.stringify({
            success: false,
            summary: `OAuth2 échec : ${oauthRes.status}. Vérifier PISTE_CLIENT_ID/SECRET sur https://piste.gouv.fr (${env}).`,
            env,
            diagnostics,
          }), { status: 200, headers: corsHeaders(req) });
        }

        accessToken = oauthData.access_token;

        // Décode le JWT pour vérifier iss/aud/scope/exp (claims attendus en prod) :
        // iss : https://oauth.piste.gouv.fr (ou équivalent issuer ANS)
        // aud : doit contenir une référence chorus-pro / cpro
        // scope : doit autoriser cpro.* ou openid + scope métier
        // exp : pas déjà expiré (timestamp futur)
        const claims = decodeJwtPayload(accessToken);
        const claimsSummary = claims ? {
          iss: claims.iss ?? '(absent)',
          aud: Array.isArray(claims.aud) ? claims.aud.join(',') : (claims.aud ?? '(absent)'),
          scope: claims.scope ?? '(absent)',
          sub: typeof claims.sub === 'string' ? `${claims.sub.slice(0, 8)}...` : '(absent)',
          exp: typeof claims.exp === 'number'
            ? `${new Date(claims.exp * 1000).toISOString()} (in ${claims.exp - Math.floor(Date.now() / 1000)}s)`
            : '(absent)',
        } : '(JWT non parsable)';

        diagnostics.push({
          step: '2. OAuth2 token request',
          status: 'OK',
          http_status: oauthRes.status,
          duration_ms: Date.now() - oauthStart,
          detail: `access_token obtenu (${accessToken?.length || 0} chars, expires_in=${oauthData.expires_in}s) | claims=${JSON.stringify(claimsSummary)}`,
        });
      } catch (fetchErr) {
        diagnostics.push({
          step: '2. OAuth2 token request',
          status: 'FAIL',
          duration_ms: Date.now() - oauthStart,
          detail: `Exception fetch OAuth : ${fetchErr instanceof Error ? fetchErr.message : String(fetchErr)}`,
        });
        return new Response(JSON.stringify({
          success: false,
          summary: 'Exception réseau lors de l\'appel OAuth PISTE',
          env, diagnostics,
        }), { status: 200, headers: corsHeaders(req) });
      }
    }

    // ─── Étape 3 : Ping API Chorus Pro (endpoint métier léger) ───
    // Endpoint recommanderChorusPro : /cpro/transverses/v1/recupererAnnuaireDestinataire
    // Alternative plus simple : consulter annuaire destinataire via API PISTE structures
    // ⚠️ Header `KeyId` requis sur les endpoints métier en prod (plan API Manager).
    const pingStart = Date.now();
    const pingUrl = `${urls.api}/cpro/transverses/v1/recupererUtilisateurCourant`;
    try {
      const pingHeaders: Record<string, string> = {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      };
      if (apiKey) pingHeaders['KeyId'] = apiKey;
      const pingRes = await fetch(pingUrl, {
        method: 'POST',
        headers: pingHeaders,
        body: JSON.stringify({ idUtilisateurCourant: 0 }),
      });
      const pingText = await pingRes.text();
      let pingData: any;
      try { pingData = JSON.parse(pingText); } catch { pingData = { raw: pingText.slice(0, 500) }; }

      diagnostics.push({
        step: '3. Ping API Chorus Pro (recupererUtilisateurCourant)',
        status: pingRes.ok ? 'OK' : 'FAIL',
        http_status: pingRes.status,
        duration_ms: Date.now() - pingStart,
        detail: pingRes.ok
          ? `Utilisateur courant : ${JSON.stringify(pingData).slice(0, 300)}`
          : `Erreur ${pingRes.status}: ${pingData?.libelleErreur || pingData?.error || pingText.slice(0, 200)}`,
      });
    } catch (pingErr) {
      diagnostics.push({
        step: '3. Ping API Chorus Pro (recupererUtilisateurCourant)',
        status: 'FAIL',
        duration_ms: Date.now() - pingStart,
        detail: `Exception fetch : ${pingErr instanceof Error ? pingErr.message : String(pingErr)}`,
      });
    }

    // ─── Étape 4 : Test auth Basic CHORUS_TECH_USER_* (si présent) ───
    if (techLogin && techPassword) {
      const techAuthStart = Date.now();
      try {
        const cproAccount = btoa(`${techLogin}:${techPassword}`);
        const techUrl = `${urls.api}/cpro/transverses/v1/rechercherStructure`;
        const techHeaders: Record<string, string> = {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'cpro-account': cproAccount,
        };
        if (apiKey) techHeaders['KeyId'] = apiKey;
        const techRes = await fetch(techUrl, {
          method: 'POST',
          headers: techHeaders,
          body: JSON.stringify({
            idUtilisateurCourant: 0,
            parametres: { nbResultatsMaxParPage: 1, numeroPagePourRechercher: 1, triSurChamp: 'Identifiant', triSensTri: 'Ascendant' },
            restreindreStructures: { structureActive: true },
            typeRecherche: 'ACTIF',
          }),
        });
        const techText = await techRes.text();
        let techData: any;
        try { techData = JSON.parse(techText); } catch { techData = { raw: techText.slice(0, 500) }; }

        diagnostics.push({
          step: '4. Auth CHORUS_TECH_USER (rechercherStructure)',
          status: techRes.ok ? 'OK' : 'FAIL',
          http_status: techRes.status,
          duration_ms: Date.now() - techAuthStart,
          detail: techRes.ok
            ? `Recherche structure OK (resultats=${techData?.listeStructures?.length ?? 0})`
            : `Erreur ${techRes.status}: ${techData?.libelleErreur || techData?.message || techText.slice(0, 200)}`,
        });
      } catch (techErr) {
        diagnostics.push({
          step: '4. Auth CHORUS_TECH_USER (rechercherStructure)',
          status: 'FAIL',
          duration_ms: Date.now() - techAuthStart,
          detail: `Exception fetch : ${techErr instanceof Error ? techErr.message : String(techErr)}`,
        });
      }
    } else {
      diagnostics.push({
        step: '4. Auth CHORUS_TECH_USER',
        status: 'SKIP',
        detail: 'CHORUS_TECH_USER_LOGIN/PASSWORD non configurés',
      });
    }

    // ─── Résumé ───
    const allOk = diagnostics.every(d => d.status === 'OK' || d.status === 'SKIP');
    const summary = allOk
      ? `✅ Tous les tests passent. Credentials PISTE/Chorus ${env} valides. Prêt pour intégration complète.`
      : `⚠️ Certains tests échouent. Voir diagnostics pour résoudre avant intégration complète.`;

    return new Response(JSON.stringify({
      success: allOk,
      summary,
      env,
      total_duration_ms: Date.now() - start,
      diagnostics,
    }), { status: 200, headers: corsHeaders(req) });

  } catch (err) {
    diagnostics.push({
      step: 'EXCEPTION',
      status: 'FAIL',
      detail: err instanceof Error ? err.message : String(err),
    });
    return new Response(JSON.stringify({
      success: false,
      summary: 'Exception lors du test',
      diagnostics,
    }), { status: 500, headers: corsHeaders(req) });
  }
});

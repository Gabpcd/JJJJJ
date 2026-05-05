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
    api: 'https://chorus-pro.gouv.fr',
  },
};

interface Diagnostic {
  step: string;
  status: 'OK' | 'FAIL' | 'SKIP';
  detail?: string;
  http_status?: number;
  duration_ms?: number;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });

  const diagnostics: Diagnostic[] = [];
  const start = Date.now();

  try {
    // Auth : accepte sb_secret_ (apikey header) OU JWT service_role (Bearer)
    const apikey = req.headers.get('apikey') || '';
    const authBearer = req.headers.get('Authorization')?.replace('Bearer ', '') || '';
    let isAuthed = false;
    if (apikey.startsWith('sb_secret_') || authBearer.startsWith('sb_secret_')) {
      isAuthed = true;
    } else {
      const token = authBearer || apikey;
      const parts = token.split('.');
      if (parts.length === 3) {
        try {
          const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
          const padded = b64 + '='.repeat((4 - b64.length % 4) % 4);
          const payload = JSON.parse(atob(padded));
          if (payload?.role === 'service_role') isAuthed = true;
        } catch { /* invalid JWT */ }
      }
    }
    if (!isAuthed) {
      return new Response(JSON.stringify({ error: 'Service role key requis (apikey ou Bearer)' }), {
        status: 403, headers: { 'Content-Type': 'application/json' },
      });
    }
    // Auth OK

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
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
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
        const oauthHeaders: Record<string, string> = {
          'Content-Type': 'application/x-www-form-urlencoded',
        };
        if (apiKey) oauthHeaders['KeyId'] = apiKey;
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
          }), { status: 200, headers: { 'Content-Type': 'application/json' } });
        }

        accessToken = oauthData.access_token;
        diagnostics.push({
          step: '2. OAuth2 token request',
          status: 'OK',
          http_status: oauthRes.status,
          duration_ms: Date.now() - oauthStart,
          detail: `access_token obtenu (${accessToken?.length || 0} chars, expires_in=${oauthData.expires_in}s)`,
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
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
    }

    // ─── Étape 3 : Ping API Chorus Pro (endpoint métier léger) ───
    // Endpoint recommanderChorusPro : /cpro/transverses/v1/recupererAnnuaireDestinataire
    // Alternative plus simple : consulter annuaire destinataire via API PISTE structures
    const pingStart = Date.now();
    const pingUrl = `${urls.api}/cpro/transverses/v1/recupererUtilisateurCourant`;
    try {
      const pingRes = await fetch(pingUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
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
        const techRes = await fetch(techUrl, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'cpro-account': cproAccount,
          },
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
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });

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
    }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});

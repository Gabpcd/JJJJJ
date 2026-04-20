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
    // Auth : service_role uniquement
    const authHeader = req.headers.get('Authorization');
    const expectedAuth = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`;
    if (authHeader !== expectedAuth) {
      return new Response(JSON.stringify({ error: 'Non autorisé (service_role requis)' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
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
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    // ─── Étape 2 : OAuth2 client_credentials ───
    const oauthStart = Date.now();
    const oauthBody = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: clientId,
      client_secret: clientSecret,
      scope: 'openid',
    });

    const oauthRes = await fetch(urls.oauth, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: oauthBody.toString(),
    });

    const oauthDuration = Date.now() - oauthStart;
    const oauthText = await oauthRes.text();
    let oauthData: any;
    try { oauthData = JSON.parse(oauthText); } catch { oauthData = { raw: oauthText }; }

    if (!oauthRes.ok) {
      diagnostics.push({
        step: '2. OAuth2 token request',
        status: 'FAIL',
        http_status: oauthRes.status,
        duration_ms: oauthDuration,
        detail: `${urls.oauth} → ${oauthRes.status}: ${oauthData?.error || oauthData?.error_description || oauthText.slice(0, 200)}`,
      });
      return new Response(JSON.stringify({
        success: false,
        summary: `OAuth2 échec : ${oauthRes.status}. Vérifier PISTE_CLIENT_ID/SECRET sur https://piste.gouv.fr (sandbox).`,
        env,
        diagnostics,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    const accessToken = oauthData.access_token;
    const expiresIn = oauthData.expires_in;
    diagnostics.push({
      step: '2. OAuth2 token request',
      status: 'OK',
      http_status: oauthRes.status,
      duration_ms: oauthDuration,
      detail: `access_token obtenu (${accessToken?.length || 0} chars, expires_in=${expiresIn}s)`,
    });

    // ─── Étape 3 : Ping API Chorus Pro (endpoint métier léger) ───
    // Endpoint recommanderChorusPro : /cpro/transverses/v1/recupererAnnuaireDestinataire
    // Alternative plus simple : consulter annuaire destinataire via API PISTE structures
    const pingStart = Date.now();
    const pingUrl = `${urls.api}/cpro/transverses/v1/recupererUtilisateurCourant`;
    const pingRes = await fetch(pingUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ idUtilisateurCourant: 0 }),
    });

    const pingDuration = Date.now() - pingStart;
    const pingText = await pingRes.text();
    let pingData: any;
    try { pingData = JSON.parse(pingText); } catch { pingData = { raw: pingText.slice(0, 500) }; }

    diagnostics.push({
      step: '3. Ping API Chorus Pro (recupererUtilisateurCourant)',
      status: pingRes.ok ? 'OK' : 'FAIL',
      http_status: pingRes.status,
      duration_ms: pingDuration,
      detail: pingRes.ok
        ? `Utilisateur courant : ${JSON.stringify(pingData).slice(0, 300)}`
        : `Erreur ${pingRes.status}: ${pingData?.libelleErreur || pingData?.error || pingText.slice(0, 200)}`,
    });

    // ─── Étape 4 : Test auth Basic CHORUS_TECH_USER_* (si présent) ───
    // Certains endpoints nécessitent en plus de l'OAuth2 un header
    // "cpro-account" = base64(login:password) pour identifier l'utilisateur technique.
    if (techLogin && techPassword) {
      const techAuthStart = Date.now();
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
      const techDuration = Date.now() - techAuthStart;
      const techText = await techRes.text();
      let techData: any;
      try { techData = JSON.parse(techText); } catch { techData = { raw: techText.slice(0, 500) }; }

      diagnostics.push({
        step: '4. Auth CHORUS_TECH_USER (rechercherStructure)',
        status: techRes.ok ? 'OK' : 'FAIL',
        http_status: techRes.status,
        duration_ms: techDuration,
        detail: techRes.ok
          ? `Recherche structure OK (resultats=${techData?.listeStructures?.length ?? 0})`
          : `Erreur ${techRes.status}: ${techData?.libelleErreur || techData?.message || techText.slice(0, 200)}`,
      });
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

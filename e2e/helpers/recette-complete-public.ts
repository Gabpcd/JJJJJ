import type { Page } from '@playwright/test';

export const missionPublique = {
  id: '69000000-0000-4000-8000-000000000072', intitule: 'Remplacement infirmier de jour',
  profession_requise: 'IDE', description: 'Mission de simulation dans le service de soins.',
  etablissement_nom: 'Résidence Camille', ville: 'Paris', code_postal: '75001',
  debut_le: '2026-11-02T07:00:00Z', fin_le: '2026-11-02T15:00:00Z', cree_le: '2026-09-24T00:00:00Z',
  taux_horaire_base: 30, type_contrat_recherche: 'SALARIE', est_urgente: true,
};
export const articleAide = {
  id: '69000000-0000-4000-8000-000000000091', slug: 'preparer-une-mission',
  titre: 'Préparer une mission', audience: 'COMMUN', categorie: 'Premiers pas',
  extrait: 'Découvrez les étapes de préparation.', contenu: '## Votre première mission\nConsultez les horaires et les conditions.\n- Vérifiez le lieu\n- Consultez le contrat',
  mis_a_jour_le: '2026-09-24T00:00:00Z',
};

/** Aucun compte réel, aucune fonction distante. Toute API inconnue fait échouer la recette. */
export async function simulerPublic(page: Page) {
  const user = { id: '69000000-0000-4000-8000-000000000071', email: 'recette@example.invalid', aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {}, identities: [] };
  const session = { user, token_type: 'bearer', access_token: 'fixture-public-auth', refresh_token: 'fixture-public-refresh', expires_in: 3600 };
  const state = {
    failures: new Set<string>(), unknown: [] as string[], errors: [] as string[],
    calls: [] as { name: string; body: any; method: string }[],
    missingMission: false, missingArticle: false,
    authError: 'invalid_credentials',
    overrides: new Map<string, unknown>(),
  };
  page.on('pageerror', e => state.errors.push(e.message));
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  await page.routeWebSocket('**/*', socket => socket.close());
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url()), name = url.pathname.split('/').pop()!;
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort();
    if (!/\/(auth|rest|functions|storage)\/v1\//.test(url.pathname)) {
      if (req.isNavigationRequest() && req.resourceType() === 'document') {
        // Les hints DNS/TLS échappent au routage HTTP, même avec une API locale.
        const response = await route.fetch();
        const html = (await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
        return route.fulfill({ response, body: html });
      }
      return route.continue();
    }
    const body = req.postData()?.startsWith('{') ? req.postDataJSON() : null;
    state.calls.push({ name, body, method: req.method() });
    if (url.pathname.startsWith('/rest/v1/') && !url.pathname.startsWith('/rest/v1/rpc/') && !['GET', 'HEAD'].includes(req.method())) {
      state.unknown.push(`${req.method()} ${url.pathname}`);
      return route.fulfill({ status: 501, json: { message: `Écriture de table non simulée : ${name}` } });
    }
    if (state.failures.has(name)) return route.fulfill({ status: 503, json: { message: 'Service indisponible', code: 'RECETTE_503' } });
    if (state.overrides.has(name)) return route.fulfill({ json: state.overrides.get(name) });
    if (url.pathname.includes('/auth/v1/')) {
      if (name === 'token') return route.fulfill({ status: 400, json: { code: state.authError, msg: state.authError === 'email_not_confirmed' ? 'Email not confirmed' : 'Invalid login credentials' } });
      if (name === 'signup') return route.fulfill({ status: 422, json: { code: 'weak_password', msg: 'Password is known to be weak and easy to guess, please choose a different one.', weak_password: { reasons: ['pwned'] } } });
      if (name === 'recover' || name === 'logout') return route.fulfill({ json: {} });
      if (name === 'verify') return route.fulfill({ json: session });
      if (name === 'user') return route.fulfill({ json: user });
    }
    if (url.pathname.includes('/rest/v1/rpc/')) {
      if (name === 'fn_mission_publique') return route.fulfill({ json: state.missingMission ? null : missionPublique });
      if (name === 'fn_rechercher_aide') return route.fulfill({ json: { articles: body?.p_query === 'introuvable' ? [] : [articleAide] } });
      if (name === 'fn_missions_publiques_recherche') return route.fulfill({ json: [] });
      if (name === 'fn_get_my_role') return route.fulfill({ json: { role: 'INCONNU', etablissement_id: null } });
      if (name === 'fn_compte_auth_actif') return route.fulfill({ json: true });
      if (name === 'fn_audit_connexion') return route.fulfill({ json: null });
    }
    if (url.pathname.includes('/rest/v1/') && name === 'articles_aide') return route.fulfill({ json: state.missingArticle ? [] : [articleAide] });
    if (url.pathname.includes('/rest/v1/') && name === 'parcours_inscription') return route.fulfill({ json: [] });
    if (url.pathname.includes('/functions/v1/') && name === 'contact-form') return route.fulfill({ json: { success: true } });
    state.unknown.push(`${req.method()} ${url.pathname}`);
    return route.fulfill({ status: 501, json: { message: `API non simulée : ${name}` } });
  });
  return state;
}

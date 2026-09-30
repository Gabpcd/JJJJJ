import { expect, test } from '@playwright/test';
import { simulerSoignant, attendreAPI, preuve } from './helpers/recette-complete-soignant';
import { manifestePoolDashboard } from '../scripts/ci/prepare-dashboard-pool.mjs';
import { parcourirDashboard, dashboardUIValide, preparerHtmlPreview } from '../scripts/ci/recette-dashboard-staging.mjs';
import { ORIGINE_UI, requeteUIAutorisee } from '../scripts/ci/dashboard-ui-contract.mjs';
import { STAGING_URL } from '../scripts/ci/prepare-load-fixtures.mjs';

test.use({ actionTimeout: 15_000 });
const membres = manifestePoolDashboard('ui-pilote-local').membres;
for (const slot of [0, 1]) {
  test(`pilote staging — parcours navigateur commun, slot ${slot} (API simulée)`, async ({ page }, info) => {
    const m = { ...membres[slot], password: `Aa1!secret-local-${slot}-entierement-fictif` };
    const state = await simulerSoignant(page);
    const requetesRefusees: string[] = [];
    let documentsPrepares = 0;
    // Même préparation du HTML produit et même garde avant le helper simulé :
    // celui-ci ne peut plus masquer un appel externe en l'abandonnant seul.
    await page.route('**/*', async route => {
      const req = route.request(), url = new URL(req.url());
      const local = ['127.0.0.1','localhost'].includes(url.hostname);
      const api = /^\/(auth|rest|functions|storage)\/v1\//.test(url.pathname);
      const cible = local ? (api ? STAGING_URL : ORIGINE_UI) + url.pathname + url.search : req.url();
      const body = req.postData() ? req.postDataJSON() : undefined;
      if (!requeteUIAutorisee({ url: cible, method: req.method(), body }, m)) {
        requetesRefusees.push(`${req.method()} ${url.origin}${url.pathname}`);
        return route.abort();
      }
      if (req.isNavigationRequest() && req.resourceType() === 'document') {
        const response = await route.fetch(); documentsPrepares++;
        return route.fulfill({ response, body: preparerHtmlPreview(await response.text()) });
      }
      return route.fallback();
    });
    Object.assign(state.profile, { id: m.userId, email: m.email, prenom: m.prenom, nom: m.nom,
      profession: 'AS', type_exercice: 'SALARIE', telephone: null, numero_rpps: null, numero_adeli: null,
      identite_verifiee: false, diplome_verifie: false, rpps_verifie: false, tous_documents_valides: false });
    const user = { id: m.userId, email: m.email, aud: 'authenticated', role: 'authenticated',
      email_confirmed_at: '2026-09-30T08:00:00Z', app_metadata: { role: 'SOIGNANT', est_compte_test: true }, user_metadata: {} };
    state.overrides.set('user', user);
    state.overrides.set('token', { user, access_token: `simulation-pilote-${slot}`, refresh_token: `simulation-refresh-${slot}`,
      token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600 });
    let validations = 0, captures = 0;
    await parcourirDashboard(page, m, { expect,
      verifierReponse: async response => {
        expect(response.status()).toBe(200);
        expect(dashboardUIValide(await response.json(), m)).toBe(true); validations++;
      },
      capturer: async etape => { await preuve(page, `pilote-${slot}-${etape}`, info, true); captures++; },
    });
    await attendreAPI(page);
    expect(validations).toBe(2); expect(captures).toBe(2);
    expect(documentsPrepares).toBe(2);
    expect(requetesRefusees).toEqual([]);
    await expect(page.locator('link[href*="fonts.googleapis.com"]')).toHaveCount(0);
    expect(state.calls.filter(c => c.name === 'token')).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_audit_connexion')).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_maj_activite_soignant')).toHaveLength(1);
    for (const c of state.calls) expect(requeteUIAutorisee({ url: STAGING_URL + c.url, method: c.method, body: c.body }, m), `${c.method} ${c.name}`).toBe(true);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  });
}

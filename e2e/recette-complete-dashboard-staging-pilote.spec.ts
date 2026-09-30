import { expect, test, type Page } from '@playwright/test';
import { simulerSoignant, attendreAPI, preuve } from './helpers/recette-complete-soignant';
import { manifestePoolDashboard } from '../scripts/ci/prepare-dashboard-pool.mjs';
import { parcourirDashboard, dashboardUIValide, preparerHtmlPreview } from '../scripts/ci/recette-dashboard-staging.mjs';
import { ORIGINE_UI, requeteUIAutorisee } from '../scripts/ci/dashboard-ui-contract.mjs';
import { creerDiagnosticUI } from '../scripts/ci/dashboard-ui-diagnostic.mjs';
import { STAGING_URL } from '../scripts/ci/prepare-load-fixtures.mjs';

test.use({ actionTimeout: 15_000 });
const membres = manifestePoolDashboard('ui-pilote-local').membres;
async function installerPiloteSimule(page: Page, slot: number) {
  const m = { ...membres[slot], password: `Aa1!secret-local-${slot}-entierement-fictif` };
  const state = await simulerSoignant(page);
  const diagnostic = creerDiagnosticUI();
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
      diagnostic.requete({url:cible,method:req.method(),statut:'refusee'});
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
  const cible = (urlBrute: string) => {
    const u=new URL(urlBrute);
    return ['127.0.0.1','localhost'].includes(u.hostname)
      ? (/^\/(auth|rest|functions|storage)\/v1\//.test(u.pathname) ? STAGING_URL : ORIGINE_UI)+u.pathname+u.search : urlBrute;
  };
  page.on('response', r=>diagnostic.requete({url:cible(r.url()),method:r.request().method(),statut:r.status()}));
  page.on('requestfailed', r=>diagnostic.requete({url:cible(r.url()),method:r.method(),statut:'transport'}));
  page.on('pageerror', ()=>diagnostic.javascript());
  return { m,state,diagnostic,requetesRefusees,documentsPrepares:()=>documentsPrepares };
}
for (const slot of [0, 1]) {
  test(`pilote staging — parcours navigateur commun, slot ${slot} (API simulée)`, async ({ page }, info) => {
    const { m,state,diagnostic,requetesRefusees,documentsPrepares } = await installerPiloteSimule(page,slot);
    let validations = 0, captures = 0;
    await parcourirDashboard(page, m, { expect, marquerPhase:phase=>diagnostic.phase(phase,slot),
      verifierReponse: async response => {
        expect(response.status()).toBe(200);
        expect(dashboardUIValide(await response.json(), m)).toBe(true); validations++;
      },
      capturer: async etape => { await preuve(page, `pilote-${slot}-${etape}`, info, true); captures++; },
    });
    await attendreAPI(page);
    expect(validations).toBe(2); expect(captures).toBe(2);
    expect(documentsPrepares()).toBe(2);
    expect(diagnostic.resultat().progression.map(p=>p.phase)).toEqual(['page','login','dashboard','reload']);
    expect(requetesRefusees).toEqual([]);
    await expect(page.locator('link[href*="fonts.googleapis.com"]')).toHaveCount(0);
    expect(state.calls.filter(c => c.name === 'token')).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_audit_connexion')).toHaveLength(1);
    expect(state.calls.filter(c => c.name === 'fn_maj_activite_soignant')).toHaveLength(1);
    for (const c of state.calls) expect(requeteUIAutorisee({ url: STAGING_URL + c.url, method: c.method, body: c.body }, m), `${c.method} ${c.name}`).toBe(true);
    expect(state.unknown).toEqual([]); expect(state.errors).toEqual([]);
  });
}


test('diagnostic — réponse dashboard 503, erreur visible après recharge, aucune capture de succès (API simulée)', async ({page}) => {
  const {m,state,diagnostic}=await installerPiloteSimule(page,0);
  state.failures.add('fn_dashboard_soignant_complet');
  let captures=0;
  await expect(parcourirDashboard(page,m,{expect,marquerPhase:phase=>diagnostic.phase(phase,0),
    verifierReponse:async r=>{if(r.status()!==200)throw new Error('Réponse dashboard refusée');},
    capturer:async()=>{captures++;},
  })).rejects.toThrow('Réponse dashboard refusée');
  await expect(page.getByRole('heading',{name:'Impossible de charger ton tableau de bord'})).toBeVisible();
  expect(captures).toBe(0);expect(diagnostic.resultat().phase).toBe('dashboard');
  expect(diagnostic.resultat().reseau).toEqual(expect.arrayContaining([expect.objectContaining({chemin:'fn_dashboard_soignant_complet',statut:503})]));
  await page.reload();
  await expect(page.getByRole('heading',{name:'Impossible de charger ton tableau de bord'})).toBeVisible();
  expect(state.calls.filter(c=>c.name==='token')).toHaveLength(1);
});

test('diagnostic — présence refusée avant transport, URL et corps canaris absents du rapport (API simulée)', async ({page}) => {
  const {m,state,diagnostic,requetesRefusees}=await installerPiloteSimule(page,0);
  await parcourirDashboard(page,m,{expect,marquerPhase:phase=>diagnostic.phase(phase,0),
    verifierReponse:async r=>expect(dashboardUIValide(await r.json(),m)).toBe(true),
  });
  const canari='secret-diagnostic-ne-jamais-exporter';
  // Requête navigateur supplémentaire volontairement interdite, entièrement locale.
  await page.evaluate(async secret=>{
    await fetch('http://127.0.0.1:8891/rest/v1/rpc/fn_update_presence?token='+secret,
      {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:secret})}).catch(()=>{});
  },canari);
  expect(requetesRefusees).toHaveLength(1);
  expect(state.calls.some(c=>c.name==='fn_update_presence')).toBe(false);
  expect(diagnostic.resultat().reseau).toEqual(expect.arrayContaining([expect.objectContaining({chemin:'fn_update_presence',statut:'refusee'})]));
  expect(JSON.stringify(diagnostic.resultat())).not.toContain(canari);
  await expect(page.locator('main').getByRole('heading',{level:1})).toContainText('Recette');
});

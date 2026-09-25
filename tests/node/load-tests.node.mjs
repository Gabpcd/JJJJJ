import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resumeCharge } from '../load/helpers/resume.js';
import { creerOptionsCharge } from '../load/helpers/options.js';
import { dashboardValide, rechercheValide, exigerRecherchePeuplee, exigerDashboardMetier, refuserScenarioNonIsole } from '../load/helpers/contrats.js';

const defaut = { executor: 'ramping-vus', startVUs: 0, stages: [{ duration: '20s', target: 100 }, { duration: '1m', target: 100 }, { duration: '10s', target: 0 }] };
test('overrides : VUs appliqués à chaque étage, sans modifier les valeurs par défaut', () => {
  const options = creerOptionsCharge('charge', defaut, {}, { LOAD_TEST_VUS: '7' });
  assert.deepEqual(options.scenarios.charge.stages.map(s => s.target), [7, 7, 0]);
  assert.deepEqual(defaut.stages.map(s => s.target), [100, 100, 0]);
});
test('override durée : durée totale explicite, sans rampe cachée', () => {
  assert.deepEqual(creerOptionsCharge('charge', defaut, {}, { LOAD_TEST_VUS: '3', LOAD_TEST_DURATION: '5s' }).scenarios.charge,
    { executor: 'constant-vus', vus: 3, duration: '5s', gracefulStop: '15s' });
  assert.equal(creerOptionsCharge('charge', defaut, {}, { LOAD_TEST_DURATION: '2m' }).scenarios.charge.vus, 100);
});
test('une itération par VU garde ce contrat lors des overrides', () => {
  const scenario = creerOptionsCharge('charge', { executor: 'per-vu-iterations', vus: 50, iterations: 1, maxDuration: '60s' }, {}, { LOAD_TEST_VUS: '2', LOAD_TEST_DURATION: '15s' }).scenarios.charge;
  assert.equal(scenario.vus, 2); assert.equal(scenario.iterations, 1); assert.equal(scenario.maxDuration, '15s');
});
test('refuse les paramètres dangereux ou ambigus et garde les seuils fonctionnels obligatoires', () => {
  for (const LOAD_TEST_VUS of ['0', '-1', '1.5', '1000', '2; echo bad']) assert.throws(() => creerOptionsCharge('charge', defaut, {}, { LOAD_TEST_VUS }));
  for (const LOAD_TEST_DURATION of ['0s', '-1s', '1h', '16m', '901s', '1s; echo bad']) assert.throws(() => creerOptionsCharge('charge', defaut, {}, { LOAD_TEST_DURATION }));
  const options = creerOptionsCharge('charge', defaut, { checks: ['rate>0'], iterations: ['count>=0'], http_req_duration: ['p(95)<1000'] });
  assert.deepEqual(options.thresholds.checks, ['rate==1']);
  assert.deepEqual(options.thresholds.iterations, ['count>0']);
  assert.deepEqual(options.thresholds.http_req_duration, ['p(95)<1000']);
});

const mission = { id: 'mission-fixture', intitule: 'Mission fictive', profession_requise: 'IDE', debut_le: '2026-09-26T08:00:00Z', fin_le: '2026-09-26T16:00:00Z', taux_horaire_base: 30, total_count: 1 };
const dashboard = { profil: { profession: 'IDE' }, missions_ouvertes: [], mes_missions: [], documents: [], gains_6mois: [], missions_semaine_cal: [], propositions: [], heures_semaine: 0, notifs_non_lues: 0, gains_mois: { net_total: 0, brut_total: 0, nb_missions: 0 } };
test('un objet erreur, null ou profil absent ne vaut jamais une réponse métier valide', () => {
  for (const value of [null, {}, [], { error: 'Non authentifié' }, { ...dashboard, profil: null }]) assert.equal(dashboardValide(value), false);
  for (const value of [null, {}, { error: 'Erreur' }, [{}], [{ ...mission, taux_horaire_base: '30' }]]) assert.equal(rechercheValide(value), false);
  assert.equal(dashboardValide(dashboard), true); assert.equal(rechercheValide([mission]), true);
  assert.equal(rechercheValide([]), true); // Un filtre sans résultat est légitime, le préflight peuplé ne l’est pas.
  assert.throws(() => exigerRecherchePeuplee([]), /base vide/);
  assert.throws(() => exigerDashboardMetier({ ...dashboard, profil: null }), /profil soignant/);
  assert.equal(exigerRecherchePeuplee([mission]), 1);
});

// Importer les scripts k6 réels avec leur HTTP remplacé par un transport en mémoire.
// Aucun serveur, compte, jeton réel ni accès réseau n'est nécessaire à ces tests.
let sequence = 0;
const urlCode = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const racineLoad = new URL('../load/', import.meta.url);
async function charger(nom, env = {}) {
  const appels = [], verifications = [], reponses = [];
  const pont = `__k6_fixture_${sequence++}`;
  globalThis.__ENV = { STAGING_SUPABASE_URL: 'https://mejpriaetwgtcstbgfid.supabase.co', STAGING_SUPABASE_ANON_KEY: 'fictif', LOAD_TEST_PASSWORD: 'fictif', ...env };
  globalThis.__ITER = 0; globalThis.__VU = 1;
  globalThis[pont] = {
    http: { post: (...args) => {
      appels.push(args); const reponse = reponses.shift();
      assert.ok(reponse, 'Toute requête doit avoir une réponse fictive explicite');
      return { status: reponse.status ?? 200, json: path => path ? reponse.body[path] : reponse.body };
    } },
    check: (res, checks) => {
      const resultats = Object.entries(checks).map(([nom, fn]) => ({ nom, ok: fn(res) }));
      verifications.push(...resultats); return resultats.every(r => r.ok);
    },
  };
  const httpUrl = urlCode(`export default globalThis.${pont}.http;`);
  const k6Url = urlCode(`export const check = globalThis.${pont}.check; export function sleep() {}`);
  const auth = (await readFile(new URL('helpers/auth.js', racineLoad), 'utf8')).replaceAll("'k6/http'", JSON.stringify(httpUrl)).replaceAll("'k6'", JSON.stringify(k6Url));
  let source = await readFile(new URL(`scenarios/${nom}.js`, racineLoad), 'utf8');
  for (const [specifier, remplacement] of [
    ['k6/http', httpUrl], ['k6', k6Url], ['../helpers/auth.js', urlCode(auth)],
    ...['options', 'contrats', 'data', 'resume'].map(n => [`../helpers/${n}.js`, new URL(`helpers/${n}.js`, racineLoad).href]),
  ]) source = source.replaceAll(`'${specifier}'`, JSON.stringify(remplacement));
  const module = await import(urlCode(`${source}\n// ${pont}`));
  return { module, appels, verifications, reponses };
}

for (const nom of ['01-inscription-bloc', '02-login-simultane', '03-recherche-missions', '05-dashboard-concurrent']) {
  test(`${nom} consomme effectivement les overrides et les seuils checks/itérations`, async () => {
    const { module } = await charger(nom, { LOAD_TEST_VUS: '2', LOAD_TEST_DURATION: '3s' });
    const scenario = Object.values(module.options.scenarios)[0];
    assert.equal(scenario.executor, 'constant-vus'); assert.equal(scenario.vus, 2); assert.equal(scenario.duration, '3s');
    assert.deepEqual(module.options.thresholds.checks, ['rate==1']);
    assert.deepEqual(module.options.thresholds.iterations, ['count>0']);
  });
}
test('C refuse un préflight vide puis contrôle les réponses de recherche sous charge', async () => {
  const t = await charger('03-recherche-missions');
  t.reponses.push({ body: [] }); assert.throws(() => t.module.setup(), /base vide/);
  t.reponses.push({ body: [mission] }); t.module.setup();
  t.reponses.push({ body: { error: 'panne' } }); t.module.default();
  assert.equal(t.verifications.some(c => !c.ok), true);
  assert.ok(t.appels.every(([url]) => url.endsWith('/rpc/fn_missions_publiques_recherche')));
});
test('E refuse auth sans profil, puis refuse erreur métier HTTP200 pendant la charge', async () => {
  const t = await charger('05-dashboard-concurrent');
  t.reponses.push({ body: { access_token: 'jwt-fictif' } }, { body: { ...dashboard, profil: null } });
  assert.throws(() => t.module.setup(), /profil soignant/);
  t.reponses.push({ body: { access_token: 'jwt-fictif' } }, { body: dashboard });
  assert.deepEqual(t.module.setup(), { jwt: 'jwt-fictif' });
  t.reponses.push({ body: { error: 'Non authentifié' } }); t.module.default({ jwt: 'jwt-fictif' });
  assert.equal(t.verifications.at(-1).ok, false);
});
for (const [lettre, nom] of [['D', '04-candidatures-simultanees'], ['F', '06-cron-weekly-invoicing']]) {
  test(`${lettre} échoue explicitement avant toute requête, y compris sans setup`, async () => {
    assert.throws(() => refuserScenarioNonIsole(lettre), /Aucune mutation exécutée/);
    const t = await charger(nom);
    assert.throws(() => t.module.setup(), /Aucune mutation exécutée/);
    assert.throws(() => t.module.default(), /Aucune mutation exécutée/);
    assert.equal(t.appels.length, 0);
    const summary = JSON.parse(t.module.handleSummary({})[`tests/load/results/${nom}.json`]);
    assert.equal(summary.preuve_metier, false);
  });
}
test('aucun script ne peut importer une destination de production', async () => {
  await assert.rejects(() => charger('03-recherche-missions', { STAGING_SUPABASE_URL: 'https://production.example.invalid' }), /production refusée/);
});

test('un résumé sans mesure ne fabrique pas un taux d’erreur nul', () => {
  const resume = resumeCharge({ metrics: {} }, 'C', 'rpc_recherche', { scenarios: {} });
  assert.match(resume, /Échecs HTTP mesurés \(%\) : non mesuré/);
  assert.doesNotMatch(resume, /Échecs HTTP mesurés \(%\) : 0/);
});


test('C vérifie le catalogue quantifié au préflight et pendant les recherches sans filtre', async () => {
  const t = await charger('03-recherche-missions', { LOAD_TEST_EXPECTED_MISSIONS: '100' });
  t.reponses.push({ body: [mission] }); assert.throws(() => t.module.setup(), /1\/100 missions attendues/);
  const catalogue = Array.from({ length: 100 }, (_, i) => ({ ...mission, id: `fixture-${i}`, total_count: 100 }));
  t.reponses.push({ body: catalogue }); t.module.setup();
  t.reponses.push({ body: [mission] }); t.module.default();
  assert.equal(t.verifications.find(c => c.nom === 'recherche sans filtre peuplee')?.ok, false);
});

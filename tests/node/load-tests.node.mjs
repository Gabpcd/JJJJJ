import { manifesteD } from '../../scripts/ci/candidatures-fixture-contract.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { donneesRapportCharge, resumeCharge, scenariosPourRapport } from '../load/helpers/resume.js';
import { creerOptionsCharge } from '../load/helpers/options.js';
import { lirePoolDashboard, slotDashboard, runDashboardMembre } from '../load/helpers/dashboard-pool.js';
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
const fixtureId = '10000000-0000-4000-a000-000000000001';
const dashboardFixture = { ...dashboard, profil: { profession: 'AS', prenom: 'Recette', nom: `Dashboard ${fixtureId}`, identite_verifiee: false, tous_documents_valides: false } };
const fixtureEmail = `recette-dashboard-${fixtureId}@example.invalid`;
const fixtureSession = { access_token: 'jwt-fictif', user: { id: fixtureId, email: fixtureEmail,
  app_metadata: { role: 'SOIGNANT', est_compte_test: true, is_test_playwright: true, load_fixture_kind: 'DASHBOARD', load_fixture_run: 'node-charge-1' } } };
const pool = Array.from({ length: 10 }, (_, slot) => {
  const userId = `10000000-0000-4000-a000-${String(slot + 1).padStart(12, '0')}`;
  return { slot, userId, email: `recette-dashboard-${userId}@example.invalid`, password: `Aa1!secret-fictif-du-profil-${slot}-non-publie`, runId: runDashboardMembre('node-charge-1', slot) };
});
const sessionPool = p => ({ access_token: `jwt-fictif-slot-${p.slot}`, user: { ...fixtureSession.user,
  id: p.userId, email: p.email, app_metadata: { ...fixtureSession.user.app_metadata, load_fixture_run: p.runId } } });
const dashboardPool = p => ({ ...dashboardFixture, profil: { ...dashboardFixture.profil, nom: `Dashboard ${p.userId}` } });
const preflightPool = t => { for (const p of pool) t.reponses.push({ body: sessionPool(p) }, { body: dashboardPool(p) }); };
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
  const appels = [], verifications = [], reponses = [], compteurs = [], latences = [];
  const pont = `__k6_fixture_${sequence++}`;
  globalThis.__ENV = { STAGING_SUPABASE_URL: 'https://mejpriaetwgtcstbgfid.supabase.co', STAGING_SUPABASE_ANON_KEY: 'fictif', LOAD_TEST_PASSWORD: 'fictif',
    LOAD_DASHBOARD_POOL_JSON: JSON.stringify(pool), LOAD_DASHBOARD_USER_ID: fixtureId, LOAD_DASHBOARD_EMAIL: fixtureEmail, LOAD_DASHBOARD_PASSWORD: 'secret-temporaire-fictif', LOAD_TEST_RUN_ID: 'node-charge-1', ...env };
  globalThis.__ITER = 0; globalThis.__VU = 1;
  globalThis[pont] = {
    http: { post: (...args) => {
      appels.push(args); const reponse = reponses.shift();
      assert.ok(reponse, 'Toute requête doit avoir une réponse fictive explicite');
      return { status: reponse.status ?? 200, timings: { duration: reponse.duration ?? 25 }, json: path => path ? reponse.body[path] : reponse.body };
    } },
    check: (res, checks) => {
      const resultats = Object.entries(checks).map(([nom, fn]) => ({ nom, ok: fn(res) }));
      verifications.push(...resultats); return resultats.every(r => r.ok);
    },
  };
  globalThis[pont].http.get = (url, options) => globalThis[pont].http.post(url, null, options);
  globalThis[pont].Counter = class { constructor(name) { this.name = name; } add(value, tags) { compteurs.push({ name: this.name, value, tags }); } };
  globalThis[pont].Trend = class { constructor(name) { this.name = name; } add(value) { latences.push({ name: this.name, value }); } };
  const metricsUrl = urlCode(`export const Counter = globalThis.${pont}.Counter; export const Trend = globalThis.${pont}.Trend;`);
  globalThis[pont].execution = { test: { get options() {
    assert.ok(globalThis[pont].optionsMoteur, 'Les options moteur ne sont pas accessibles au contexte init');
    return globalThis[pont].optionsMoteur;
  } } };
  const executionUrl = urlCode(`export default globalThis.${pont}.execution;`);
  const httpUrl = urlCode(`export default globalThis.${pont}.http;`);
  const k6Url = urlCode(`export const check = globalThis.${pont}.check; export function sleep() {}`);
  const auth = (await readFile(new URL('helpers/auth.js', racineLoad), 'utf8')).replaceAll("'k6/http'", JSON.stringify(httpUrl)).replaceAll("'k6'", JSON.stringify(k6Url));
  let source = await readFile(new URL(`scenarios/${nom}.js`, racineLoad), 'utf8');
  for (const [specifier, remplacement] of [
    ['k6/execution', executionUrl], ['k6/http', httpUrl], ['k6', k6Url], ['k6/metrics', metricsUrl], ['../helpers/auth.js', urlCode(auth)],
    ...['options', 'contrats', 'data', 'resume', 'dashboard-pool', 'candidatures-pool'].map(n => [`../helpers/${n}.js`, new URL(`helpers/${n}.js`, racineLoad).href]),
  ]) source = source.replaceAll(`'${specifier}'`, JSON.stringify(remplacement));
  const module = await import(urlCode(`${source}\n// ${pont}`));
  const optionsMoteur = structuredClone(module.options);
  globalThis[pont].optionsMoteur = optionsMoteur;
  return { module, appels, verifications, reponses, compteurs, latences, optionsMoteur };
}

for (const nom of ['01-inscription-bloc', '02-login-simultane', '03-recherche-missions', '05-dashboard-concurrent']) {
  test(`${nom} consomme effectivement les overrides et les seuils checks/itérations`, async () => {
    const vus = nom.startsWith('05-') ? 10 : 2;
    const { module } = await charger(nom, { LOAD_TEST_VUS: String(vus), LOAD_TEST_DURATION: '3s' });
    const scenario = Object.values(module.options.scenarios)[0];
    assert.equal(scenario.executor, 'constant-vus'); assert.equal(scenario.vus, vus); assert.equal(scenario.duration, '3s');
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
test('E10 valide tout le pool avant réseau, sans repli compte fixe ou pool incomplet', async () => {
  const corrompre = fn => { const p = structuredClone(pool); fn(p); return JSON.stringify(p); };
  for (const raw of ['', '{}', '[]', JSON.stringify(pool.slice(1)), corrompre(p => p[5] = p[0]),
    corrompre(p => p[8].runId = 'autre'), corrompre(p => p[9].email = 'playwright-soignant@jolene.app'),
    corrompre(p => p[0].password = ''), corrompre(p => p[2].slot = 12), corrompre(p => p[3].token = 'inattendu')]) {
    const t = await charger('05-dashboard-concurrent', { LOAD_DASHBOARD_POOL_JSON: raw });
    assert.throws(() => t.module.setup()); assert.equal(t.appels.length, 0);
  }
  assert.throws(() => lirePoolDashboard(JSON.stringify(pool), 'autre'));
  await assert.rejects(charger('05-dashboard-concurrent', { LOAD_TEST_VUS: '2' }), /au moins dix VUs/);
});
test('E10 refuse tout le setup si un profil aux positions 1, 5 ou 10 est incohérent', async () => {
  for (const slot of [0, 4, 9]) {
    for (const defaut of ['login', 'dashboard', 'autre-profil', 'http']) {
      const t = await charger('05-dashboard-concurrent');
      for (const p of pool.slice(0, slot)) t.reponses.push({ body: sessionPool(p) }, { body: dashboardPool(p) });
      const p = pool[slot], session = sessionPool(p);
      if (defaut === 'login') session.user.app_metadata.est_compte_test = false;
      t.reponses.push({ body: session, ...(defaut === 'http' ? { status: 429 } : {}) });
      if (!['login', 'http'].includes(defaut)) t.reponses.push({ body: defaut === 'dashboard' ? { error: 'refus' } : dashboardPool(pool[(slot + 1) % 10]) });
      assert.throws(() => t.module.setup());
      assert.equal(t.compteurs.length, 0);
      assert.equal(t.appels.length, slot * 2 + (['login', 'http'].includes(defaut) ? 1 : 2));
    }
  }
});
test('E100 utilise dix JWT distincts, dix VUs par profil, et un compteur validé par slot', async () => {
  const t = await charger('05-dashboard-concurrent', { LOAD_TEST_VUS: '100', LOAD_TEST_DURATION: '1m' });
  preflightPool(t); const data = t.module.setup();
  assert.equal(data.sessions.length, 10); assert.equal(new Set(data.sessions.map(s => s.jwt)).size, 10);
  for (const p of pool) assert.deepEqual(JSON.parse(t.appels[p.slot * 2][1]), { email: p.email, password: p.password });
  for (let vu = 1; vu <= 100; vu++) {
    globalThis.__VU = vu; const p = pool[slotDashboard(vu)];
    t.reponses.push({ body: dashboardPool(p) }); t.module.default(data);
    assert.equal(t.appels.at(-1)[2].headers.Authorization, `Bearer jwt-fictif-slot-${p.slot}`);
  }
  for (let slot = 0; slot < 10; slot++) {
    assert.equal(t.compteurs.filter(c => c.tags.slot === String(slot)).length, 10);
    assert.equal(t.latences.filter(c => c.name === `dashboard_duree_profil_${slot}`).length, 10);
    assert.deepEqual(t.module.options.thresholds[`dashboard_reponses_profil{slot:${slot}}`], ['count>0']);
  }
  assert.equal(t.verifications.every(c => c.ok), true);
  assert.deepEqual(t.module.options.thresholds['http_req_duration{name:rpc_dashboard}'], ['p(95)<2000', 'p(99)<3500']);
});
test('le canari de chaque profil refuse le voisin, un profil validé et une erreur HTTP200 sans incrémenter le compteur', async () => {
  const t = await charger('05-dashboard-concurrent'); preflightPool(t); const data = t.module.setup();
  for (let slot = 0; slot < 10; slot++) {
    globalThis.__VU = slot + 1;
    for (const body of [dashboardPool(pool[(slot + 1) % 10]), { error: 'refus' },
      { ...dashboardPool(pool[slot]), profil: { ...dashboardPool(pool[slot]).profil, identite_verifiee: true } }]) {
      t.reponses.push({ body }); t.module.default(data); assert.equal(t.verifications.at(-1).ok, false);
    }
  }
  assert.equal(t.compteurs.length, 0);
  assert.equal(t.latences.length, 30, 'Les latences des réponses refusées restent mesurées.');
  assert.throws(() => t.module.default({ sessions: [] }));
  for (const vu of [0, -1, 1.5, undefined]) assert.throws(() => slotDashboard(vu));
});
for (const [lettre, nom] of [['D', '04-candidatures-simultanees'], ['F', '06-cron-weekly-invoicing']]) {
  test(`${lettre} échoue explicitement avant toute requête, y compris sans setup`, async () => {
    assert.throws(() => refuserScenarioNonIsole(lettre), /Aucune mutation exécutée/);
    const t = await charger(nom);
    assert.throws(() => t.module.setup(), lettre === 'D' ? /Banc D2 non préparé/ : /Aucune mutation exécutée/);
    assert.throws(() => t.module.default(), lettre === 'D' ? /hors borne ou setup absent/ : /Aucune mutation exécutée/);
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

test('les quantiles p50/p95/p99 sont exportés sans déplacer les seuils ni exclure le démarrage', () => {
  const seuils = { 'http_req_duration{name:rpc_dashboard}': ['p(95)<2000', 'p(99)<3500'] };
  const options = creerOptionsCharge('charge', defaut, seuils, { LOAD_TEST_VUS: '100', LOAD_TEST_DURATION: '1m' });
  for (const quantile of ['p(50)', 'p(95)', 'p(99)']) assert.ok(options.summaryTrendStats.includes(quantile));
  assert.deepEqual(options.thresholds['http_req_duration{name:rpc_dashboard}'], seuils['http_req_duration{name:rpc_dashboard}']);
  assert.deepEqual(options.scenarios.charge, { executor: 'constant-vus', vus: 100, duration: '1m', gracefulStop: '15s' });
  const resume = resumeCharge({ metrics: { 'http_req_duration{name:rpc_dashboard}': { values: { med: 111.1, 'p(95)': 153.1, 'p(99)': 4123.7 } } } }, 'E', 'rpc_dashboard', options);
  assert.match(resume, /p50 \/ p95 \/ p99 \(ms\) : 111 \/ 153 \/ 4124/);
});

test('les rapports conservent les preuves agrégées et excluent les données de setup ou futurs champs inconnus', async () => {
  const secret = 'session-fictive-a-ne-jamais-publier';
  const data = {
    metrics: { iterations: { values: { count: 42 } } },
    root_group: { checks: [{ name: 'dashboard 200', passes: 42, fails: 0 }], groups: [] },
    state: { testRunDurationMs: 60000 },
    options: { summaryTrendStats: ['p(50)', 'p(95)', 'p(99)'], summaryTimeUnit: 'ms', noColor: true, env: { PASSWORD: secret } },
    setup_data: { jwt: secret, userId: fixtureId, sessions: pool.map(p => ({ jwt: secret + p.slot, password: p.password })) },
    futur_champ_runtime: { authorization: secret },
  };
  const attendu = { metrics: data.metrics, root_group: data.root_group, state: data.state,
    options: { summaryTrendStats: data.options.summaryTrendStats, summaryTimeUnit: 'ms', noColor: true } };
  assert.deepEqual(donneesRapportCharge(data), attendu);
  for (const nom of ['01-inscription-bloc', '02-login-simultane', '03-recherche-missions', '04-candidatures-simultanees', '05-dashboard-concurrent', '06-cron-weekly-invoicing']) {
    const { module } = await charger(nom);
    const sorties = module.handleSummary(data);
    assert.equal(JSON.stringify(sorties).includes(secret), false, nom);
    for (const p of pool) assert.equal(JSON.stringify(sorties).includes(p.password), false, nom);
    const rapport = JSON.parse(sorties[`tests/load/results/${nom}.json`]);
    const indisponible = nom.startsWith('06-') ? 'F' : null;
    assert.deepEqual(rapport, indisponible ? { ...attendu, preuve_metier: false, scenario_indisponible: indisponible } : nom.startsWith('04-') ? { ...attendu, profils_attendus:2, preuve_metier:false, verification_sql_et_cleanup_requis:true } : nom.startsWith('05-') ? { ...attendu, profils_attendus: 10 } : attendu, nom);
  }
  assert.equal(data.setup_data.jwt, secret, 'La session en mémoire ne doit pas être modifiée par le rapport');
});


test('C vérifie le catalogue quantifié au préflight et pendant les recherches sans filtre', async () => {
  const t = await charger('03-recherche-missions', { LOAD_TEST_EXPECTED_MISSIONS: '100' });
  t.reponses.push({ body: [mission] }); assert.throws(() => t.module.setup(), /1\/100 missions attendues/);
  const catalogue = Array.from({ length: 100 }, (_, i) => ({ ...mission, id: `fixture-${i}`, total_count: 100 }));
  t.reponses.push({ body: catalogue }); t.module.setup();
  t.reponses.push({ body: [mission] }); t.module.default();
  assert.equal(t.verifications.find(c => c.nom === 'recherche sans filtre peuplee')?.ok, false);
});


test('résumé C/E : options moteur conservées lorsque k6 remplace les scénarios exportés par un objet natif vide', async () => {
  for (const nom of ['03-recherche-missions','05-dashboard-concurrent']) {
    const t=await charger(nom,{LOAD_TEST_VUS:'100',LOAD_TEST_DURATION:'1m'});
    const seuils=structuredClone(t.module.options.thresholds);
    // Le moteur applique ses valeurs consolidées ; le rapport ne doit pas
    // reconstruire les paramètres depuis __ENV ou l'export JS réinjecté.
    const moteur=Object.values(t.optionsMoteur.scenarios)[0];
    moteur.duration='1m0s';moteur.gracefulStop='15s';
    const attendu=structuredClone(t.optionsMoteur.scenarios);
    t.module.options.scenarios={};
    assert.equal(JSON.stringify(t.module.options.scenarios),'{}');
    const rapport=t.module.handleSummary({metrics:{}}).stdout;
    const ligne=rapport.split('\n').find(l=>l.startsWith('Configuration effective : '));
    assert.deepEqual(JSON.parse(ligne.slice('Configuration effective : '.length)),attendu,nom);
    assert.deepEqual(t.module.options.thresholds,seuils);assert.equal(t.appels.length,0);
  }
});
test('résumé : la projection des options moteur exclut env, tags et secrets imbriqués sans modifier les sources', () => {
  const secret='canari-token-password-options';
  const options={env:{token:secret},scenarios:{dashboard_concurrent:{executor:'constant-vus',vus:100,duration:'1m0s',gracefulStop:'15s',
    env:{password:secret},tags:{session:secret},options:{browser:{secret}},futur_champ:secret},
    rampe:{executor:'ramping-vus',startVUs:0,stages:[{duration:'20s',target:100,env:{password:secret}}]}}};
  const avant=structuredClone(options);const rapport=resumeCharge({metrics:{}},'E','rpc_dashboard',options);
  assert.doesNotMatch(rapport,new RegExp(secret));
  assert.deepEqual(scenariosPourRapport(options),{dashboard_concurrent:{executor:'constant-vus',vus:100,duration:'1m0s',gracefulStop:'15s'},
    rampe:{executor:'ramping-vus',startVUs:0,stages:[{duration:'20s',target:100}]}});
  assert.deepEqual(options,avant);
  assert.match(resumeCharge({metrics:{}},'E','rpc_dashboard',{}),/Configuration effective : non disponible/);
});

const dManifeste=manifesteD('node-charge-1','2026-10-14');
const dLot={...dManifeste,identites:dManifeste.membres.map((a,i)=>({...a,password:'Aa1!canari-D2-motdepasse-ne-pas-sortir-'+i}))};
const dSession=a=>({access_token:'jeton-D2-'+a.slot,user:{id:a.userId,email:a.email,app_metadata:{role:a.role,est_compte_test:true,is_test_playwright:true,load_fixture_kind:'CANDIDATURES_D2',load_fixture_run:dLot.runId,...(a.slot===2?{etablissement_id:a.userId}:{})}}});
function dPreflight(t){
  for(const a of dLot.identites)t.reponses.push({body:dSession(a)});
  for(const a of dLot.identites.slice(0,2))t.reponses.push(
    {body:[{id:a.userId,profession:'AS',type_exercice:'SALARIE',est_compte_test:true,identite_verifiee:false,tous_documents_valides:false}]},
    {body:[{id:dLot.missionId,etablissement_id:dLot.identites[2].userId,statut:'OUVERTE',est_urgente:false,soignant_assigne_id:null,type_contrat_recherche:'SALARIE',mode_attribution:'CANDIDATURE'}]},
    {body:[{id:dLot.creneauId,debut:dLot.debut,fin:dLot.fin,type_creneau:'PREVISIONNEL',est_pause:false}]},{body:[]});
}
const dRow=i=>({id:`10000000-0000-4000-a000-00000000000${i+1}`,mission_id:dLot.missionId,soignant_id:dLot.identites[i].userId,statut:'EN_ATTENTE',type_contrat_choisi:'SALARIE',message:dLot.marker});
test('D2 : pool invalide refusé avant Auth ; volume fixe et absence de setup fermée',async()=>{
  for(const change of [p=>p.identites.pop(),p=>p.identites[1]=p.identites[0],p=>p.identites[0].email='playwright-soignant@jolene.app',p=>p.runId='autre',p=>p.fin=p.debut]){
    const p=structuredClone(dLot);change(p);const t=await charger('04-candidatures-simultanees',{LOAD_CANDIDATURES_JSON:JSON.stringify(p)});assert.throws(()=>t.module.setup());assert.equal(t.appels.length,0);
  }
  for(const env of [{LOAD_TEST_VUS:'50'},{LOAD_TEST_DURATION:'1m'}])await assert.rejects(charger('04-candidatures-simultanees',env),/aucun override/);
});
test('D2 : chaque préflight identité/profil/mission/planning/compteur vide bloque avant candidature',async()=>{
  for(const index of [0,1,2,3,4,5,6,7,8,9,10]){
    const t=await charger('04-candidatures-simultanees',{LOAD_CANDIDATURES_JSON:JSON.stringify(dLot)});dPreflight(t);t.reponses[index]={body:{error:'canari-secret-provider'},status:index<3?429:200};assert.throws(()=>t.module.setup());assert.equal(t.appels.some(([u])=>u.includes('/rpc/fn_confirmer')),false);
  }
});
test('D2 : deux POST frontend exacts, deux lignes propres, établissement voit deux, pas de secret résumé',async()=>{
  const t=await charger('04-candidatures-simultanees',{LOAD_CANDIDATURES_JSON:JSON.stringify(dLot)});dPreflight(t);const data=t.module.setup();
  assert.equal(JSON.stringify(data).includes(dLot.identites[0].password),false);
  for(let i=0;i<2;i++){
    globalThis.__VU=i+1;t.reponses.push({body:{success:true,candidature_id:dRow(i).id,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:true}},{body:[dRow(i)]});t.module.default(data);
  }
  t.reponses.push({body:[dRow(0),dRow(1)]});t.module.teardown(data);
  assert.equal(t.compteurs.length,2);assert.equal(t.verifications.every(v=>v.ok),true);
  const posts=t.appels.filter(([u])=>u.includes('/rpc/fn_confirmer'));assert.equal(posts.length,2);
  for(const [,body]of posts)assert.deepEqual(JSON.parse(body),{p_mission_id:dLot.missionId,p_action:'POSTULER',p_creneaux_confirmes:[{debut:dLot.debut,fin:dLot.fin}],p_message:dLot.marker,p_choix_contrat:null,p_candidature_id:null});
  globalThis.__ITER=1;assert.throws(()=>t.module.default(data));globalThis.__ITER=0;globalThis.__VU=3;assert.throws(()=>t.module.default(data));
  const rapport=JSON.stringify(t.module.handleSummary({setup_data:data,metrics:{}}));assert.equal(rapport.includes('jeton-D2'),false);assert.equal(rapport.includes(dLot.marker),false);
});
test('D2 : faux 200, ligne autre soignant et total établissement vide ne peuvent réussir',async()=>{
  for(const cas of ['error','autre']){
    const t=await charger('04-candidatures-simultanees',{LOAD_CANDIDATURES_JSON:JSON.stringify(dLot)});dPreflight(t);const data=t.module.setup();globalThis.__VU=1;
    t.reponses.push({body:cas==='error'?{error:'refus'}:{success:true,candidature_id:dRow(0).id,choix_contrat:'SALARIE',profession_requise:'AS',docs_a_completer:true}});
    if(cas==='autre')t.reponses.push({body:[dRow(1)]});t.module.default(data);assert.equal(t.compteurs.length,0);assert.ok(t.verifications.some(v=>!v.ok));
    t.reponses.push({body:[]});assert.throws(()=>t.module.teardown(data));
  }
});

test('D2 accepte les quatre variantes UUID v4 serveur sans relâcher propriétaire/mission',async()=>{
 const {candidatureDValide}=await import('../load/helpers/candidatures-pool.js');
 for(const variant of ['8','9','a','b']){
  const row={...dRow(0),id:`10000000-0000-4000-${variant}000-000000000001`};
  assert.equal(candidatureDValide(row,dLot,dLot.identites[0],row.id),true);
  assert.equal(candidatureDValide(row,dLot,dLot.identites[1],row.id),false);
  assert.equal(candidatureDValide({...row,mission_id:dRow(1).id},dLot,dLot.identites[0],row.id),false);
 }
 for(const id of ['10000000-0000-4000-c000-000000000001','pas-un-uuid',dRow(0).id.replace('-4000-','-1000-')])assert.equal(candidatureDValide({...dRow(0),id},dLot,dLot.identites[0],id),false);
});

import k6Execution from 'k6/execution';
import { donneesRapportCharge, resumeCharge } from '../helpers/resume.js';
import { creerOptionsCharge } from '../helpers/options.js';
/**
 * Scenario E — Dashboard concurrent.
 *
 * 100 VUs ouvrent dashboard soignant simultanément (RPC fn_dashboard_soignant_complet
 * qui calcule stats + missions disponibles + alertes).
 *
 * Cible : 100% succès, p95 < 2s.
 *
 * Dix identités AS minimales éphémères, chacune affectée à dix VUs sur E100.
 * Les mots de passe transitent via LOAD_DASHBOARD_POOL_JSON privé ; aucun
 * identifiant/secret ne devient un tag ou un champ de résumé.
 * Profils non vérifiés sans historique : aucune capacité nationale déduite.
 */

import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';
import { lirePoolDashboard, NOMBRE_PROFILS_DASHBOARD, slotDashboard } from '../helpers/dashboard-pool.js';
import { check, sleep } from 'k6';
import { SUPABASE_URL, authedHeaders, loginDashboardFixture } from '../helpers/auth.js';
import { dashboardFixtureValide, exigerDashboardMetier } from '../helpers/contrats.js';

const reponsesParProfil = new Counter('dashboard_reponses_profil');
// Un échec isolé doit rester explicable sans publier réponse, compte ou jeton.
// Classes fixes : aucun message fournisseur ni statut libre dans les métriques.
const statutsDiagnostic = [400, 401, 403, 404, 408, 409, 422, 429, 500, 502, 503, 504];
const classesDiagnostic = ['transport', 'contrat_200', 'autre_statut', ...statutsDiagnostic.map(s => `http_${s}`)];
const echecsDiagnostic = Object.fromEntries(classesDiagnostic.map(c => [c, new Counter(`dashboard_echec_${c}`)]));
export function classerEchecDashboard(statut) {
  if (statut === 0) return 'transport';
  if (statut === 200) return 'contrat_200';
  return statutsDiagnostic.includes(statut) ? `http_${statut}` : 'autre_statut';
}
const latencesParProfil = Array.from({ length: NOMBRE_PROFILS_DASHBOARD }, (_, slot) =>
  new Trend(`dashboard_duree_profil_${slot}`, true));
const seuilsProfils = Object.fromEntries(Array.from({ length: NOMBRE_PROFILS_DASHBOARD }, (_, slot) =>
  [`dashboard_reponses_profil{slot:${slot}}`, ['count>0']]));

export const options = creerOptionsCharge('dashboard_concurrent', {
  executor: 'ramping-vus',
  startVUs: 0,
  stages: [
    { duration: '20s', target: 100 },
    { duration: '1m', target: 100 },
    { duration: '10s', target: 0 },
  ],
  gracefulRampDown: '15s',
}, {
  ...seuilsProfils,
  'http_req_failed{name:rpc_dashboard}': ['rate<0.01'],
  'http_req_duration{name:rpc_dashboard}': ['p(95)<2000', 'p(99)<3500'],
}, __ENV);

const execution = options.scenarios.dashboard_concurrent;
const vus = execution.vus || Math.max(...execution.stages.map(s => s.target));
if (vus < NOMBRE_PROFILS_DASHBOARD) throw new Error('E10 exige au moins dix VUs pour mesurer chaque profil.');

export function setup() {
  // Valider le lot entier avant le premier login. Aucun repli vers un compte fixe.
  const pool = lirePoolDashboard(__ENV.LOAD_DASHBOARD_POOL_JSON, __ENV.LOAD_TEST_RUN_ID);
  const sessions = pool.map(identite => {
    const session = loginDashboardFixture(identite);
    const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`, '{}', {
      headers: authedHeaders(session.access_token), tags: { name: 'dashboard_preflight' }, timeout: '15s',
    });
    if (res.status !== 200) throw new Error(`Préflight E : dashboard indisponible (HTTP ${res.status}).`);
    const dashboard = res.json();
    exigerDashboardMetier(dashboard);
    if (!dashboardFixtureValide(dashboard, session.user.id)) throw new Error('Préflight E : profil AS minimal du run attendu.');
    return { jwt: session.access_token, userId: session.user.id, slot: identite.slot };
  });
  console.log('Préflight E : dix profils AS minimaux distincts contrôlés ; aucune mutation métier pendant la charge.');
  return { sessions };
}

export default function (data) {
  const slot = slotDashboard(__VU);
  const session = data?.sessions?.[slot];
  if (data?.sessions?.length !== NOMBRE_PROFILS_DASHBOARD || session?.slot !== slot || !session.jwt) {
    throw new Error('Pool de sessions E10 incomplet.');
  }
  const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`, '{}', {
    headers: authedHeaders(session.jwt), tags: { name: 'rpc_dashboard' }, timeout: '15s',
  });
  // Latence de toutes les réponses, même erronées ; dix séries bornées sans
  // identité dans leur nom. Les seuils historiques agrégés restent inchangés.
  latencesParProfil[slot].add(res.timings.duration);
  const valide = check(res, {
    'dashboard 200': r => r.status === 200,
    'dashboard profil et contrat metier valides': r => {
      try { return dashboardFixtureValide(r.json(), session.userId); } catch { return false; }
    },
  });
  if (valide) reponsesParProfil.add(1, { slot: String(slot) });
  else echecsDiagnostic[classerEchecDashboard(res.status)].add(1);
  sleep(0.5);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'E — Dashboard concurrent'),
    'tests/load/results/05-dashboard-concurrent.json': JSON.stringify({ ...donneesRapportCharge(data), profils_attendus: NOMBRE_PROFILS_DASHBOARD }, null, 2),
  };
}

function textSummary(data, label) {
  return resumeCharge(data, label, 'rpc_dashboard', k6Execution.test.options) + '\nDix profils minimaux attendus ; chaque compteur dashboard_reponses_profil{slot:0..9} doit être positif.\n';
}

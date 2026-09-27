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
 * Stratégie : 1 setup() login du profil AS minimal éphémère de ce run.
 * Son JWT est réutilisé pour tous les VUs : une seule identité et aucun dossier
 * vérifié. Cette mesure ne représente pas 100 utilisateurs distincts.
 *
 * Lancer :
 *   k6 run tests/load/scenarios/05-dashboard-concurrent.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=... \
 *     -e LOAD_DASHBOARD_EMAIL=... -e LOAD_DASHBOARD_PASSWORD=... \
 *     -e LOAD_DASHBOARD_USER_ID=... -e LOAD_TEST_RUN_ID=...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { SUPABASE_URL, authedHeaders, loginDashboardFixture } from '../helpers/auth.js';
import { dashboardFixtureValide, exigerDashboardMetier } from '../helpers/contrats.js';

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
  'http_req_failed{name:rpc_dashboard}': ['rate<0.01'],
  'http_req_duration{name:rpc_dashboard}': ['p(95)<2000', 'p(99)<3500'],
}, __ENV);

export function setup() {
  const session = loginDashboardFixture();
  const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`, '{}', {
    headers: authedHeaders(session.access_token), tags: { name: 'dashboard_preflight' }, timeout: '15s',
  });
  if (res.status !== 200) throw new Error(`Préflight E : dashboard indisponible (HTTP ${res.status}).`);
  const dashboard = res.json();
  exigerDashboardMetier(dashboard);
  if (!dashboardFixtureValide(dashboard, session.user.id)) throw new Error('Préflight E : profil AS minimal du run attendu.');
  console.log('Préflight E : profil soignant et structure métier présents ; charge sur un seul compte, aucune mutation métier.');
  return { jwt: session.access_token, userId: session.user.id };
}

export default function (data) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`;
  const res = http.post(url, '{}', {
    headers: authedHeaders(data.jwt),
    tags: { name: 'rpc_dashboard' },
    timeout: '15s',
  });
  check(res, {
    'dashboard 200': (r) => r.status === 200,
    'dashboard profil et contrat metier valides': (r) => {
      try { return dashboardFixtureValide(r.json(), data.userId); } catch { return false; }
    },
  });
  sleep(0.5);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'E — Dashboard concurrent'),
    'tests/load/results/05-dashboard-concurrent.json': JSON.stringify(donneesRapportCharge(data), null, 2),
  };
}

function textSummary(data, label) {
  return resumeCharge(data, label, 'rpc_dashboard', options);
}

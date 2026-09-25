import { resumeCharge } from '../helpers/resume.js';
import { creerOptionsCharge } from '../helpers/options.js';
/**
 * Scenario E — Dashboard concurrent.
 *
 * 100 VUs ouvrent dashboard soignant simultanément (RPC fn_dashboard_soignant_complet
 * qui calcule stats + missions disponibles + alertes).
 *
 * Cible : 100% succès, p95 < 2s.
 *
 * Stratégie : 1 setup() login soignant test fixe → réutilise le JWT pour tous
 * les VUs. C'est représentatif d'un soignant qui rafraîchit régulièrement,
 * ou de plusieurs soignants similaires (la RPC fait le même travail).
 *
 * Lancer :
 *   k6 run tests/load/scenarios/05-dashboard-concurrent.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=... \
 *     -e LOAD_TEST_PASSWORD=...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { SUPABASE_URL, authedHeaders, loginTestAccount } from '../helpers/auth.js';
import { dashboardValide, exigerDashboardMetier } from '../helpers/contrats.js';

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
  const session = loginTestAccount('SOIGNANT');
  if (!session?.access_token) {
    throw new Error('setup: login playwright-soignant échoué');
  }
  const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`, '{}', {
    headers: authedHeaders(session.access_token), tags: { name: 'dashboard_preflight' }, timeout: '15s',
  });
  if (res.status !== 200) throw new Error(`Préflight E : dashboard indisponible (HTTP ${res.status}).`);
  exigerDashboardMetier(res.json());
  console.log('Préflight E : profil soignant et structure métier présents ; charge sur un seul compte, aucune mutation métier.');
  return { jwt: session.access_token };
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
      try { return dashboardValide(r.json()); } catch { return false; }
    },
  });
  sleep(0.5);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'E — Dashboard concurrent'),
    'tests/load/results/05-dashboard-concurrent.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, label) {
  return resumeCharge(data, label, 'rpc_dashboard', options);
}

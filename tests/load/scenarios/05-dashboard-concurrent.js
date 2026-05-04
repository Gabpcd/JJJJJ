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

export const options = {
  scenarios: {
    dashboard_concurrent: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '20s', target: 100 },
        { duration: '1m', target: 100 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    'http_req_failed{name:rpc_dashboard}': ['rate<0.01'],
    'http_req_duration{name:rpc_dashboard}': ['p(95)<2000', 'p(99)<3500'],
  },
};

export function setup() {
  const session = loginTestAccount('SOIGNANT');
  if (!session?.access_token) {
    throw new Error('setup: login playwright-soignant échoué');
  }
  return { jwt: session.access_token };
}

export default function (data) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/fn_dashboard_soignant_complet`;
  const res = http.post(url, '{}', {
    headers: authedHeaders(data.jwt),
    tags: { name: 'rpc_dashboard' },
  });
  check(res, {
    'dashboard 200': (r) => r.status === 200,
    'dashboard returns object': (r) => {
      try { return typeof r.json() === 'object'; } catch { return false; }
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
  const m = data.metrics;
  const dur = m['http_req_duration{name:rpc_dashboard}'] || m.http_req_duration;
  const fail = m['http_req_failed{name:rpc_dashboard}'] || m.http_req_failed;
  return [
    '',
    `=== Scenario ${label} ===`,
    `Iterations  : ${m.iterations?.values?.count ?? 'n/a'}`,
    `Req/s       : ${m.http_reqs?.values?.rate?.toFixed(2) ?? 'n/a'}`,
    `Failure %   : ${((fail?.values?.rate ?? 0) * 100).toFixed(2)}`,
    `p50/p95/p99 : ${dur?.values?.['p(50)']?.toFixed(0)}/${dur?.values?.['p(95)']?.toFixed(0)}/${dur?.values?.['p(99)']?.toFixed(0)} ms`,
    '',
  ].join('\n');
}

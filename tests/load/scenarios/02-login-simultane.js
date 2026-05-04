/**
 * Scenario B — Login simultané.
 *
 * 50 VUs login simultané. On ne peut pas re-login le même compte 50x sans
 * créer 50 sessions distinctes côté Supabase, mais l'auth gère ça (pas de
 * limite de sessions concurrentes par user, juste rotation de refresh token).
 *
 * Cible : 100% succès, p99 < 2s.
 *
 * Stratégie : 50 VUs login en boucle sur un pool de comptes test seedés
 * (playwright-soignant + playwright-etab + comptes seedés en pre-step si
 * besoin). Pour la version minimale, on utilise les 2 comptes fixes en
 * round-robin → ça crée 50 sessions JWT pour 2 users.
 *
 * Lancer :
 *   k6 run tests/load/scenarios/02-login-simultane.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=... \
 *     -e LOAD_TEST_PASSWORD=...
 */

import { sleep } from 'k6';
import { login } from '../helpers/auth.js';

const POOL = [
  { email: 'playwright-soignant@jolene.app' },
  { email: 'playwright-etab@jolene.app' },
];

export const options = {
  scenarios: {
    login_simultane: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '15s', target: 50 },
        { duration: '1m', target: 50 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    'http_req_failed{name:auth_login}': ['rate<0.01'], // 100% succès attendu
    'http_req_duration{name:auth_login}': ['p(95)<1000', 'p(99)<2000'],
  },
};

export default function () {
  const password = __ENV.LOAD_TEST_PASSWORD;
  if (!password) throw new Error('LOAD_TEST_PASSWORD requis');
  const account = POOL[__VU % POOL.length];
  login(account.email, password);
  sleep(0.5); // pacing : ~2 req/s/VU = 100 req/s total
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'B — Login simultané'),
    'tests/load/results/02-login-simultane.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, label) {
  const m = data.metrics;
  const dur = m['http_req_duration{name:auth_login}'] || m.http_req_duration;
  const fail = m['http_req_failed{name:auth_login}'] || m.http_req_failed;
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

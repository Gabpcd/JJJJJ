/**
 * Scenario A — Inscription en bloc (cas viral post LinkedIn).
 *
 * 100 VUs simultanés POST /auth/v1/signup avec emails uniques.
 * Cible : 95%+ succès, p99 < 5s.
 *
 * Notes :
 * - On utilise /auth/v1/signup direct (pas l'edge fn register-soignant qui
 *   a un rate limit 5/IP/10min, incompatible avec 100 VUs depuis 1 runner).
 * - L'edge fn fait des choses additionnelles (vérif RPPS, profil INSERT,
 *   serie onboarding) — testées séparément en flow E2E.
 * - Ce scenario mesure la capacité brute de l'auth Supabase (gotrue).
 *
 * Lancer :
 *   k6 run tests/load/scenarios/01-inscription-bloc.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=...
 */

import { sleep } from 'k6';
import { signup } from '../helpers/auth.js';
import { uniqueEmail, strongPassword, soignantMetadata } from '../helpers/data.js';

export const options = {
  scenarios: {
    inscription_bloc: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 }, // ramp-up à 100 VUs
        { duration: '1m', target: 100 },  // plateau 1 min
        { duration: '15s', target: 0 },   // ramp-down
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    // Cible : 95%+ succès (5% rate limit acceptable pour Supabase)
    'http_req_failed{name:auth_signup}': ['rate<0.05'],
    // p99 < 5s (auth signup peut être lent : INSERT auth.users + trigger profil)
    'http_req_duration{name:auth_signup}': ['p(95)<3000', 'p(99)<5000'],
  },
};

export default function () {
  const email = uniqueEmail('inscr');
  const result = signup(email, strongPassword(), soignantMetadata());
  if (result?.rateLimited) {
    // Acceptable — Supabase auth a son propre rate limiter, attendre 1s
    sleep(1);
  } else {
    sleep(0.1);
  }
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data),
    'tests/load/results/01-inscription-bloc.json': JSON.stringify(data, null, 2),
  };
}

// Inline textSummary pour éviter dépendance externe
function textSummary(data) {
  const m = data.metrics;
  const reqDur = m['http_req_duration{name:auth_signup}'] || m.http_req_duration;
  const reqFail = m['http_req_failed{name:auth_signup}'] || m.http_req_failed;
  const lines = [
    '',
    '=== Scenario A — Inscription en bloc ===',
    `Total iterations : ${m.iterations?.values?.count ?? 'n/a'}`,
    `Requests/sec     : ${m.http_reqs?.values?.rate?.toFixed(2) ?? 'n/a'}`,
    `Failure rate     : ${((reqFail?.values?.rate ?? 0) * 100).toFixed(2)}%`,
    `Latence p50      : ${reqDur?.values?.['p(50)']?.toFixed(0) ?? 'n/a'} ms`,
    `Latence p95      : ${reqDur?.values?.['p(95)']?.toFixed(0) ?? 'n/a'} ms`,
    `Latence p99      : ${reqDur?.values?.['p(99)']?.toFixed(0) ?? 'n/a'} ms`,
    '',
  ];
  return lines.join('\n');
}

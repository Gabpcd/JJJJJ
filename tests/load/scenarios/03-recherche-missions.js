/**
 * Scenario C — Recherche missions massive.
 *
 * 200 VUs cherchent simultanément avec filtres variés via la RPC publique
 * fn_missions_publiques_recherche(p_profession, p_ville). Pas d'auth requise
 * (RPC SECURITY DEFINER ouverte aux anon).
 *
 * Cible : 100% succès, p95 < 1s.
 *
 * Lancer :
 *   k6 run tests/load/scenarios/03-recherche-missions.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { SUPABASE_URL, anonHeaders } from '../helpers/auth.js';
import { randomFilters } from '../helpers/data.js';

export const options = {
  scenarios: {
    recherche_missions: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 200 },
        { duration: '1m30s', target: 200 },
        { duration: '15s', target: 0 },
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    'http_req_failed{name:rpc_recherche}': ['rate<0.01'],
    'http_req_duration{name:rpc_recherche}': ['p(50)<400', 'p(95)<1000', 'p(99)<2000'],
  },
};

export default function () {
  const url = `${SUPABASE_URL}/rest/v1/rpc/fn_missions_publiques_recherche`;
  const filters = randomFilters();
  // Nettoyer les null pour ne pas envoyer "p_profession":null si non utilisé
  const body = {};
  if (filters.p_profession) body.p_profession = filters.p_profession;
  if (filters.p_ville) body.p_ville = filters.p_ville;

  const res = http.post(url, JSON.stringify(body), {
    headers: anonHeaders(),
    tags: { name: 'rpc_recherche' },
  });
  check(res, {
    'recherche 200': (r) => r.status === 200,
    'recherche array body': (r) => {
      try { return Array.isArray(r.json()); } catch { return false; }
    },
  });
  sleep(0.3);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'C — Recherche missions massive'),
    'tests/load/results/03-recherche-missions.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, label) {
  const m = data.metrics;
  const dur = m['http_req_duration{name:rpc_recherche}'] || m.http_req_duration;
  const fail = m['http_req_failed{name:rpc_recherche}'] || m.http_req_failed;
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

/**
 * Scenario F — Cron weekly invoicing sur 500 missions terminées.
 *
 * Mesure le temps total et le taux d'échec du cron `weekly-invoicing-cron`
 * quand 500 missions sont à facturer.
 *
 * Cible : < 10 min pour 500 missions, 0% échec.
 *
 * Pré-requis :
 * - 500 missions [loadtest] TERMINEE seedées (workflow deploy-staging
 *   avec input seed_load_test_data=true, ou exécution manuelle de
 *   tests/load/seed/seed-staging.sql).
 *
 * Stratégie : 1 seul VU, 1 itération qui invoque le cron via service_role
 * et mesure la durée. Pas de concurrence (le cron est mono-instance par
 * design — pg_cron schedule unique).
 *
 * Lancer :
 *   k6 run tests/load/scenarios/06-cron-weekly-invoicing.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=... \
 *     -e STAGING_SUPABASE_SERVICE_ROLE_KEY=...
 */

import http from 'k6/http';
import { check } from 'k6';
import { SUPABASE_URL, SERVICE_ROLE_KEY } from '../helpers/auth.js';

export const options = {
  scenarios: {
    cron_weekly_invoicing: {
      executor: 'per-vu-iterations',
      vus: 1,
      iterations: 1,
      maxDuration: '15m', // cible 10 min, on tolère 15 max
    },
  },
  thresholds: {
    'http_req_failed{name:cron_invoke}': ['rate==0'],
    'http_req_duration{name:cron_invoke}': ['p(100)<600000'], // 10 min en ms
  },
};

export default function () {
  if (!SERVICE_ROLE_KEY) {
    throw new Error('STAGING_SUPABASE_SERVICE_ROLE_KEY requis pour invoke edge fn cron');
  }

  // Compter les missions à facturer AVANT (sanity check)
  const beforeRes = http.get(
    `${SUPABASE_URL}/rest/v1/missions?statut=eq.TERMINEE&intitule=like.${encodeURIComponent('[loadtest]%')}&select=id`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } },
  );
  const before = beforeRes.status === 200 ? beforeRes.json().length : 0;
  console.log(`Missions [loadtest] TERMINEE avant cron : ${before}`);

  // Invoke le cron
  const start = Date.now();
  const res = http.post(
    `${SUPABASE_URL}/functions/v1/weekly-invoicing-cron`,
    '{}',
    {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      tags: { name: 'cron_invoke' },
      timeout: '15m',
    },
  );
  const elapsed = Date.now() - start;
  console.log(`Cron weekly-invoicing terminé en ${(elapsed / 1000).toFixed(1)}s (status ${res.status})`);

  check(res, {
    'cron 200': (r) => r.status === 200,
    'cron < 10min': () => elapsed < 600_000,
  });

  // Compter les factures générées
  const afterRes = http.get(
    `${SUPABASE_URL}/rest/v1/factures_honoraires?select=id&limit=1000`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } },
  );
  const factures = afterRes.status === 200 ? afterRes.json().length : 0;
  console.log(`Factures total après cron : ${factures}`);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'F — Cron weekly invoicing'),
    'tests/load/results/06-cron-weekly-invoicing.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, label) {
  const m = data.metrics;
  const dur = m['http_req_duration{name:cron_invoke}'] || m.http_req_duration;
  const fail = m['http_req_failed{name:cron_invoke}'] || m.http_req_failed;
  return [
    '',
    `=== Scenario ${label} ===`,
    `Iterations  : ${m.iterations?.values?.count ?? 'n/a'}`,
    `Failure %   : ${((fail?.values?.rate ?? 0) * 100).toFixed(2)}`,
    `Durée totale: ${dur?.values?.max?.toFixed(0)} ms (${(dur?.values?.max / 1000).toFixed(1)} s)`,
    '',
  ].join('\n');
}

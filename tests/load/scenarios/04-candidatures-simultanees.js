/**
 * Scenario D — 50 candidatures simultanées sur 1 mission populaire.
 *
 * Test de race condition : 50 soignants postulent EN MÊME TEMPS sur 1 mission.
 * Vérifie qu'aucune candidature dupliquée n'est créée (contrainte UNIQUE
 * (mission_id, soignant_id) sur la table candidatures doit tenir).
 *
 * Cible : toutes créées en EN_ATTENTE OU rejetées proprement, AUCUN doublon
 * en DB.
 *
 * Pré-requis :
 * - 50 comptes soignants test seedés (préfixe loadtest-soignant-N@jolene.app)
 *   créés via le setup() ci-dessous (idempotent).
 * - 1 mission test seedée (handler setup() + teardown() pour cleanup).
 *
 * Lancer :
 *   k6 run tests/load/scenarios/04-candidatures-simultanees.js \
 *     -e STAGING_SUPABASE_URL=... -e STAGING_SUPABASE_ANON_KEY=... \
 *     -e STAGING_SUPABASE_SERVICE_ROLE_KEY=... -e LOAD_TEST_PASSWORD=...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  SUPABASE_URL,
  ANON_KEY,
  serviceRoleHeaders,
  authedHeaders,
  login,
} from '../helpers/auth.js';
import { strongPassword } from '../helpers/data.js';

const VU_COUNT = 50;

export const options = {
  scenarios: {
    candidatures_simultanees: {
      executor: 'per-vu-iterations',
      vus: VU_COUNT,
      iterations: 1, // chaque VU postule 1 fois
      maxDuration: '60s',
      gracefulStop: '15s',
    },
  },
  thresholds: {
    // 1 succès attendu, 49 conflict / unique violation (status 409 ou erreur RPC)
    // → le but : pas de 5xx, pas de doublon
    'http_req_failed{name:rpc_postuler}': ['rate<0.10'], // tolère les conflicts métier
    'http_req_duration{name:rpc_postuler}': ['p(95)<2000'],
  },
};

/**
 * Setup global (1× au début) :
 * 1. Crée 50 comptes soignants test si non existants
 * 2. Crée 1 mission OUVERTE rattachée à playwright-etab@jolene.app
 * 3. Pre-login chaque soignant et stocke les JWT
 */
export function setup() {
  const sr = serviceRoleHeaders();

  // 1. Trouver l'etab id (compte test fixe seedé via migration 20260503050000)
  const etabRes = http.post(
    `${SUPABASE_URL}/rest/v1/rpc/fn_admin_get_user_id_by_email`,
    JSON.stringify({ p_email: 'playwright-etab@jolene.app' }),
    { headers: sr },
  );
  if (etabRes.status !== 200) {
    throw new Error(`setup: get etab id failed (${etabRes.status})`);
  }
  const etabId = etabRes.json();
  if (!etabId) throw new Error('setup: playwright-etab non seedé en staging');

  // 2. Créer la mission test (idempotent : DELETE then INSERT)
  http.del(
    `${SUPABASE_URL}/rest/v1/missions?intitule=eq.${encodeURIComponent('[loadtest-D] Mission populaire')}`,
    null,
    { headers: sr },
  );
  const missionRes = http.post(
    `${SUPABASE_URL}/rest/v1/missions`,
    JSON.stringify({
      etablissement_id: etabId,
      intitule: '[loadtest-D] Mission populaire',
      description: 'Test 50 candidatures simultanées',
      profession_requise: 'IDE',
      service: 'Test',
      debut_le: new Date(Date.now() + 7 * 86400000).toISOString(),
      fin_le: new Date(Date.now() + 7 * 86400000 + 8 * 3600000).toISOString(),
      taux_horaire_base: 30,
      statut: 'OUVERTE',
      mode_attribution: 'CANDIDATURE',
    }),
    { headers: { ...sr, Prefer: 'return=representation' } },
  );
  if (missionRes.status >= 400) {
    throw new Error(`setup: create mission failed (${missionRes.status}): ${missionRes.body}`);
  }
  const missionId = missionRes.json()[0].id;

  // 3. Pré-créer 50 soignants test + login chacun
  const password = strongPassword();
  const tokens = [];
  for (let i = 1; i <= VU_COUNT; i++) {
    const email = `loadtest-soignant-${i}@jolene.app`;
    // signup idempotent : si existe déjà, on ignore l'erreur
    http.post(
      `${SUPABASE_URL}/auth/v1/signup`,
      JSON.stringify({ email, password, data: { role: 'SOIGNANT', via_loadtest: true } }),
      { headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' } },
    );
    const tok = login(email, password);
    if (tok?.access_token) tokens.push(tok.access_token);
  }
  if (tokens.length < VU_COUNT) {
    console.warn(`setup: only ${tokens.length}/${VU_COUNT} tokens obtained`);
  }
  return { missionId, tokens };
}

export default function (data) {
  const jwt = data.tokens[(__VU - 1) % data.tokens.length];
  if (!jwt) return;
  const url = `${SUPABASE_URL}/rest/v1/rpc/fn_postuler_mission`;
  const res = http.post(
    url,
    JSON.stringify({ p_mission_id: data.missionId, p_message: 'Loadtest D' }),
    { headers: authedHeaders(jwt), tags: { name: 'rpc_postuler' } },
  );
  check(res, {
    'postuler 200/400 (conflict OK)': (r) => r.status === 200 || r.status === 400,
    'pas de 5xx': (r) => r.status < 500,
  });
}

/**
 * Teardown : vérifie qu'il n'y a PAS de doublon dans candidatures pour
 * la mission, puis cleanup (delete mission + candidatures).
 */
export function teardown(data) {
  const sr = serviceRoleHeaders();
  const cntRes = http.get(
    `${SUPABASE_URL}/rest/v1/candidatures?mission_id=eq.${data.missionId}&select=soignant_id`,
    { headers: sr },
  );
  const candidatures = cntRes.json() || [];
  const uniqueSoignants = new Set(candidatures.map((c) => c.soignant_id));
  const hasDuplicates = candidatures.length !== uniqueSoignants.size;
  console.log(`Teardown: ${candidatures.length} candidatures, ${uniqueSoignants.size} unique soignants, doublons=${hasDuplicates}`);
  if (hasDuplicates) {
    throw new Error('CRITICAL: doublons candidatures détectés (race condition non protégée)');
  }
  // Cleanup
  http.del(
    `${SUPABASE_URL}/rest/v1/candidatures?mission_id=eq.${data.missionId}`,
    null,
    { headers: sr },
  );
  http.del(`${SUPABASE_URL}/rest/v1/missions?id=eq.${data.missionId}`, null, { headers: sr });
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, 'D — Candidatures simultanées'),
    'tests/load/results/04-candidatures-simultanees.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, label) {
  const m = data.metrics;
  const dur = m['http_req_duration{name:rpc_postuler}'] || m.http_req_duration;
  const fail = m['http_req_failed{name:rpc_postuler}'] || m.http_req_failed;
  return [
    '',
    `=== Scenario ${label} ===`,
    `Iterations  : ${m.iterations?.values?.count ?? 'n/a'}`,
    `Failure %   : ${((fail?.values?.rate ?? 0) * 100).toFixed(2)}`,
    `p50/p95/p99 : ${dur?.values?.['p(50)']?.toFixed(0)}/${dur?.values?.['p(95)']?.toFixed(0)}/${dur?.values?.['p(99)']?.toFixed(0)} ms`,
    '',
  ].join('\n');
}

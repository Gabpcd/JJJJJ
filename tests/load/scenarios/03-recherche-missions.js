import { resumeCharge } from '../helpers/resume.js';
import { creerOptionsCharge } from '../helpers/options.js';
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
import { rechercheValide, exigerRecherchePeuplee } from '../helpers/contrats.js';

export const options = creerOptionsCharge('recherche_missions', {
  executor: 'ramping-vus',
  startVUs: 0,
  stages: [
    { duration: '30s', target: 200 },
    { duration: '1m30s', target: 200 },
    { duration: '15s', target: 0 },
  ],
  gracefulRampDown: '15s',
}, {
  'http_req_failed{name:rpc_recherche}': ['rate<0.01'],
  'http_req_duration{name:rpc_recherche}': ['p(50)<400', 'p(95)<1000', 'p(99)<2000'],
}, __ENV);

export function setup() {
  const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_missions_publiques_recherche`, '{}', {
    headers: anonHeaders(), tags: { name: 'recherche_preflight' }, timeout: '15s',
  });
  if (res.status !== 200) throw new Error(`Préflight C : recherche indisponible (HTTP ${res.status}).`);
  const nombreMissions = exigerRecherchePeuplee(res.json());
  console.log(`Préflight C : ${nombreMissions} mission(s) publique(s) visible(s). Aucune écriture.`);
}

export default function () {
  const url = `${SUPABASE_URL}/rest/v1/rpc/fn_missions_publiques_recherche`;
  // Inclure régulièrement la recherche peuplée du préflight ; les filtres sans résultat restent légitimes.
  const filters = __ITER % 5 === 0 ? {} : randomFilters();
  // Nettoyer les null pour ne pas envoyer "p_profession":null si non utilisé
  const body = {};
  if (filters.p_profession) body.p_profession = filters.p_profession;
  if (filters.p_ville) body.p_ville = filters.p_ville;

  const res = http.post(url, JSON.stringify(body), {
    headers: anonHeaders(),
    tags: { name: 'rpc_recherche' },
    timeout: '15s',
  });
  check(res, {
    'recherche 200': (r) => r.status === 200,
    'recherche contrat public valide': (r) => {
      try { return rechercheValide(r.json()); } catch { return false; }
    },
    'recherche sans filtre peuplee': (r) => {
      try { return __ITER % 5 !== 0 || r.json().length > 0; } catch { return false; }
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
  return resumeCharge(data, label, 'rpc_recherche', options);
}

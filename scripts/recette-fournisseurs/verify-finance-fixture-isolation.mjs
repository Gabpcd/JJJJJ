import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT = 'mejpriaetwgtcstbgfid';
const sql = readFileSync(new URL('./sql/finance-cohortes-rollback.sql', import.meta.url), 'utf8');
const verification = `SELECT
  (SELECT valeur::text FROM public.parametres_systeme WHERE cle='inscriptions_publiques_actives') AS inscriptions,
  (SELECT count(*)::int FROM auth.users WHERE raw_app_meta_data->>'recette_finance_rollback'='true') AS acteurs;`;

// Contrôle backend de préparation, sans appel Stripe. Les quatre comptes
// fictifs et tous les effets SQL de leurs triggers sont annulés par ROLLBACK.
export async function verifyFixtureIsolation({ token, fetchImpl = fetch }) {
  const report = { projectRef: PROJECT, status: 'UNCONFIRMED', integratedFlowReady: false,
    rollbackConfirmed: false, issue: null };
  if (typeof token !== 'string' || !token.trim()) return { ...report, issue: 'TOKEN_MISSING' };
  async function query(query, readOnly) {
    const response = await fetchImpl(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, read_only: readOnly }),
    });
    if (!response.ok) throw new Error('QUERY_REJECTED');
    return response.json();
  }
  const restored = rows => Array.isArray(rows) && rows.length === 1
    && rows[0]?.inscriptions === '0' && rows[0]?.acteurs === 0;
  try {
    if (!restored(await query(verification, true))) return { ...report, issue: 'INITIAL_STATE_INVALID' };
    await query(sql, false);
    if (!restored(await query(verification, true))) return { ...report, issue: 'RESTORATION_UNCONFIRMED' };
    return { ...report, status: 'FIXTURE_ISOLATION_VERIFIED', rollbackConfirmed: true };
  } catch {
    // Une réponse perdue ne permet pas de revendiquer un rollback confirmé.
    // Aucun retry et aucun corps d'erreur fournisseur dans le rapport.
    return { ...report, issue: 'EXECUTION_UNCONFIRMED' };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = await verifyFixtureIsolation({ token: process.env.STAGING_SUPABASE_ACCESS_TOKEN });
  writeFileSync('finance-fixture-isolation.json', JSON.stringify(report, null, 2) + '\n');
  console.log(`${report.status}: ${report.issue ?? 'isolation seulement, aucun paiement exécuté'}`);
  process.exitCode = report.rollbackConfirmed ? 0 : 2;
}

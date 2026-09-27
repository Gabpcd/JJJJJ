import { execFileSync } from 'node:child_process';
import { readdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { assertCandidate, assertHarnessCleanupReady, RECETTE_REF, PROD_REF } from './lib/recette-escrow-safety.mjs';

export async function preflight({ branchRef, expectedSha, actualSha, expectedMigrations, token, stripeKey, fetchImpl = fetch }) {
  if (branchRef !== RECETTE_REF) throw new Error('CIBLE_REFUSEE: seule la branche escrow dédiée est autorisée.');
  if (!/^[a-f0-9]{40}$/.test(expectedSha || '') || actualSha !== expectedSha) throw new Error('SHA_INCOMPATIBLE: checkout différent de la candidate demandée.');
  if (!token || !stripeKey?.startsWith('sk_test_')) throw new Error('SECRETS_TEST_REQUIS: token Management et clé Stripe TEST requis.');
  const request = async (url, init) => {
    const response = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`PREFLIGHT_HTTP_${response.status}: aucun corps de réponse ni secret affiché.`);
    try { return await response.json(); } catch { throw new Error('REPONSE_PREFLIGHT_INVALIDE'); }
  };
  const branches = await request(`https://api.supabase.com/v1/projects/${PROD_REF}/branches`, { headers: { Authorization: `Bearer ${token}` } });
  const applied = await request(`https://api.supabase.com/v1/projects/${branchRef}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;' }),
  });
  if (!Array.isArray(branches) || !Array.isArray(applied)) throw new Error('REPONSE_PREFLIGHT_INVALIDE');
  assertCandidate({ branchRef, actualSha, expectedSha, branches, expectedMigrations, appliedMigrations: applied.map((row) => row.version) });
  const balance = await request('https://api.stripe.com/v1/balance', { headers: { Authorization: `Bearer ${stripeKey}` } });
  if (balance.livemode !== false) throw new Error('STRIPE_LIVE_INTERDIT');
  assertHarnessCleanupReady();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const proof = { candidate: process.env.RECETTE_CANDIDATE_SHA || null, branch: process.env.RECETTE_BRANCH_REF || null, ready: false, mutations: 0 };
  try {
    await preflight({ branchRef: proof.branch, expectedSha: proof.candidate,
      actualSha: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
      expectedMigrations: readdirSync('supabase/migrations').filter((name) => /^\d+_.+\.sql$/.test(name)).map((name) => name.split('_')[0]),
      token: process.env.SUPABASE_ACCESS_TOKEN, stripeKey: process.env.STRIPE_TEST_SECRET_KEY,
    });
  } catch (error) {
    proof.reason = error.message;
    writeFileSync('recette-stripe-preflight.json', JSON.stringify(proof, null, 2) + '\n', { mode: 0o600 });
    console.error(proof.reason);
    process.exitCode = 1;
  }
}

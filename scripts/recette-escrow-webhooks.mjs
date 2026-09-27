import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { assertHarnessCleanupReady, cleanupWebhooks, createWebhooks } from './lib/recette-escrow-safety.mjs';

const path = 'recette-stripe-webhooks.json';
const save = async (manifest) => {
  writeFileSync(`${path}.tmp`, JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
  renameSync(`${path}.tmp`, path);
};
const key = process.env.STRIPE_TEST_SECRET_KEY || '';
async function api(method, resource, params = {}, idempotencyKey) {
  if (!key.startsWith('sk_test_')) throw new Error('CLE_STRIPE_TEST_REQUISE');
  const body = new URLSearchParams();
  for (const [name, value] of Object.entries(params)) {
    for (const item of Array.isArray(value) ? value : [value]) body.append(Array.isArray(value) ? `${name}[]` : name, String(item));
  }
  const response = await fetch(`https://api.stripe.com/v1/${resource}`, {
    method, headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/x-www-form-urlencoded',
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}) },
    ...(method === 'POST' ? { body } : {}), signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`STRIPE_HTTP_${response.status}`);
  try { return await response.json(); } catch { throw new Error('REPONSE_STRIPE_INVALIDE'); }
}

try {
  if (process.argv[2] === 'cleanup') {
    if (!existsSync(path)) {
      console.log('Aucun webhook enregistré par ce run; aucune suppression effectuée.');
    } else {
      const manifest = JSON.parse(readFileSync(path, 'utf8'));
      await cleanupWebhooks({ api, manifest, save });
      console.log(`Suppression confirmée pour ${manifest.webhooks.length} webhook(s) enregistré(s) par ce run.`);
    }
  } else if (process.argv[2] === 'create') {
    assertHarnessCleanupReady();
    const { secrets } = await createWebhooks({ api, branchRef: process.env.RECETTE_BRANCH_REF,
      runId: `${process.env.GITHUB_RUN_ID}-${process.env.GITHUB_RUN_ATTEMPT}`, save });
    // Secrets stay in memory; the artifact contains only ownership and deletion proof.
    const response = await fetch(`https://api.supabase.com/v1/projects/${process.env.RECETTE_BRANCH_REF}/secrets`, {
      method: 'POST', headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify([
        { name: 'STRIPE_SECRET_KEY', value: key },
        { name: 'STRIPE_PLATFORM_WEBHOOK_SECRET', value: secrets.platform },
        { name: 'STRIPE_CONNECT_WEBHOOK_SECRET', value: secrets.connect },
      ]), signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`SECRETS_BRANCHE_HTTP_${response.status}`);
    console.log('Deux endpoints TEST enregistrés dans le manifeste; secrets branche installés.');
  } else {
    throw new Error('COMMANDE_REQUISE: create ou cleanup');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

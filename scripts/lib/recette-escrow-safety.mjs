// This legacy recipe is intentionally blocked until its SQL fixtures and Vault
// changes have a verified cleanup/restore strategy. There is no env bypass.
export const RECETTE_REF = 'wnepopwygokbhlqghydb';
export const PROD_REF = 'flripxtsyegjshnhzjkz';
export const CLEANUP_BLOCKER = 'RECETTE_BLOQUEE: prévoir le manifeste et le nettoyage des seules ressources créées, sans retoucher les fixtures existantes, ainsi que la restauration du bearer Vault, avant de réactiver les legs Stripe.';

export function assertHarnessCleanupReady() {
  throw new Error(CLEANUP_BLOCKER);
}

export function assertCandidate({ branchRef, actualSha, expectedSha, branches, expectedMigrations, appliedMigrations }) {
  if (branchRef !== RECETTE_REF) throw new Error('CIBLE_REFUSEE: seule la branche escrow dédiée est autorisée; production et staging partagé interdits.');
  if (!/^[a-f0-9]{40}$/.test(expectedSha || '') || actualSha !== expectedSha) throw new Error('SHA_INCOMPATIBLE: le checkout doit correspondre exactement à la candidate demandée.');
  const branch = branches.find((b) => b.project_ref === branchRef);
  if (!branch || branch.parent_project_ref !== PROD_REF || branch.is_default !== false || branch.with_data !== false || branch.status !== 'FUNCTIONS_DEPLOYED' || branch.preview_project_status !== 'ACTIVE_HEALTHY') {
    throw new Error('BRANCHE_NON_PRETE: branche dédiée saine, sans copie de données, et migrations réussies requises.');
  }
  const expected = [...expectedMigrations].sort();
  const applied = [...appliedMigrations].sort();
  if (!expected.length || JSON.stringify(expected) !== JSON.stringify(applied)) throw new Error('SCHEMA_INCOMPATIBLE: le registre SQL de la branche doit correspondre aux migrations du checkout; aucune migration ni reset automatique.');
}

// A caller supplies an HTTP client and a durable, secret-free manifest writer.
// IDs are persisted after EACH creation, including when the next POST fails.
export async function createWebhooks({ api, branchRef, runId, save }) {
  if (branchRef !== RECETTE_REF || !/^[a-zA-Z0-9_-]+$/.test(runId)) throw new Error('CONTEXTE_WEBHOOK_INVALIDE');
  const manifest = { version: 1, branchRef, runId, webhooks: [] };
  const secrets = {};
  await save(manifest);
  try {
    for (const kind of ['platform', 'connect']) {
      const url = `https://${branchRef}.supabase.co/functions/v1/${kind === 'platform' ? 'stripe-webhook' : 'stripe-connect-webhook'}`;
      const description = `recette-escrow ${runId} ${kind}`;
      const params = {
        url, description, api_version: '2026-02-25.clover',
        ...(kind === 'connect' ? { connect: true } : {}),
        enabled_events: kind === 'platform'
          ? ['payment_intent.succeeded', 'payment_intent.payment_failed', 'charge.dispute.created', 'charge.refunded']
          : ['account.updated', 'payout.created', 'payout.paid', 'payout.failed', 'payout.canceled'],
      };
      const endpoint = await api('POST', 'webhook_endpoints', params, `recette-escrow-${runId}-${kind}`);
      if (!/^we_[a-zA-Z0-9]+$/.test(endpoint.id || '')) throw new Error('IDENTIFIANT_WEBHOOK_INVALIDE');
      manifest.webhooks.push({ kind, id: endpoint.id, url, description, deleted: false });
      await save(manifest);
      if (endpoint.livemode !== false || endpoint.url !== url || endpoint.description !== description || typeof endpoint.secret !== 'string' || !endpoint.secret.startsWith('whsec_')) throw new Error('REPONSE_WEBHOOK_INVALIDE');
      secrets[kind] = endpoint.secret;
    }
    return { manifest, secrets };
  } catch (error) {
    await cleanupWebhooks({ api, manifest, save });
    throw error;
  }
}

export async function cleanupWebhooks({ api, manifest, save }) {
  if (manifest.version !== 1 || manifest.branchRef !== RECETTE_REF || !/^[a-zA-Z0-9_-]+$/.test(manifest.runId || '') || !Array.isArray(manifest.webhooks)) throw new Error('MANIFESTE_WEBHOOK_INVALIDE');
  const failures = [];
  for (const entry of manifest.webhooks) {
    if (entry.deleted === true) continue;
    try {
      const expectedUrl = `https://${RECETTE_REF}.supabase.co/functions/v1/${entry.kind === 'platform' ? 'stripe-webhook' : 'stripe-connect-webhook'}`;
      const expectedDescription = `recette-escrow ${manifest.runId} ${entry.kind}`;
      if (!['platform', 'connect'].includes(entry.kind) || !/^we_[a-zA-Z0-9]+$/.test(entry.id || '') || entry.url !== expectedUrl || entry.description !== expectedDescription) throw new Error('MANIFESTE_WEBHOOK_INVALIDE');
      // Never delete an endpoint belonging to another run or to live mode.
      const existing = await api('GET', `webhook_endpoints/${entry.id}`);
      if (existing.id !== entry.id || existing.livemode !== false || existing.url !== expectedUrl || existing.description !== expectedDescription) throw new Error('PROPRIETE_WEBHOOK_NON_PROUVEE');
      const deleted = await api('DELETE', `webhook_endpoints/${entry.id}`);
      if (deleted.id !== entry.id || deleted.deleted !== true) throw new Error('SUPPRESSION_WEBHOOK_NON_CONFIRMEE');
      entry.deleted = true;
      await save(manifest);
    } catch {
      failures.push(entry.kind);
    }
  }
  if (failures.length) throw new Error(`NETTOYAGE_WEBHOOK_INCOMPLET: ${failures.join(', ')}. Consulter le manifeste; aucune suppression confirmée pour ces entrées.`);
}

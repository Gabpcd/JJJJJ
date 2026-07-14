import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  join(process.cwd(), 'supabase/functions/process-stripe-refunds/index.ts'),
  'utf8',
);
const migration = readFileSync(
  join(
    process.cwd(),
    'supabase/migrations/20260714032324_securiser_finalisation_remboursements_stripe.sql',
  ),
  'utf8',
);

describe('process-stripe-refunds — reprise et persistance idempotentes', () => {
  it('reprend après lease une ligne EN_COURS abandonnée', () => {
    expect(source).toContain('const LEASE_MS = 15 * 60 * 1000');
    expect(source).toContain('const leaseBefore = new Date(Date.now() - LEASE_MS).toISOString()');
    expect(source).toContain('.in("statut", ["EN_ATTENTE", "EN_COURS"])');
    expect(source).toContain('.eq("tentatives", item.tentatives)');
    expect(source).toContain('.or(`dernier_essai_le.is.null,dernier_essai_le.lt.${leaseBefore}`)');
    expect(source).toContain('idempotencyKey: `refund_queue_${item.id}`');
  });

  it('persiste le refund exact puis finalise TRAITE par une seule RPC', () => {
    expect(source).toContain('async function bindRefundId(');
    expect(source).toContain('current.stripe_refund_id !== refundId');
    expect(source).toContain('["EN_COURS", "TRAITE", "ECHEC"].includes(current.statut)');
    expect(source).toContain('sb.rpc("fn_stripe_refund_rapprocher"');
    expect(source).toContain('if (error || !data?.success)');
    expect(source).toContain('await reconcile(sb, item, exactRefund.id, "SUCCEEDED", null)');
  });

  it('restaure en ECHEC seulement un préflight prouvé avant refunds.create', () => {
    const catchStart = source.indexOf('} catch (error)', source.indexOf('for (const item of queue)'));
    const catchBlock = source.slice(catchStart, source.indexOf('\n      }\n    }', catchStart));

    expect(catchBlock).toContain('error instanceof ProvenPreflightError');
    expect(catchBlock).toContain('refundAbsenceProven');
    expect(catchBlock).toContain('!createAttempted');
    expect(catchBlock).toContain('!exactRefund');
    expect(catchBlock).toContain('await reconcile(sb, item, null, "FAILED"');
    expect(catchBlock).toContain('await keepAmbiguousForPolling(');
  });

  it('ne rétrograde jamais un TRAITE écrit par le webhook concurrent', () => {
    expect(migration).toContain(
      "IF p_resultat = 'SUCCEEDED' AND v_queue.statut = 'TRAITE' THEN",
    );
    expect(migration).toContain(
      "RETURN jsonb_build_object('success', true, 'already_processed', true)",
    );
    expect(migration).toContain(
      "IF v_queue.statut NOT IN ('EN_ATTENTE', 'EN_COURS') THEN",
    );
    expect(source).not.toMatch(/\.update\(\{\s*statut:\s*"TRAITE"/);
  });
});

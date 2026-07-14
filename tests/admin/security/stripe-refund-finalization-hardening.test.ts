import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const worker = readFileSync(
  'supabase/functions/process-stripe-refunds/index.ts',
  'utf8',
);
const webhook = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260714032324_securiser_finalisation_remboursements_stripe.sql',
  'utf8',
);

describe('Stripe refunds — finalisation exacte et retryable', () => {
  it('gèle l’escrow jusqu’au statut succeeded et restaure seulement failed/canceled', () => {
    expect(migration).toContain("'REMBOURSE_EN_COURS'::text");
    expect(migration).toContain("SET statut = 'REMBOURSE_EN_COURS'");
    expect(migration).toContain('escrow_statut_avant_remboursement');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_stripe_refund_rapprocher');
    expect(migration).toContain("p_resultat NOT IN ('SUCCEEDED', 'FAILED', 'CANCELED')");
    expect(migration).toContain("IF p_resultat = 'SUCCEEDED' THEN");
    expect(migration).toContain("SET statut = 'REMBOURSE'");
    expect(migration).toContain("SET statut = 'TRAITE'");
    expect(migration).toContain('SET statut = v_queue.escrow_statut_avant_remboursement');
    expect(migration).toContain("SET statut = 'ECHEC'");
    expect(migration).toContain("AND statut = 'REMBOURSE_EN_COURS'");
  });

  it('retrouve un Refund par queue_id sur tout l’historique avant toute création', () => {
    const findStart = worker.indexOf('async function findExistingRefund');
    const bindStart = worker.indexOf('async function bindRefundId', findStart);
    const find = worker.slice(findStart, bindStart);
    const create = worker.indexOf('stripe.refunds.create(context.params');

    expect(find).toContain('stripe.refunds.retrieve(item.stripe_refund_id)');
    expect(find).toContain('stripe.refunds.list({');
    expect(find).toContain('starting_after: startingAfter');
    expect(find).toContain('page.has_more ? page.data.at(-1)?.id : undefined');
    expect(find).toContain('refund.metadata?.queue_id === item.id');
    expect(find).toContain('DUPLICATE_QUEUE_REFUNDS_MANUAL_REVIEW');
    expect(worker.indexOf('const existing = await findExistingRefund')).toBeLessThan(create);
    expect(worker).toContain('idempotencyKey: `refund_queue_${item.id}`');
  });

  it('ne transforme jamais une source déjà remboursée ou contestée en échec restaurable', () => {
    const sourceValidation = worker.slice(
      worker.indexOf('async function validateCommonStripeSource'),
      worker.indexOf('async function validateEscrowSource'),
    );
    const queueLoop = worker.indexOf('for (const item of queue)');
    const catchStart = worker.indexOf('} catch (error)', queueLoop);
    const catchBlock = worker.slice(
      catchStart,
      worker.indexOf('\n      }\n    }', catchStart),
    );

    expect(sourceValidation).toContain('otherSucceededRefundedAmount');
    expect(sourceValidation).toContain('charge.disputed');
    expect(sourceValidation).toContain('new AmbiguousFinancialStateError(');
    expect(catchBlock).toContain('error instanceof ProvenPreflightError');
    expect(catchBlock).toContain('refundAbsenceProven');
    expect(catchBlock).toContain('!createAttempted');
    expect(catchBlock).toContain('await keepAmbiguousForPolling(');
    expect(catchBlock).not.toContain('charge_already_refunded');
  });

  it('ne finalise la queue que par la RPC transactionnelle et un Refund terminal', () => {
    const statusStart = worker.indexOf('if (exactRefund.status === "succeeded")');
    const statusBranch = worker.slice(
      statusStart,
      worker.indexOf('} catch (error)', statusStart),
    );

    expect(statusBranch).toContain('await reconcile(sb, item, exactRefund.id, "SUCCEEDED", null)');
    expect(statusBranch).toContain('exactRefund.status === "failed"');
    expect(statusBranch).toContain('exactRefund.status === "canceled"');
    expect(statusBranch).toContain('await keepAmbiguousForPolling(');
    expect(worker).toContain('sb.rpc("fn_stripe_refund_rapprocher"');
    expect(worker).not.toMatch(/\.update\(\{\s*statut:\s*"TRAITE"/);
  });

  it('rapproche le webhook par refund/queue exacts, y compris le reversal escrow', () => {
    const start = webhook.indexOf('// ── charge.refunded');
    const end = webhook.indexOf('// ── transfer.reversed', start);
    const refunded = webhook.slice(start, end);

    expect(refunded).toContain('starting_after: refundStartingAfter');
    expect(refunded).toContain('refund.metadata?.queue_id');
    expect(refunded).toContain('[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}');
    expect(refunded).toContain('.eq("id", queueId)');
    expect(refunded).toContain('refund.metadata?.source !== "jolene_refunds_cron"');
    expect(refunded).toContain('refund.metadata?.origin_type !== expectedOrigin');
    expect(refunded).toContain('refund.metadata?.facture_origine_id');
    expect(refunded).toContain('!refund.transfer_reversal');
    expect(refunded).toContain('"fn_stripe_refund_rapprocher"');
    expect(refunded).toContain('status.toUpperCase()');
    expect(refunded).toContain('Unmanaged Stripe refund');
    expect(refunded).not.toContain('REMBOURSEE');
  });
});

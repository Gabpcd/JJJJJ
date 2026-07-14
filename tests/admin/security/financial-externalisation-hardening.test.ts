import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const worker = readFileSync(
  'supabase/functions/process-externalisation-actions/index.ts',
  'utf8',
);
const refundsMigration = readFileSync(
  'supabase/migrations/20260714032324_securiser_finalisation_remboursements_stripe.sql',
  'utf8',
);
const documentsMigration = readFileSync(
  'supabase/migrations/20260714060000_securiser_remplacement_documents_rib_et_validation_etablissements.sql',
  'utf8',
);

describe('Externalisations financières — identité, reprise et acquittement', () => {
  it('contrôle chaque acquittement et ne rétrograde pas un effet fournisseur réussi', () => {
    expect(worker).toContain('let externalEffectSucceeded = false');
    expect(worker).toContain('externalEffectSucceeded = true');
    expect(worker).toContain('ack?.success !== true');
    expect(worker).toContain('EXTERNALISATION_SUCCESS_ACK_FAILED');
    expect(worker).toContain('EXTERNALISATION_FAILURE_ACK_FAILED');
    expect(worker).toContain('if (externalEffectSucceeded)');
    expect(worker).toContain('ackFailed++');
    expect(worker).toContain('status: ackFailed > 0 ? 500 : 200');

    expect(refundsMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_externalisation_succes',
    );
    expect(refundsMigration).toContain(
      'CREATE OR REPLACE FUNCTION public.fn_externalisation_echec',
    );
    expect(refundsMigration).toContain('FOR UPDATE');
    expect(refundsMigration).toContain("IF v_action.statut = 'DONE' THEN");
  });

  it('ne rembourse qu’une charge standard exacte et reprend le Refund par action', () => {
    const start = worker.indexOf('async function dispatchStripeRefund(');
    const end = worker.indexOf('async function dispatchStripePayment(', start);
    const refund = worker.slice(start, end);

    expect(refund).toContain('.from("missions")');
    expect(refund).toContain('.from("etablissements")');
    expect(refund).toContain('paymentIntent.metadata?.mission_id !== mission.id');
    expect(refund).toContain(
      'paymentIntent.metadata?.etablissement_id !== mission.etablissement_id',
    );
    expect(refund).toContain('piCustomerId !== etablissement.stripe_customer_id');
    expect(refund).toContain('chargePaymentIntentId !== paymentIntent.id');
    expect(refund).toContain('CONNECT_TRANSFER_REVERSAL_REQUIRED');
    expect(refund).toContain('ESCROW_REFUND_QUEUE_REQUIRED');
    expect(refund).toContain('sourceType !== "commission_reservation"');
    expect(refund).toContain(
      'refund.metadata?.externalisation_action_id === action.id',
    );
    expect(refund).toContain('DUPLICATE_EXTERNALISATION_REFUNDS');
    expect(refund).toContain('idempotencyKey: `externalisation_refund_${action.id}`');
    expect(refund).toContain('refund.status !== "succeeded"');
    expect(refund).toContain('STRIPE_REFUND_RESULT_IDENTITY_MISMATCH');
  });

  it('désactive les paiements génériques dépourvus de source réconciliable', () => {
    const start = worker.indexOf('async function dispatchStripePayment(');
    const end = worker.indexOf('async function dispatchStripePayout(', start);
    const genericPayment = worker.slice(start, end);

    expect(genericPayment).toContain('STRIPE_PAYMENT_GENERIQUE_DESACTIVE');
    expect(genericPayment).not.toContain('stripe.transfers.create');
    expect(genericPayment).not.toContain('stripe.paymentIntents.create');
  });

  it('verse une prime seulement via deux transferts Connect exacts et persistés', () => {
    const start = worker.indexOf('async function dispatchRecompenseParrainage(');
    const end = worker.indexOf('async function dispatchRemboursementAvoirSwan(', start);
    const referral = worker.slice(start, end);
    const finalization = referral.indexOf(
      '.update({ statut: "PRIME_VERSEE", prime_versee_le:',
    );

    expect(referral).toContain('action.source !== "parrainage_soignant"');
    expect(referral).toContain('parrainage.parrain_id !== parrain_id');
    expect(referral).toContain('parrainage.filleul_id !== filleul_id');
    expect(referral).toContain('Number(montant_parrain) !== prime');
    expect(referral).toContain('persistedAction.statut !== "PROCESSING"');
    expect(referral).toContain('onboarding.onboarding_complete !== true');
    expect(referral).toContain('onboarding.charges_enabled !== true');
    expect(referral).toContain('onboarding.payouts_enabled !== true');
    expect(referral).toContain('PARRAINAGE_TRAITEMENT_MANUEL_REQUIS');
    expect(referral).toContain('await persistProgress()');
    expect(referral).toContain(
      'idempotencyKey: `parrainage_transfer_${parrainage_id}_${role}`',
    );
    expect(referral).toContain('transfer.metadata?.beneficiaire_id !== userId');
    expect(referral).toContain('transfer.amount_reversed !== 0');
    expect(finalization).toBeGreaterThan(referral.indexOf('for (const [role, userId]'));
    expect(referral).not.toContain('swanClient');
  });

  it('rend l’enfilage de prime unique et audite les transitions métier', () => {
    expect(documentsMigration).toContain(
      'uniq_externalisation_recompense_parrainage',
    );
    expect(documentsMigration).toContain(
      'ON CONFLICT (type_action, source, source_id)',
    );
    expect(documentsMigration).toContain('FOR UPDATE');
    expect(documentsMigration).toContain('PARRAINAGE_SOIGNANT_FRAUDE');
    expect(documentsMigration).toContain('PARRAINAGE_SOIGNANT_SEUIL_ATTEINT');
    expect(documentsMigration).toContain("'prime_due_eur', v_prime");
    expect(documentsMigration).toContain('son paiement est en cours de traitement');
  });

  it('ne simule ni virement SWAN confirmé ni PDF comptable', () => {
    const swanStart = worker.indexOf('async function dispatchRemboursementAvoirSwan(');
    const swanEnd = worker.indexOf('// ─── Chorus Pro', swanStart);
    const swan = worker.slice(swanStart, swanEnd);
    const pdfStart = worker.indexOf('async function dispatchAvoirPdf(');
    const pdf = worker.slice(pdfStart);

    expect(swan).toContain('type_document !== "AVOIR"');
    expect(swan).toContain('REMBOURSEMENT_AVOIR_MANUEL_REQUIS');
    expect(swan).not.toContain('payments.create');
    expect(swan).not.toContain('iban');
    expect(swan).not.toContain('date_remboursement:');
    expect(pdf).toContain('AVOIR_PDF_CONFORME_REQUIERT_AVOIR_DB');
    expect(pdf).not.toContain('.upload(');
    expect(pdf).not.toContain('Math.random');
  });

  it('reprend séparément email et push DPAE sur un contrat salarié exact', () => {
    const start = worker.indexOf('async function dispatchDpaeAnnulation(');
    const end = worker.indexOf('// ─── Emails + Push', start);
    const dpae = worker.slice(start, end);

    expect(dpae).toContain('action.source !== "ANNULATION_MISSION"');
    expect(dpae).toContain('action.source_id !== mission_id');
    expect(dpae).toContain('contrat.mission_id !== mission_id');
    expect(dpae).toContain('["CDD", "CDDU", "VACATION"]');
    expect(dpae).toContain('contrat.statut !== "RUPTURE_ETAB"');
    expect(dpae).toContain('progress.email_sent !== true');
    expect(dpae).toContain('progress.push_sent !== true');
    expect(dpae).toContain('if (!emailResponse.ok)');
    expect(dpae).toContain('if (!pushResponse.ok)');
    expect(dpae).toContain('await persistProgress()');
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const debit = readFileSync(
  'supabase/functions/escrow-debit-echeance/index.ts',
  'utf8',
);
const webhook = readFileSync(
  'supabase/functions/_shared/stripe-webhook-handler.ts',
  'utf8',
);
const debitIncidentMigration = readFileSync(
  'supabase/migrations/20260714054000_cas_echec_debit_escrow.sql',
  'utf8',
);

describe('Escrow — exposition A2 persistée et rejouable', () => {
  it('propage tout échec RPC d’exposition au lieu de continuer silencieusement', () => {
    const helperStart = debit.indexOf('const enregistrerExpositionEscrow');
    const helperEnd = debit.indexOf('let debitIdempotencyKey', helperStart);
    const helper = debit.slice(helperStart, helperEnd);

    expect(helperStart).toBeGreaterThan(0);
    expect(helper).toContain('fn_escrow_enregistrer_exposition');
    expect(helper).toContain('const { error: expositionError }');
    expect(helper).toContain('if (expositionError)');
    expect(helper).toContain('ESCROW_EXPOSITION_PERSISTENCE_FAILED');
    expect(helper).toContain('throw Object.assign');
  });

  it.each(['succeeded', 'processing']) (
    'rejoue l’exposition idempotente pour un PI existant %s avant de continuer',
    (status) => {
      const branchStart = debit.indexOf(`if (precedent.status === "${status}")`);
      const nextBranch = debit.indexOf('\n        if (precedent.status ===', branchStart + 1);
      const terminalBranch = debit.indexOf(
        '\n        if (!["canceled", "requires_payment_method"]',
        branchStart + 1,
      );
      const branchEnd = nextBranch > branchStart
        ? nextBranch
        : terminalBranch;
      const branch = debit.slice(branchStart, branchEnd);

      expect(branchStart).toBeGreaterThan(0);
      expect(branch).toContain('await enregistrerExpositionEscrow(precedent.id)');
      expect(branch).toContain('continue;');
    },
  );

  it('exige le succès du CAS de liaison PI avant d’enregistrer l’exposition', () => {
    const bindStart = debit.indexOf('let liaisonPiQuery = admin');
    const exposure = debit.indexOf('await enregistrerExpositionEscrow(pi.id)', bindStart);
    const block = debit.slice(bindStart, exposure);

    expect(bindStart).toBeGreaterThan(0);
    expect(block).toContain('.eq("statut", "INITIE")');
    expect(block).toContain('.eq("tentatives_debit", (esc.tentatives_debit ?? 0) + 1)');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('if (liaisonPiError || !paiementLieAuPi)');
    expect(block).toContain('ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED');
    expect(exposure).toBeGreaterThan(bindStart);
  });

  it('persiste aussi un statut PI inattendu par CAS exact avant de geler', () => {
    const statusGate = debit.indexOf('if (!["processing", "succeeded"].includes(pi.status))');
    const incident = debit.indexOf('const incidentCree = await marquerEchecDebitEscrow', statusGate);
    const block = debit.slice(statusGate, incident);

    expect(statusGate).toBeGreaterThan(0);
    expect(block).toContain('let referencePiQuery = admin');
    expect(block).toContain('.eq("tentatives_debit", (esc.tentatives_debit ?? 0) + 1)');
    expect(block).toContain('referencePiQuery.eq("stripe_payment_intent_id"');
    expect(block).toContain('referencePiQuery.is("stripe_payment_intent_id", null)');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('referencePiError || !referencePi');
    expect(block).toContain('ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED');
  });

  it('garde INITIE et sous la borne de retry lors d’une panne de persistance locale', () => {
    const catchStart = debit.indexOf('} catch (err: any)');
    const incident = debit.indexOf('if ((esc.tentatives_debit ?? 0) + 1 >= 3)', catchStart);
    const retryable = debit.slice(catchStart, incident);

    expect(retryable).toContain('ESCROW_EXPOSITION_PERSISTENCE_FAILED');
    expect(retryable).toContain('ESCROW_PAYMENT_INTENT_PERSISTENCE_FAILED');
    expect(retryable).toContain('err?.paymentIntentId');
    expect(retryable).toContain('tentatives_debit: Math.min(esc.tentatives_debit ?? 0, 2)');
    expect(retryable).toContain('.eq("statut", "INITIE")');
    expect(retryable).toContain('if (retryPersistenceError || !retryPersisted)');
    expect(retryable).toContain('continue;');
    expect(retryable.indexOf('continue;')).toBeLessThan(
      retryable.indexOf('if (failedIntentId)'),
    );
  });

  it('contrôle aussi le CAS de persistance du PI renvoyé par une erreur Stripe', () => {
    const start = debit.indexOf('if (failedIntentId)');
    const incident = debit.indexOf('if ((esc.tentatives_debit ?? 0) + 1 >= 3)', start);
    const block = debit.slice(start, incident);

    expect(block).toContain('failedIntentQuery');
    expect(block).toContain('.select("id")');
    expect(block).toContain('.maybeSingle()');
    expect(block).toContain('failedIntentPersistenceError || !failedIntentPersisted');
    expect(block).toContain('throw new Error(');
  });

  it('valide la Charge réellement acquise avant tout INITIE → DEBITE', () => {
    const existingSucceeded = debit.indexOf('if (precedent.status === "succeeded")');
    const existingUpdate = debit.indexOf('statut: "DEBITE"', existingSucceeded);
    const existingGuard = debit.indexOf(
      'requireAcquiredStripeSourceCharge(stripe, precedent',
      existingSucceeded,
    );
    const immediateSucceeded = debit.indexOf('if (pi.status === "succeeded")');
    const immediateUpdate = debit.indexOf('statut: "DEBITE"', immediateSucceeded);
    const immediateGuard = debit.lastIndexOf(
      'requireAcquiredStripeSourceCharge(stripe, pi',
      immediateSucceeded,
    );

    expect(existingGuard).toBeGreaterThan(existingSucceeded);
    expect(existingGuard).toBeLessThan(existingUpdate);
    expect(immediateGuard).toBeGreaterThan(0);
    expect(immediateGuard).toBeLessThan(immediateUpdate);
  });

  it('rend l’audit post-débit non bloquant et ne régresse jamais DEBITE sur son échec', () => {
    const auditHelper = debit.slice(
      debit.indexOf('async function auditEscrowNonBloquant'),
      debit.indexOf('async function marquerEchecDebitEscrow'),
    );
    const immediateDebit = debit.slice(
      debit.indexOf('if (pi.status === "succeeded")'),
      debit.indexOf('} catch (err: any)'),
    );

    expect(auditHelper).toContain('try {');
    expect(auditHelper).toContain('await auditEscrow(');
    expect(auditHelper).toContain('} catch (error)');
    expect(auditHelper).not.toContain('throw error');
    expect(immediateDebit).toContain('statut: "DEBITE"');
    expect(immediateDebit).toContain('await auditEscrowNonBloquant(');
    expect(immediateDebit).not.toContain('await auditEscrow(admin, "ESCROW_DEBIT_INITIE"');
  });

  it('applique l’incident de débit par CAS INITIE atomique, cron comme webhook', () => {
    expect(debitIncidentMigration).toContain("AND pe.statut = 'INITIE'");
    expect(debitIncidentMigration).toContain('FOR UPDATE');
    expect(debitIncidentMigration).toContain("SET statut = 'ECHOUE'");
    expect(debitIncidentMigration).toContain("AND statut = 'INITIE'");
    expect(debitIncidentMigration).toContain('RETURN false');
    expect(debit).not.toContain('admin.rpc("fn_escrow_marquer_incident"');
    expect(debit).toContain('admin.rpc("fn_escrow_marquer_echec_debit"');

    const paymentFailedStart = webhook.indexOf(
      'event.type === "payment_intent.payment_failed"',
    );
    const paymentFailedEnd = webhook.indexOf(
      '// Handle payment_intent.succeeded (backup reconciliation)',
      paymentFailedStart,
    );
    const paymentFailed = webhook.slice(paymentFailedStart, paymentFailedEnd);
    expect(paymentFailed).toContain('"fn_escrow_marquer_echec_debit"');
    expect(paymentFailed).not.toContain('"fn_escrow_marquer_incident"');
  });
});

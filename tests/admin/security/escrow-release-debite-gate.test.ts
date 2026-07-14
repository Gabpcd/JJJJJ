import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const edge = readFileSync(
  join(process.cwd(), 'supabase/functions/escrow-release/index.ts'),
  'utf8',
);

const migration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260713221941_verrou_release_escrow_debite.sql'),
  'utf8',
);
const recoveryMigration = readFileSync(
  join(process.cwd(), 'supabase/migrations/20260714055000_recuperer_payout_escrow_ambigu.sql'),
  'utf8',
);
const payoutGuard = readFileSync(
  join(process.cwd(), 'supabase/functions/_shared/stripe-escrow-payout.ts'),
  'utf8',
);
const webhook = readFileSync(
  join(process.cwd(), 'supabase/functions/_shared/stripe-webhook-handler.ts'),
  'utf8',
);

describe('release escrow — débit confirmé obligatoire', () => {
  it('exclut en base toute file dont l’escrow exact n’est pas DEBITE', () => {
    expect(migration).toMatch(/AND pe\.statut = 'DEBITE'/);
    expect(migration).toContain('fn_escrow_releases_a_traiter');
  });

  it('relit puis réserve atomiquement DEBITE avant de créer le payout', () => {
    const create = edge.indexOf('stripe.payouts.create(');
    const reservation = edge.lastIndexOf('.eq("statut", "DEBITE")', create);
    expect(edge).toContain('.select("statut, stripe_payout_id")');
    expect(edge).toContain('!["DEBITE", "RELEASE_PLANIFIE"].includes(escrowCourant.statut)');
    expect(reservation).toBeGreaterThan(0);
    expect(reservation).toBeLessThan(create);
    expect(edge.slice(reservation, create)).toContain('releaseReservee = true');
  });

  it('ne transforme jamais INITIE en DEBITE dans le consumer de payout', () => {
    expect(edge).not.toMatch(/statut:\s*"DEBITE"[\s\S]{0,180}\.eq\("statut",\s*"INITIE"\)/);
  });

  it('réutilise une tentative ambiguë et versionne seulement après un payout terminal connu', () => {
    expect(edge).toContain('release_${rel.paiement_escrow_id}_after_${precedent.id}');
    expect(edge).toContain('["pending", "in_transit", "paid"]');
    expect(edge).toContain('if (releaseReservee && !postPayoutAmbigu)');
  });

  it('délie atomiquement le payout terminal avant de persister sa nouvelle version', () => {
    const terminal = edge.indexOf('const { data: terminalReouvert');
    const version = edge.indexOf(
      'payoutIdempotencyKey = `release_${rel.paiement_escrow_id}_after_${precedent.id}`',
      terminal,
    );
    const create = edge.indexOf('stripe.payouts.create(', version);
    const bindNew = edge.indexOf(
      'await persistExactEscrowPayout(admin, payoutExpected, payoutObserve)',
      create,
    );
    const terminalBlock = edge.slice(terminal, version);

    expect(terminal).toBeGreaterThan(0);
    expect(terminalBlock).toContain('statut: "DEBITE"');
    expect(terminalBlock).toContain('stripe_payout_id: null');
    expect(terminalBlock).toContain('.eq("stripe_payout_id", precedent.id)');
    expect(edge.indexOf('payoutObserve = null', version)).toBeLessThan(create);
    expect(bindNew).toBeGreaterThan(create);
  });

  it('récupère un lease EN_COURS et un RELEASE_PLANIFIE sans borne terminale', () => {
    expect(recoveryMigration).toContain("q.statut IN ('EN_ATTENTE', 'EN_COURS')");
    expect(recoveryMigration).toContain("OR pe.statut = 'RELEASE_PLANIFIE'");
    expect(edge).toContain('.in("statut", ["EN_ATTENTE", "EN_COURS"])');
    expect(edge).toContain('.lte("prochaine_tentative_le"');
    expect(edge).toContain('Math.min((rel.tentatives ?? 0) + 1, 4)');
  });

  it('recherche exhaustivement le payout metadata exact avant toute nouvelle création', () => {
    const search = edge.indexOf('async function findEscrowPayoutsByMetadata');
    const create = edge.indexOf('stripe.payouts.create(');
    expect(search).toBeGreaterThan(0);
    expect(search).toBeLessThan(create);
    expect(edge).toContain('stripe.payouts.list(');
    expect(edge).toContain('starting_after: startingAfter');
    expect(edge).toContain('if (!page.has_more) break');
    expect(edge).toContain(
      'payout.metadata?.paiement_escrow_id === paiementEscrowId',
    );
    expect(edge).toContain('ESCROW_PAYOUT_DUPLICATE_ACTIVE');
  });

  it('valide montant, devise et metadata exacts avant rattachement ou promotion', () => {
    expect(payoutGuard).toContain('payout.amount !== expected.amountCents');
    expect(payoutGuard).toContain('payout.currency !== "eur"');
    expect(payoutGuard).toContain('payout.metadata?.type !== "ESCROW_RELEASE"');
    expect(payoutGuard).toContain(
      'payout.metadata?.paiement_escrow_id !== expected.paiementEscrowId',
    );
    expect(payoutGuard).toContain('payout.metadata?.mission_id !== expected.missionId');
    expect(payoutGuard).toContain('payout.metadata?.soignant_id !== expected.soignantId');
    expect(edge).toContain('requireExactEscrowPayout(precedent, payoutExpected)');
    expect(edge).toContain('requireExactEscrowPayout(payout, payoutExpected)');
  });

  it('ne rollback jamais RELEASE_PLANIFIE après appel Stripe ou résultat observé', () => {
    const catchStart = edge.indexOf('} catch (err: any)');
    const catchBlock = edge.slice(catchStart);
    const payoutCall = edge.indexOf('payoutCallStarted = true');
    const create = edge.indexOf('stripe.payouts.create(', payoutCall);

    expect(payoutCall).toBeGreaterThan(0);
    expect(payoutCall).toBeLessThan(create);
    expect(catchBlock).toContain(
      'const postPayoutAmbigu = payoutCallStarted || payoutObserve !== null || repriseAmbigue',
    );
    expect(catchBlock).toContain('if (releaseReservee && !postPayoutAmbigu)');
    expect(catchBlock).toContain('findEscrowPayoutsByMetadata(');
    expect(catchBlock).toContain('persistExactEscrowPayout(');
    expect(catchBlock).toContain('statut: postPayoutAmbigu');
    expect(catchBlock).not.toContain('if (releaseReservee) {');
  });

  it.each([
    ['payout.paid', '"paid"', 'fn_escrow_confirmer_payout'],
    ['payout.failed', '"failed"', 'fn_escrow_echouer_payout'],
    ['payout.canceled', '"canceled"', 'fn_escrow_echouer_payout'],
  ])('valide exactement %s avant la RPC financière', (eventType, status, rpc) => {
    const start = webhook.indexOf(`event.type === "${eventType}"`);
    const validation = webhook.indexOf('await loadAndValidateEscrowPayout(', start);
    const statusArg = webhook.indexOf(status, validation);
    const transition = webhook.indexOf(rpc, validation);

    expect(start).toBeGreaterThan(0);
    expect(validation).toBeGreaterThan(start);
    expect(statusArg).toBeGreaterThan(validation);
    expect(transition).toBeGreaterThan(statusArg);
  });
});

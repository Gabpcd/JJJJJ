import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const EDGE_PATH = 'supabase/functions/create-mission-payment/index.ts';
const MIGRATION_PATH = 'supabase/migrations/20260713229000_atomic_reservation_paiement_mission.sql';
const LIST_PATH = 'src/components/ListeCandidatures.tsx';
const MODAL_PATH = 'src/components/ModalPaiementCommission.tsx';

const edge = readFileSync(EDGE_PATH, 'utf8');
const migration = readFileSync(MIGRATION_PATH, 'utf8');
const list = readFileSync(LIST_PATH, 'utf8');
const modal = readFileSync(MODAL_PATH, 'utf8');

describe('Paiement mission — persistance et attribution atomiques', () => {
  it('refuse avant Stripe toute mission qui n’est plus OUVERTE et non attribuée', () => {
    const stateGuard = edge.indexOf(
      'mission.statut !== "OUVERTE" || mission.soignant_assigne_id !== null',
    );
    const stripeCreate = edge.indexOf('stripe.paymentIntents.create(');

    expect(edge).toContain('statut, soignant_assigne_id');
    expect(stateGuard).toBeGreaterThan(-1);
    expect(stripeCreate).toBeGreaterThan(stateGuard);
    expect(edge).toContain('error: "MISSION_STATE_CHANGED"');
  });

  it('ne masque aucune erreur Supabase critique avant la création financière', () => {
    expect(edge).toContain('if (authError || !user?.email)');
    expect(edge).toContain('if (userRoleError)');
    expect(edge).toContain('if (errM)');
    expect(edge).toContain('if (existingPaymentError)');
    expect(edge).toContain('if (customerPersistError || !customerPersisted)');
    expect(edge).toContain('if (paiementSynchroniseError || !paiementSynchronise)');
  });

  it('verrouille mission et paiement dans le RPC réservé au service role', () => {
    expect(edge).toContain('fn_enregistrer_reservation_paiement_mission');
    expect(edge).not.toContain('.from("paiements_mission").insert(');
    expect(migration).toContain('FROM public.missions m');
    expect(migration).toContain('FOR UPDATE;');
    expect(migration).toContain("v_mission.statut IS DISTINCT FROM 'OUVERTE'");
    expect(migration).toContain('v_mission.soignant_assigne_id IS NOT NULL');
    expect(migration).toContain('FROM PUBLIC, anon, authenticated');
    expect(migration).toContain('TO service_role');
  });

  it('compense un PaymentIntent non durable et rend une erreur réessayable', () => {
    expect(edge).toContain('stripe.paymentIntents.cancel(');
    expect(edge).toContain('cancel_${paymentIntent.id}_persistence_failure');
    expect(edge).toContain('class RetryablePaymentPersistenceError');
    expect(edge).toContain('error: "PAYMENT_PERSISTENCE_FAILED"');
    expect(edge).toContain('retryable: true');
    expect(edge).toContain('status: 503');
  });

  it('persiste avant de renvoyer succès ou client_secret', () => {
    const autoStart = edge.indexOf('if (defaultPM)');
    const manualStart = edge.indexOf('// No saved card');
    const autoBlock = edge.slice(autoStart, manualStart);
    const manualBlock = edge.slice(manualStart);

    expect(autoBlock.indexOf('await enregistrerPaiement(paymentIntent.id, "AUTORISE")'))
      .toBeLessThan(autoBlock.indexOf('auto_charged: true'));
    expect(manualBlock.indexOf('await enregistrerPaiement(paymentIntent.id, "EN_ATTENTE")'))
      .toBeLessThan(manualBlock.indexOf('client_secret: paymentIntent.client_secret'));
  });

  it('vérifie exactement le PaymentIntent après confirmPayment avant attribution', () => {
    expect(edge).toContain('precedent.amount !== amountCents');
    expect(edge).toContain('precedent.currency !== "eur"');
    expect(edge).toContain('precedent.capture_method !== "manual"');
    expect(edge).toContain('precedent.metadata?.mission_id !== mission.id');
    expect(edge).toContain('precedent.metadata?.etablissement_id !== mission.etablissement_id');
    expect(edge).toContain('precedentCustomerId !== etab.stripe_customer_id');
    expect(edge).toContain('await enregistrerPaiement(precedent.id, "AUTORISE")');

    expect(modal).toContain('await onSuccess()');
    expect(list).toContain('verifierPaiementPuisAccepter');
    expect(list).toContain("data?.statut !== 'AUTORISE' && data?.statut !== 'CAPTURE'");
    expect(list.indexOf("body: { mission_id: missionId }", list.indexOf('verifierPaiementPuisAccepter')))
      .toBeLessThan(list.indexOf('await finaliserAcceptation(candidatureId)', list.indexOf('verifierPaiementPuisAccepter')));
  });

  it('bloque en base toutes les portes d’attribution sans réservation autorisée', () => {
    expect(migration).toContain('fn_exiger_reservation_avant_attribution');
    expect(migration).toContain("v_mode IS DISTINCT FROM 'STRIPE_RESERVATION'");
    expect(migration).toContain("v_paiement.statut NOT IN ('AUTORISE', 'CAPTURE')");
    expect(migration).toContain('v_paiement.montant_ttc IS DISTINCT FROM NEW.montant_commission_ttc');
    expect(migration).toContain('CREATE TRIGGER trg_exiger_reservation_avant_attribution');
    expect(migration).toContain("NEW.statut = 'ASSIGNEE'::public.statut_mission");
  });
});

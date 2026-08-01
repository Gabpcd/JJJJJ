import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const checkout = readFileSync('src/components/StripeEmbeddedCheckout.tsx', 'utf8');
const detail = readFileSync('src/pages/DetailMission.tsx', 'utf8');
const migration = readFileSync(
  'supabase/migrations/20260801212950_dedupliquer_revenus_connect_soignant.sql',
  'utf8',
);

describe('DetailMission — confirmation Stripe Connect fail-closed', () => {
  it('attend le callback asynchrone en conservant l’état de confirmation', () => {
    expect(checkout).toContain('onComplete?: () => void | Promise<void>');
    expect(checkout).toContain('setConfirming(true)');
    expect(checkout).toContain('await onComplete?.()');
    expect(checkout).toContain('finally');
    expect(checkout).not.toContain("toast.success('Paiement envoyé avec succès !')");
  });

  it('ne déclare le paiement réussi qu’après lecture du transfer de la session Checkout courante', () => {
    expect(detail).toContain(".from('stripe_transfers')");
    expect(detail).toContain(".select('statut')");
    expect(detail).toContain(".eq('mission_id', missionId)");
    expect(detail).toContain(".eq('etablissement_id', etablissementId)");
    expect(detail).toContain(".eq('stripe_checkout_session_id', checkoutSessionId)");
    expect(detail).not.toContain(".order('cree_le', { ascending: false })");
    expect(detail).toContain("['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'].includes(statut)");
    expect(detail).toContain("statut === 'ECHOUE'");
    expect(detail).toContain("toast.success('Paiement confirmé et enregistré.')");
    expect(detail).toContain("toast.error('Le paiement Stripe a échoué. Aucun paiement n’a été enregistré.')");
    expect(detail).toContain('La confirmation est encore en cours');
    expect(detail).not.toContain('Les honoraires du soignant ont été transmis via Stripe');
  });

  it('exige et transmet l’identifiant de la session Checkout préparée', () => {
    const edgeFunction = readFileSync(
      'supabase/functions/stripe-connect-pay-mission/index.ts',
      'utf8',
    );

    expect(detail).toContain('!data?.checkout_session_id');
    expect(detail).toContain('setConnectCheckoutSessionId(data.checkout_session_id)');
    expect(detail).toContain('connectCheckoutSessionId,');
    expect(edgeFunction).toContain('checkout_session_id: derniereSessionMission.id');
    expect(edgeFunction).toContain('checkout_session_id: session.id');
  });

  it('exécute atomiquement la migration avec un search_path vide', () => {
    expect(migration.trimStart().startsWith('BEGIN;')).toBe(true);
    expect(migration).toContain("SET search_path TO ''");
    expect(migration.trimEnd().endsWith('COMMIT;')).toBe(true);
  });
});

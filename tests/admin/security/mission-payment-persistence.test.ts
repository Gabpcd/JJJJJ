import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const EDGE_PATH = 'supabase/functions/create-mission-payment/index.ts';
const MIGRATION_PATH =
  'supabase/migrations/20260714014100_desactiver_reservation_carte_prelaunch.sql';
const LIST_PATH = 'src/components/ListeCandidatures.tsx';
const PROFILE_PATH = 'src/pages/ProfilEtablissement.tsx';
const DETAIL_PATH = 'src/pages/DetailMission.tsx';

const edge = readFileSync(EDGE_PATH, 'utf8');
const migration = readFileSync(MIGRATION_PATH, 'utf8');
const list = readFileSync(LIST_PATH, 'utf8');
const profile = readFileSync(PROFILE_PATH, 'utf8');
const detail = readFileSync(DETAIL_PATH, 'utf8');

describe('Paiement mission — STRIPE_RESERVATION désactivé au lancement', () => {
  it('authentifie et contrôle la permission avant un refus explicite', () => {
    const auth = edge.indexOf('verifyUserOrServiceRole(req)');
    const permission = edge.indexOf('fn_a_permission_etablissement');
    const disabled = edge.indexOf('error: "STRIPE_RESERVATION_DISABLED"');

    expect(auth).toBeGreaterThan(-1);
    expect(permission).toBeGreaterThan(auth);
    expect(disabled).toBeGreaterThan(permission);
    expect(edge).toContain('status: 410');
  });

  it('ne peut créer, confirmer ou capturer aucun objet Stripe', () => {
    expect(edge).not.toContain('npm:stripe');
    expect(edge).not.toContain('paymentIntents.create');
    expect(edge).not.toContain('paymentIntents.confirm');
    expect(edge).not.toContain('paymentIntents.capture');
    expect(edge).not.toContain('client_secret');
  });

  it('migre seulement le mode legacy vers la facture mensuelle', () => {
    expect(migration).toContain("SET mode_paiement_commission = 'FACTURE_MENSUELLE'");
    expect(migration).toContain("WHERE mode_paiement_commission = 'STRIPE_RESERVATION'");
    expect(migration).toContain("ALTER COLUMN mode_paiement_commission SET DEFAULT 'FACTURE_MENSUELLE'");
    expect(migration).not.toMatch(/ARRAY\[[^\]]*STRIPE_RESERVATION/);
    expect(migration).toContain("'SEPA_DEBIT'::text");
    expect(migration).toContain("'CHORUS_PRO'::text");
  });

  it('retire la réservation carte du parcours établissement et de l’acceptation', () => {
    expect(profile).not.toContain("value: 'STRIPE_RESERVATION'");
    expect(detail).not.toContain("mode_paiement_commission === 'STRIPE_RESERVATION'");
    expect(list).not.toContain("modePaiement === 'STRIPE_RESERVATION'");
    expect(list).not.toContain('create-mission-payment');
    expect(list).not.toContain('ModalPaiementCommission');
  });
});

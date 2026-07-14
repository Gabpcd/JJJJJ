import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714035033_securiser_modification_mode_paiement_etablissement.sql',
  'utf8',
);
const profile = readFileSync('src/pages/ProfilEtablissement.tsx', 'utf8');
const invoices = readFileSync('src/pages/FacturationEtablissement.tsx', 'utf8');
const createInvoice = readFileSync(
  'supabase/functions/create-invoice-payment/index.ts',
  'utf8',
);

describe('Établissement — mode de paiement commission', () => {
  it('réserve la modification au RPC propriétaire et à trois modes de lancement', () => {
    expect(migration).toContain('v_etab_id uuid := public.mon_etablissement_id()');
    expect(migration).toContain('auth.uid() IS NULL OR v_etab_id IS NULL');
    expect(migration).toContain("'FACTURE_MENSUELLE', 'SEPA_DEBIT', 'CHORUS_PRO'");
    expect(migration).not.toContain("p_mode_paiement_commission = 'STRIPE_RESERVATION'");
    expect(migration).toContain("p_mode_paiement_commission = 'CHORUS_PRO'");
    expect(migration).toContain('NOT v_etab.est_secteur_public');
    expect(migration).toContain("p_mode_paiement_commission = 'SEPA_DEBIT'");
    expect(migration).toContain("v_etab.stripe_customer_id !~ '^cus_");
    expect(migration).toContain("v_etab.stripe_sepa_payment_method_id !~ '^pm_");
  });

  it('ouvre le bypass commercial seulement autour de l’UPDATE validé', () => {
    const enable = migration.indexOf("set_config('app.internal_operation', 'true', true)");
    const update = migration.indexOf('UPDATE public.etablissements', enable);
    const disable = migration.indexOf("set_config('app.internal_operation', 'false', true)", update);

    expect(enable).toBeGreaterThan(0);
    expect(update).toBeGreaterThan(enable);
    expect(disable).toBeGreaterThan(update);
    expect(migration).toContain('FOR UPDATE');
    expect(migration).toContain("'ETABLISSEMENT_MODIFICATION'");
    expect(migration).toContain('FROM PUBLIC, anon');
    expect(migration).toContain('TO authenticated, service_role');
  });

  it('affiche les erreurs métier renvoyées par le RPC au lieu d’un faux succès', () => {
    expect(profile).toContain('data: saveResult');
    expect(profile).toContain("'error' in saveResult");
    expect(profile).toContain('saveBusinessError || extraireMessageErreur(error)');
  });

  it('interdit le double paiement manuel d’une facture en mode SEPA', () => {
    expect(createInvoice).toContain('mode_paiement_commission === "SEPA_DEBIT"');
    expect(createInvoice).toContain('FACTURE_RESERVEE_SEPA');
    expect(invoices).toContain("etab?.mode_paiement_commission !== 'SEPA_DEBIT'");
    expect(invoices).toContain("etab?.mode_paiement_commission === 'SEPA_DEBIT'");
  });
});

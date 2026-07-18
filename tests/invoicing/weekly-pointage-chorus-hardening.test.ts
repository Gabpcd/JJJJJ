import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260718122441_fiabiliser_pointage_facturation_hebdo_chorus.sql');
const manualPaymentMigration = read('supabase/migrations/20260718124959_declarer_paiement_facture_hebdomadaire.sql');
const periodAmountMigration = read('supabase/migrations/20260718130658_autoriser_montant_facture_periode.sql');
const storageMigration = read('supabase/migrations/20260718130836_autoriser_facturx_xml_storage.sql');
const defactoMigration = read('supabase/migrations/20260718131005_corriger_trigger_defacto_facture_emise.sql');
const generateInvoice = read('supabase/functions/generate-invoice/index.ts');
const connect = read('supabase/functions/stripe-connect-pay-mission/index.ts');
const webhook = read('supabase/functions/_shared/stripe-webhook-handler.ts');
const chorus = read('supabase/functions/chorus-pro-deposit/index.ts');
const facturationUi = read('src/pages/FacturationEtablissement.tsx');

describe('Pointage, facturation hebdomadaire et commission Chorus', () => {
  it('calcule le temps sur tous les créneaux EFFECTIF et conserve les pauses', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.dec_calculer_duree_presence()');
    expect(migration).toContain("mc.type_creneau = 'EFFECTIF'");
    expect(migration).toContain('sum(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 60.0)');
    expect(migration).toContain('NEW.heures_reelles := round(NEW.duree_nette_min / 60.0, 2)');
    expect(migration).toContain('NEW.duree_pause_min := round(');
  });

  it('autorise uniquement les périodes closes des missions longues en cours', () => {
    expect(generateInvoice).toContain("mission.strategie_facturation !== 'HEBDO_ET_FINALE'");
    expect(generateInvoice).toContain("['EN_COURS', 'TERMINEE'].includes(mission.statut)");
    expect(generateInvoice).toContain('periode_fin >= aujourdHui');
    expect(generateInvoice).toContain("'fn_preparer_facture_commission_periode'");
    expect(migration).toContain('v_fh.est_facture_finale_mission');
    expect(generateInvoice).toContain("'fn_a_permission_etablissement'");
    expect(generateInvoice).toContain("authenticatedUserId !== mission.soignant_assigne_id");
    expect(periodAmountMigration).toContain("v_strategie = 'HEBDO_ET_FINALE'");
    expect(periodAmountMigration).toContain('public.fn_calculer_montant_periode(');
    expect(periodAmountMigration).toContain('v_montant_attendu');
    expect(storageMigration).toContain("'application/xml'");
    expect(storageMigration).toContain("WHERE id = 'jolene-documents'");
    expect(defactoMigration).toContain('SELECT s.defacto_opt_in');
    expect(defactoMigration.split('AS $$')[1]).not.toContain('v_soignant.mandat_facturation_signe');
    expect(generateInvoice).toContain(".update({ statut: 'ERREUR_GENERATION' })");
    expect(generateInvoice).toContain('regenXmlUploadError');
    expect(generateInvoice).toContain('Facture hebdomadaire S${facture.numero_semaine_iso}');
  });

  it('isole chaque semaine dans Stripe et rapproche les deux factures exactes', () => {
    expect(connect).toContain('facture_honoraire_id?: unknown');
    expect(connect).toContain('flow: "CONNECT_INVOICE"');
    expect(connect).toContain('facture_honoraire_id: factureHonoraires.id');
    expect(connect).toContain('payment_scope: invoiceScopedPayment ? "INVOICE" : "MISSION"');
    expect(webhook).toContain('validatedTransferClaim.facture_honoraire_id !== factureHonorairesId');
    expect(webhook).toContain('facture_honoraire_id: factureHonorairesId');
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_stripe_connect_rapprocher_facture(');
    expect(migration).toContain("v_mission.statut NOT IN ('EN_COURS', 'TERMINEE')");
    expect(facturationUi).toContain('Paiement hebdomadaire — période close');
  });

  it('permet aussi de déclarer et confirmer une échéance hebdomadaire sans Stripe', () => {
    expect(manualPaymentMigration).toContain('CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_facture_soignant(');
    expect(manualPaymentMigration).toContain("v_fh.periode_fin >= CURRENT_DATE");
    expect(manualPaymentMigration).toContain('p.facture_honoraire_id = v_fh.id');
    expect(manualPaymentMigration).toContain("SET statut = 'PAYEE'");
    expect(facturationUi).toContain("'fn_declarer_paiement_facture_soignant'");
    expect(facturationUi).toContain('Échéances à payer aux soignants');
  });

  it('dépose la facture de commission Jolene avec le RBAC établissement', () => {
    expect(generateInvoice).toContain("functions.invoke('chorus-pro-deposit'");
    expect(chorus).toContain("p_permission: 'paiement'");
    expect(chorus).toContain('facture.etablissement_id');
    expect(chorus).not.toContain('facture.etablissement_id !== userId');
    expect(chorus).not.toContain('date_echeance, description');
    expect(chorus).toContain("MISE_A_DISPOSITION: 'RECUE'");
    expect(chorus).toContain("MANDATEE: 'MANDATEE'");
  });
});

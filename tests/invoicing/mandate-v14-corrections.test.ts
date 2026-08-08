import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

const mandat = read('supabase/functions/_shared/invoicing-mandate.ts');
const mandatPage = read('src/pages/MandatFacturation.tsx');
const missionForm = read('src/components/FormulaireMission.tsx');
const missionRecap = read('src/components/mission/ModalRecapMission.tsx');
const migration = read('supabase/migrations/20260808150856_aligner_mandat_facturation_tva_et_periodes.sql');
const generateInvoice = read('supabase/functions/generate-invoice/index.ts');
const sendEmail = read('supabase/functions/send-email/index.ts');
const caregiverInvoices = read('src/pages/MesFacturesHonoraires.tsx');
const submitToChorus = read('supabase/functions/submit-to-chorus/index.ts');
const chorusCommission = read('supabase/functions/chorus-pro-deposit/index.ts');
const sharedCii = read('supabase/functions/_shared/facturx-builder.ts');
const adminDisputeModal = read('src/components/admin/litiges/LitigeResolutionModal.tsx');
const mandateEdge = read('supabase/functions/sign-invoicing-mandate/index.ts');
const webhook = read('supabase/functions/_shared/stripe-webhook-handler.ts');
const billingPage = read('src/pages/FacturationEtablissement.tsx');
const disputeWizard = read('src/components/litige/WizardOuvertureLitige.tsx');
const planningMigration = read('supabase/migrations/20260801091225_aligner_planning_exact_candidature_creation_edition.sql');
const connect = read('supabase/functions/stripe-connect-pay-mission/index.ts');
const expireDisputeCheckout = read('supabase/functions/expire-invoice-checkout-for-dispute/index.ts');
const escrow = read('supabase/functions/escrow-debit-echeance/index.ts');
const caregiverMission = read('src/pages/DetailMissionSoignant.tsx');
const adminVatReviews = read('src/components/admin/RevuesTvaMissions.tsx');
const termsPage = read('src/pages/PageCGU.tsx');
const caregiverMissionSwipe = read('src/components/swipe/ModalDetailMissionSwipe.tsx');
const honorariaPdfDownload = read('src/lib/facture-honoraires-pdf.ts');

function functionBody(source: string, name: string): string {
  const marker = `CREATE OR REPLACE FUNCTION public.${name}`;
  const start = source.lastIndexOf(marker);
  expect(start).toBeGreaterThanOrEqual(0);
  const end = source.indexOf('$body$;', start);
  return source.slice(start, end > start ? end + '$body$;'.length : undefined);
}

describe('mandat de facturation v1.4 et corrections comptables', () => {
  it('sépare intégralement les honoraires de la commission Jolene', () => {
    expect(mandat).toContain("MANDAT_FACTURATION_VERSION = '1.4'");
    expect(mandat).toContain("# Mandat de facturation et instructions de paiement");
    expect(mandat).toContain("l'intégralité des honoraires TTC dus au Soignant");
    expect(mandat).toContain('Les frais Jolene ne sont pas déduits des honoraires');
    expect(mandat).not.toContain('déduction faite de la commission');
    expect(mandat).toContain("facturée séparément à l'Établissement");
  });

  it('sépare le statut TVA du soignant de la nature TVA confirmée par mission', () => {
    expect(mandat).toContain("value: 'FRANCHISE_EN_BASE'");
    expect(mandat).toContain("value: 'REDEVABLE_TVA'");
    expect(mandat).not.toContain("value: 'EXONERE_ART_261_4_1'");
    expect(mandat).toContain("l'Établissement qualifie la prestation");
    expect(mandat).toContain('la mission reste active mais la facturation est suspendue');
    expect(mandatPage).toContain("functions.invoke('sign-invoicing-mandate'");
    expect(mandatPage).toContain('STATUTS_TVA_HONORAIRES.map');
    expect(mandatPage).toContain('Activité professionnelle à compléter');
    expect(migration).toContain('IF v_soignant.type_exercice IS NULL');
    expect(missionForm).toContain('Nature TVA prévue de la prestation libérale');
    expect(missionForm).toContain('professionnel médical ou paramédical réglementé');
    expect(missionForm).toContain('Voir la doctrine fiscale officielle');
    expect(caregiverMission).toContain('Critères officiels');
    expect(missionForm).toContain('p_nature_tva_prestation');
    expect(migration).toContain('nature_tva_prestation');
    expect(migration).toContain('RETURNING nature_tva_prestation, statut_validation_tva');
    expect(migration).toContain("'nature_tva_prestation', v_nature_effective");
    expect(migration).toContain('statut_validation_tva');
    expect(migration).toContain('fn_confirmer_nature_tva_mission');
    expect(migration).toContain('fn_admin_proposer_nature_tva_mission');
    expect(caregiverMission).toContain('Un désaccord n\'annule pas la mission');
    expect(adminVatReviews).toContain('L\'admin propose ; le soignant confirme');
  });

  it('limite le verrou TVA à la facture primaire et laisse les litiges modifier la mission', () => {
    const vatProtection = functionBody(migration, 'fn_proteger_validation_tva_mission');
    const vatTriggerStart = migration.indexOf('CREATE TRIGGER trg_05_proteger_validation_tva_mission');
    const vatTriggerEnd = migration.indexOf('FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_validation_tva_mission();', vatTriggerStart);
    const vatTrigger = migration.slice(vatTriggerStart, vatTriggerEnd);
    const correctionBranch = generateInvoice.indexOf('if (facture_id && !mission_id)');
    const primaryVatGate = generateInvoice.indexOf("error: 'VALIDATION_TVA_MISSION_REQUISE'");

    expect(vatProtection).toContain("les corrections de litige ne sont volontairement pas concernés");
    expect(vatTrigger).not.toContain('duree_heures');
    expect(vatTrigger).not.toContain('taux_horaire_base');
    expect(vatTrigger).not.toContain('presences');
    expect(vatTrigger).not.toContain('statut,');
    expect(correctionBranch).toBeGreaterThanOrEqual(0);
    expect(primaryVatGate).toBeGreaterThan(correctionBranch);
    expect(generateInvoice).toContain('La mission et ses litiges restent actifs ; seule l’émission de la facture est suspendue.');
    expect(migration).toContain("'jolene.admin_override_gel', v_mission.id::text, true");
    expect(migration).toContain("'jolene.admin_override_reason'");
    expect(migration).toContain("'Résolution du litige ' || p_litige_id::text");
  });

  it('signe le mandat canonique via une IP capturée côté Edge', () => {
    expect(mandateEdge).toContain("req.headers.get('cf-connecting-ip')");
    expect(mandateEdge).toContain("req.headers.get('x-forwarded-for')");
    expect(mandateEdge).toContain('buildMandatFacturationTexte');
    expect(mandateEdge).toContain('CONTENU_MANDAT_NON_CANONIQUE');
    expect(migration).toContain('fn_signer_mandat_facturation_serveur');
    expect(migration).toContain("p_version IS DISTINCT FROM '1.4'");
    expect(migration).toContain('contenu_texte');
    expect(migration).toContain("now() + interval '10 years'");
  });

  it('retire la rétrocession du lancement dans le front et la bloque côté serveur', () => {
    expect(missionForm).toContain("p_mode_remuneration: 'TAUX_HORAIRE'");
    expect(missionForm).toContain('p_retrocession_pct: null');
    expect(missionForm).not.toContain("modeRemuneration === 'RETROCESSION'");
    expect(missionRecap).not.toContain('Rétrocession au remplaçant');
    expect(migration).toContain('fn_bloquer_retrocession_prelaunch');
    expect(migration).toContain("CHECK (mode_remuneration = 'TAUX_HORAIRE' AND retrocession_pct IS NULL)");
  });

  it('applique exactement le seuil de sept jours et facture seulement le reliquat final', () => {
    expect(migration).toContain("p_fin > p_debut + interval '7 days'");
    expect(migration).toContain("THEN 'HEBDO_ET_FINALE'");
    expect(migration).toContain('(max(fh.periode_fin) + 1)::date AS prochain_debut');
    expect(migration).toContain("COALESCE(derniere_periode.prochain_debut, m.debut_le::date) <= m.fin_le::date");
  });

  it('autorise les corrections de litige sans autoriser deux factures principales concurrentes', () => {
    const periodLock = functionBody(migration, 'fn_verrouiller_periode_facture_honoraires');
    expect(migration).toContain("nature_correction IN ('ORIGINALE', 'REMPLACEMENT', 'COMPLEMENT', 'AVOIR')");
    expect(periodLock).toContain("NEW.nature_correction = 'COMPLEMENT'");
    expect(periodLock).toContain("v_origine.statut NOT IN ('PAYEE', 'FACTORISEE')");
    expect(migration).toContain("v_facture.statut IN ('PAYEE', 'FACTORISEE')");
    expect(migration).toContain("statut IN ('PAYEE', 'FACTORISEE')");
    expect(migration).toContain('FROM public.paiements_escrow pe');
    expect(migration).toContain('FROM public.factor_advances fa');
    expect(periodLock).toContain("fh.nature_correction <> 'COMPLEMENT'");
    expect(migration).toContain("AND type_document = 'FACTURE'\n    AND nature_correction <> 'COMPLEMENT'");
    expect(migration).toContain('fn_admin_resoudre_litige_intelligent');
    expect(migration).toContain("'action_financiere', 'COMPLEMENT'");
    expect(migration).toContain('fn_preparer_commission_complement_honoraires');
    expect(migration).toContain('fn_preparer_commission_remplacement_honoraires');
    expect(migration).toContain('fn_preparer_avoir_commission_honoraires');
    expect(migration).toContain('fn_bloquer_paiement_facture_en_litige');
    expect(migration).toContain("CURRENT_DATE, CURRENT_DATE, 'EN_GENERATION'");
    expect(migration).toContain("v_facture.mode_remboursement = 'AUTO_STRIPE'");
    expect(migration).toContain('Aucun remboursement ne peut précéder son avoir émis');
    expect(migration).toContain('factures_honoraires_rectifications');
    expect(migration).toContain("'action_financiere', 'RECTIFICATION_DESCRIPTIVE'");
    expect(migration).toContain("'action_financiere', 'CORRECTION_PRESENCE_SANS_IMPACT_FACTURE'");
    expect(migration).toContain('fn_solde_correction_facture_honoraires');
    expect(migration).toContain('fn_admin_solde_correction_facture_honoraires');
    expect(migration).toContain('v_nouveau_ttc - v_total_courant_ttc');
    expect(migration).toContain('v_total_courant_ttc - v_nouveau_montant_ttc');
    expect(migration).toContain('Plusieurs avoirs sont admis');
    expect(migration).toContain("statut_litige = 'EN_ATTENTE_LITIGE'");
    expect(adminDisputeModal).toContain("supabase.rpc('fn_admin_solde_correction_facture_honoraires'");
    expect(adminDisputeModal).toContain('solde corrigé');
    expect(adminDisputeModal).toContain('factureLoading ||');
  });

  it('cible la facture exacte et ne suspend pas les autres semaines', () => {
    expect(migration).toContain('p_facture_id uuid');
    expect(migration).toContain("'FACTURE_CONTESTEE_EXPLICITEMENT'");
    expect(disputeWizard).toContain('factureHonorairesId');
    expect(disputeWizard).toContain('p_facture_id');
    expect(disputeWizard).toContain("'FACTORISEE'");
    expect(caregiverInvoices).toContain('Demander une revue');
    expect(caregiverInvoices).toContain("facture.statut_litige === 'EN_ATTENTE_LITIGE'");
    expect(caregiverInvoices).toContain('!verification.litigeActif');
    expect(disputeWizard).toContain('Seule cette échéance sera gelée');
    expect(billingPage).toContain('facturesBloqueesParLitige');
    expect(billingPage).toContain('Échéance indépendante');
    expect(connect).toContain('FACTURE_EN_LITIGE');
    expect(webhook).toContain('CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE');
    expect(expireDisputeCheckout).toContain('checkout.sessions.expire');
    expect(expireDisputeCheckout).toContain('CHECKOUT_EXPIRE_AVANT_CORRECTION_LITIGE');
    expect(expireDisputeCheckout.indexOf('await writeRequiredFinancialAudit')).toBeLessThan(
      expireDisputeCheckout.indexOf('.from("stripe_transfers")\n    .update({ statut: "ANNULEE" })'),
    );
    expect(billingPage).toContain('Cette échéance est suspendue ; les autres périodes restent payables.');
  });

  it('archive des versions documentaires immuables au lieu d’écraser un PDF', () => {
    expect(generateInvoice).toContain("crypto.randomUUID()" );
    expect(generateInvoice).toContain("{ upsert: false }");
    expect(generateInvoice).not.toContain("{ upsert: true }");
    expect(generateInvoice).toContain(".from('factures_honoraires_documents')");
    expect(generateInvoice).toContain('pdf_sha256: pdfSha256');
    expect(generateInvoice).toContain('xml_sha256: xmlSha256');
    expect(migration).toContain('fn_preserver_document_facture_honoraires');
    expect(honorariaPdfDownload).toContain(".select('numero_facture, pdf_s3_key')");
    expect(honorariaPdfDownload).toContain('.createSignedUrl(facture.pdf_s3_key');
    expect(honorariaPdfDownload).toContain('window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000)');
    expect(honorariaPdfDownload).not.toContain("import('jspdf')");
    expect(honorariaPdfDownload).not.toContain(".from('presences')");
    const storageRead = functionBody(migration, 'fn_peut_lire_objet_jolene');
    expect(storageRead).toContain('fh.pdf_s3_key = p_name');
    expect(storageRead).toContain('FROM public.factures_honoraires_documents fhd');
    expect(storageRead).toContain("'lecture_paiement', fh.etablissement_id");
    expect(storageRead).toContain('fh.soignant_id = auth.uid()');
    expect(storageRead).not.toContain("split_part(p_name, '/', 1) = fh.soignant_id");
    expect(migration).toContain('Inventaire SECURITY DEFINER mandat v1.4 incomplet ou périmé');
  });

  it('génère les mentions TVA selon le régime, sans exonération universelle', () => {
    expect(generateInvoice).toContain('TVA non applicable, art. 293 B du CGI');
    expect(generateInvoice).toContain('article 261, 4, 1 du CGI');
    expect(generateInvoice).toContain("vatRate: 20");
    expect(generateInvoice).toContain('soignant.statut_tva_honoraires as StatutTvaHonoraires');
    expect(generateInvoice).toContain('mission.nature_tva_prestation as NatureTvaPrestation');
    expect(generateInvoice).toContain('VALIDATION_TVA_MISSION_REQUISE');
    expect(migration).toContain("m.statut_validation_tva = 'CONFIRMEE'");
    expect(migration).toContain('m.nature_tva_confirmee_par = m.soignant_assigne_id');
    expect(generateInvoice).not.toContain('const vatExempt = !soignant.assujetti_tva');
    expect(generateInvoice).toContain('Article L. 213-98 du CIBS');
    expect(generateInvoice).toContain('Article L. 213-151 du CIBS');
  });

  it('porte quantité et prix unitaire dans le PDF et Factur-X seulement quand le total se réconcilie', () => {
    expect(generateInvoice).toContain('hourlyLineIsConsistent');
    expect(generateInvoice).toContain("const unitCode = hourlyLineIsConsistent ? 'HUR' : 'C62'");
    expect(generateInvoice).toContain('Quantite : ${Number(inv.quantity).toFixed(2)} h');
    expect(generateInvoice).toContain('quantity: Number(facture.quantite_heures_snapshot) || null');
    expect(generateInvoice).toContain('<ram:TypeCode>VAT</ram:TypeCode>');
    expect(generateInvoice).toContain('<ram:SubjectCode>PMD</ram:SubjectCode>');
    expect(generateInvoice).toContain('<ram:SubjectCode>PMT</ram:SubjectCode>');
    expect(generateInvoice).toContain('<ram:URIID schemeID="0002">${buyerSiret}</ram:URIID>');
    expect(generateInvoice).toContain('serviceDate: facture.periode_fin');
  });

  it('produit un avoir CII cohérent : type 381 et montants positifs', () => {
    const ciiGenerator = generateInvoice.slice(
      generateInvoice.indexOf('function generateCiiXml'),
      generateInvoice.indexOf('function escapeXml'),
    );
    expect(generateInvoice).toContain("const typeCode = inv.isAvoir ? '381' : '380'");
    expect(ciiGenerator).not.toContain('const sign = inv.isAvoir ? -1 : 1');
    expect(generateInvoice).toContain('<ram:GrandTotalAmount>${fmtAmt(inv.amountTtc)}</ram:GrandTotalAmount>');
    expect(generateInvoice).toContain('<ram:LineTotalAmount>${fmtAmt(inv.amountHt)}</ram:LineTotalAmount>');
  });

  it('remet chaque document au soignant et ouvre une validation ou contestation exacte', () => {
    expect(migration).toContain('fn_emettre_document_facturation_honoraires');
    expect(migration).toContain('verification_echeance_le');
    expect(migration).toContain('fn_accepter_document_facturation_honoraires');
    expect(migration).toContain('COALESCE(f.emise_le, f.cree_le, f.date_emission::timestamptz)');
    expect(generateInvoice).toContain('notifierEmissionDocument');
    expect(sendEmail).toContain('Vérifier le document');
    expect(caregiverInvoices).toContain('Tout est correct');
    expect(caregiverInvoices).toContain('Signaler une erreur');
    expect(caregiverInvoices).toContain('Télécharger le PDF');
    expect(caregiverInvoices).not.toContain('Télécharger Factur-X');
    expect(submitToChorus).toContain("Deno.env.get('CHORUS_DEPOSIT_MODE_CERTIFIE')");
    expect(submitToChorus).toContain("Deno.env.get('CHORUS_CII_SYNTAXE_CERTIFIEE')");
    expect(submitToChorus).toContain("error: 'CHORUS_FORMAT_NON_CERTIFIE'");
    expect(submitToChorus).toContain("'IN_DP_E1_CII_16B'");
    expect(submitToChorus).toContain("'IN_DP_E1_CII_22B_FE'");
    expect(submitToChorus).toContain("const submissionType = 'DEPOT_XML_API'");
    expect(submitToChorus).not.toContain("syntaxeFlux: 'IN_DP_E2_CII_FACTURX'");
    expect(chorusCommission).toContain("Deno.env.get('CHORUS_CII_SYNTAXE_CERTIFIEE')");
    expect(chorusCommission).toContain("error: 'CHORUS_FORMAT_NON_CERTIFIE'");
    expect(chorusCommission).not.toContain('SIM-${Date.now()}');
    expect(chorusCommission).toContain('La facture reste à déposer.');
    expect(chorusCommission).not.toContain("syntaxeFlux: 'IN_DP_E2_CII_FACTURX'");
    expect(chorusCommission).toContain("Deno.env.get('JOLENE_TVA_ID')");
    expect(sharedCii).toContain('<ram:TypeCode>VAT</ram:TypeCode>');
    expect(sharedCii).not.toContain('const sign = inv.isAvoir ? -1 : 1');
  });

  it('bloque le chevauchement du soignant sans bloquer les besoins simultanés de l’établissement', () => {
    const overlap = planningMigration.slice(
      planningMigration.indexOf('CREATE OR REPLACE FUNCTION public.dec_refuser_chevauchement_soignant()'),
      planningMigration.indexOf('$function$;', planningMigration.indexOf('CREATE OR REPLACE FUNCTION public.dec_refuser_chevauchement_soignant()')),
    );
    expect(overlap).toContain('autre.soignant_assigne_id = NEW.soignant_assigne_id');
    expect(overlap).toContain("autre.statut IN ('ASSIGNEE', 'EN_COURS')");
    expect(overlap).not.toContain('autre.etablissement_id = NEW.etablissement_id');
  });

  it('conserve un paiement unique avec deux créances et les montants exacts', () => {
    expect(connect).toContain('factureCommission?.montant_ttc');
    expect(connect).toContain('factureHonoraires.montant_ttc');
    expect(connect).toContain('unit_amount: commissionCents');
    expect(connect).toContain('unit_amount: soignantCents');
    expect(connect).toContain('paymentIntent.amount !== totalCents');
    expect(connect).toContain('amount: soignantCents');
    expect(escrow).toContain('application_fee_amount: commissionCents');
    expect(escrow).toContain('amount: totalCents');
    expect(escrow).toContain('transfer_data: { destination: onboarding.stripe_account_id }');
  });

  it('présente le paiement rapide comme une instruction de versement et non une arrivée bancaire garantie', () => {
    expect(mandat).toContain("Ce délai vise l'instruction donnée au prestataire de paiement");
    expect(termsPage).toContain("Ce délai concerne l'instruction donnée au prestataire de paiement");
    expect(caregiverMission).toContain('Versement normalement lancé sous 24 à 72 h');
    expect(caregiverMissionSwipe).toContain('Versement normalement lancé sous 24 à 72 h');
    expect(caregiverMission).not.toContain('Payée sous 24 à 72 h');
    expect(caregiverMissionSwipe).not.toContain('Payée sous 24 à 72 h');
  });
});

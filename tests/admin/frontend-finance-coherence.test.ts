import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

describe('cohérence financière des interfaces', () => {
  it('réserve le badge de paiement rapide aux missions libérales', () => {
    const card = read('src/components/swipe/CardMissionSwipe.tsx');
    const modal = read('src/components/swipe/ModalDetailMissionSwipe.tsx');

    expect(card).toContain('missionEstLiberale && mission.paiement_rapide');
    expect(modal.match(/missionEstLiberale && mission\.paiement_rapide/g)?.length)
      .toBeGreaterThanOrEqual(2);
  });

  it('ne décrit jamais la commission Connect comme une retenue soignant', () => {
    const dashboard = read('src/pages/admin/AdminDashboard.tsx');
    expect(dashboard).toContain('Commission facturée (Connect)');
    expect(dashboard).not.toContain('Commission retenue (Connect)');
    expect(dashboard).not.toContain('Commission Jolene retenue sur chaque paiement');
    expect(dashboard).toContain('Honoraires versés aux soignants');
  });

  it('ne promet pas un paiement accéléré en dehors d une mission éligible', () => {
    const checklist = read('src/components/dashboard/ChecklistActivation.tsx');
    const devenirSoignant = read('src/pages/DevenirSoignant.tsx');
    const relanceMandat = read('src/pages/admin/AdminMandatsFacturation.tsx');
    expect(checklist).not.toContain('Stripe (paiement 24-48 h)');
    expect(devenirSoignant).toContain("un paiement accéléré n'est proposé que lorsqu'il est explicitement affiché");
    expect(relanceMandat).toContain("Lorsqu'une mission est explicitement éligible au paiement accéléré");
    expect(relanceMandat).not.toContain('il débloque la facturation automatique et le paiement rapide');
  });

  it('décrit le prélèvement SEPA selon le traitement réel des factures émises', () => {
    const profil = read('src/pages/ProfilEtablissement.tsx');
    const facturation = read('src/pages/FacturationEtablissement.tsx');
    const activation = read('src/pages/ActiverEtablissement.tsx');
    const interfaces = `${profil}\n${facturation}\n${activation}`;

    expect(interfaces).toContain('après leur émission, lors du prochain traitement automatique');
    expect(profil).toContain('Chaque facture de commission indique sa propre échéance');
    expect(facturation).toContain('Générer une facture groupée');
    expect(interfaces).not.toContain('prélevées automatiquement chaque mois');
    expect(interfaces).not.toContain('après chaque mission terminée');
    expect(interfaces).not.toContain('prélevées automatiquement à réception de facture');
    expect(interfaces).not.toContain('prérequis du futur');
  });

  it('ne promet pas un virement Connect immédiat et ne confond pas facture à régler avec impayé', () => {
    const connect = read('src/pages/PageStripeConnect.tsx');
    const dashboardEtablissement = read('src/pages/DashboardEtablissement.tsx');
    expect(connect).toContain('selon le cycle indiqué sur chacune');
    expect(connect).toContain('Virements automatiques pour les périodes facturées');
    expect(connect).not.toContain('directement, sans délai');
    expect(connect).not.toContain('Virements automatiques après chaque mission');
    expect(dashboardEtablissement).toContain('Règlements à effectuer');
    expect(dashboardEtablissement).not.toContain('Impayés — Cliquez pour payer');
  });

  it('distingue facture à régler, retard réel et virement déjà déclaré', () => {
    const facturation = read('src/pages/FacturationEtablissement.tsx');
    expect(facturation).toContain('Factures et règlements en cours');
    expect(facturation).toContain('estFactureRelancable({');
    expect(facturation).toContain('`À régler avant le ${echeanceLisible}`');
    expect(facturation).toContain('`En retard depuis le ${echeanceLisible}`');
    expect(facturation).toContain('Virement déclaré · vérification en cours');
    expect(facturation).toContain('canManagePayments && !virementDeclare');
    expect(facturation).toContain('Période facturée :');
    expect(facturation).toContain('Le montant correspond à cette période, pas nécessairement à toute la mission.');
    expect(facturation).not.toContain('Factures impayées');
    expect(facturation).not.toContain('facture commission impayée');
  });

  it('refuse un PDF de paie incomplet au lieu d inventer une ventilation', () => {
    const page = read('src/pages/BulletinsPaie.tsx');
    const pdf = read('src/lib/bulletin-paie-pdf.ts');
    expect(page).toContain('missionsAvecCotisations.has(b.mission_id)');
    expect(page).toContain('Aucun document comptable incomplet n\'est généré');
    expect(page).toContain('disabled={downloading || !pdfDisponible}');
    expect(pdf).toContain('la simulation PDF ne peut pas être générée de façon fiable');
  });

  it('n invente aucun net salarié dans la facture commission ou l export paie', () => {
    const factureCommission = read('src/lib/facture-commission-pdf.ts');
    const exportPaie = read('src/pages/ExportPaie.tsx');
    expect(factureCommission).toContain("Déterminés par le bulletin de paie de l\\'employeur");
    expect(factureCommission).not.toContain('superBrut * 0.78');
    expect(factureCommission).not.toContain('Cotisations salariales (~22%)');
    expect(exportPaie).not.toContain('brut * 0.78');
    expect(exportPaie).not.toContain('brut * 0.22');
    expect(exportPaie).not.toContain("'Cotisations_salariales', 'Net'");
    expect(exportPaie).toContain('brut à transmettre au moteur de paie');
  });

});

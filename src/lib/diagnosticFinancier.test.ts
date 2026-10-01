import { describe, expect, it } from 'vitest';
import { ERREUR_DIAGNOSTIC_FINANCIER, lireDiagnosticFinancier } from './diagnosticFinancier';

function resultat() {
  return {
    success: true, controle_documentaire_version: 2, genere_le: '2026-10-01T12:00:00Z',
    factures_verifiees: 2,
    missions_incoherentes: { count: 0, echantillon: [] },
    factures_ecart_mission: { count: 0, echantillon: [] },
    stripe_transfers_orphelins: { count: 0, echantillon: [] },
    factures_non_verifiables: { count: 0, echantillon: [] },
  };
}

describe('Résultat du diagnostic financier', () => {
  it('accepte une réponse complète et ne recalcule aucun montant côté client', () => {
    const value = resultat();
    expect(lireDiagnosticFinancier(value)).toBe(value);
  });

  it('conserve un avoir non vérifiable séparé des deux pièces contrôlées', () => {
    const value = { ...resultat(), factures_non_verifiables: { count: 1, echantillon: [
      { facture_id: 'avoir', numero_facture: 'AVOIR-20', mission_id: 'mission', motif: 'CORRECTION_MONETAIRE' },
    ] } };
    const diagnostic = lireDiagnosticFinancier(value);
    expect(diagnostic.factures_non_verifiables.count).toBe(1);
    expect(diagnostic.factures_verifiees).toBe(2);
    expect(diagnostic.factures_ecart_mission.count).toBe(0);
  });

  it('conserve le véritable écart serveur 90 contre 80 et les pièces sans mission', () => {
    const value = { ...resultat(), factures_ecart_mission: { count: 1, echantillon: [
      { facture_id: 'facture', numero_facture: 'FACTURE-90', mission_id: null, montant_ht: 90, attendu_ht: 80, ecart: 10 },
    ] } };
    expect(lireDiagnosticFinancier(value).factures_ecart_mission.echantillon[0].ecart).toBe(10);
  });

  it.each([
    null, {}, { success: false, error: 'column mc.fin_le does not exist' },
    { ...resultat(), controle_documentaire_version: undefined },
    { ...resultat(), factures_non_verifiables: undefined },
    { ...resultat(), genere_le: 'invalide' },
    { ...resultat(), factures_verifiees: -1 },
    { ...resultat(), missions_incoherentes: { count: NaN, echantillon: [] } },
    { ...resultat(), factures_ecart_mission: { count: 1, echantillon: [] } },
    { ...resultat(), stripe_transfers_orphelins: { count: 0, echantillon: [{}] } },
    { ...resultat(), factures_non_verifiables: { count: 1, echantillon: [
      { facture_id: 'avoir', numero_facture: 'AVOIR-20', mission_id: 'mission', motif: 'SQL_BRUT_INATTENDU' },
    ] } },
    { ...resultat(), factures_ecart_mission: { count: 1, echantillon: [
      { facture_id: 'facture', numero_facture: 'FACTURE-90', mission_id: 'mission', montant_ht: 90, attendu_ht: Infinity, ecart: 10 },
    ] } },
    { ...resultat(), factures_verifiees: 0, factures_ecart_mission: { count: 1, echantillon: [
      { facture_id: 'facture', numero_facture: 'FACTURE-90', mission_id: 'mission', montant_ht: 90, attendu_ht: 80, ecart: 10 },
    ] } },
  ])('refuse un résultat incomplet ou ancien sans afficher son erreur interne %#', value => {
    expect(() => lireDiagnosticFinancier(value)).toThrow(ERREUR_DIAGNOSTIC_FINANCIER);
  });
});

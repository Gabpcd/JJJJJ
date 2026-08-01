import { describe, expect, it } from 'vitest';
import {
  enrichirFacturesHonoraires,
  factureCompteDansTotal,
  factureEstAvoir,
  facturePdfDisponible,
  libelleStatutFacture,
  montantTtcSigneFacture,
  regrouperFacturesParMission,
  resumerFacturesMission,
  selectionnerFactureAffichable,
  totalFacturesComptabilisables,
  totalFacturesEnAttente,
  totalFacturesPayees,
} from './factureHonorairesUi';

describe('factureHonorairesUi', () => {
  const factures = [
    { id: 'payee', statut: 'PAYEE', montant_ttc: 500, date_emission: '2026-07-18' },
    { id: 'erreur-1', statut: 'ERREUR_GENERATION', montant_ttc: 500, date_emission: '2026-07-18' },
    { id: 'erreur-2', statut: 'ERREUR_GENERATION', montant_ttc: 500, date_emission: '2026-07-18' },
    { id: 'emise', statut: 'EMISE', montant_ttc: 200, date_emission: '2026-07-19' },
    { id: 'annulee', statut: 'ANNULEE', montant_ttc: 300, date_emission: '2026-07-20' },
  ];

  it('exclut les erreurs, brouillons, annulations, remplacements et remboursements des totaux', () => {
    expect(totalFacturesComptabilisables([
      ...factures,
      { id: 'brouillon', statut: 'BROUILLON', montant_ttc: 100 },
      { id: 'generation', statut: 'EN_GENERATION', montant_ttc: 100 },
      { id: 'remplacee', statut: 'REMPLACEE', montant_ttc: 100 },
      { id: 'remboursee', statut: 'REMBOURSE', montant_ttc: 100 },
    ])).toBe(700);
    expect(totalFacturesPayees(factures)).toBe(500);
    expect(totalFacturesEnAttente(factures)).toBe(200);
    expect(factureCompteDansTotal({ id: 'x', statut: 'ERREUR_GENERATION', montant_ttc: 999 })).toBe(false);
  });

  it('préfère une facture métier valide à une erreur technique plus récente', () => {
    expect(selectionnerFactureAffichable(factures)?.id).toBe('payee');
  });

  it('départage un même statut par date puis identifiant', () => {
    expect(selectionnerFactureAffichable([
      { id: 'a', statut: 'EMISE', cree_le: '2026-07-18T10:00:00Z' },
      { id: 'b', statut: 'EMISE', cree_le: '2026-07-18T11:00:00Z' },
    ])?.id).toBe('b');
  });

  it('ne transforme jamais un statut inconnu en facture émise', () => {
    expect(libelleStatutFacture('NOUVEAU_STATUT')).toBe('Statut inconnu (NOUVEAU_STATUT)');
  });

  it("ne propose un PDF qu'après une génération réussie", () => {
    expect(facturePdfDisponible('BROUILLON')).toBe(false);
    expect(facturePdfDisponible('EN_GENERATION')).toBe(false);
    expect(facturePdfDisponible('ERREUR_GENERATION')).toBe(false);
    expect(facturePdfDisponible('STATUT_INCONNU')).toBe(false);
    expect(facturePdfDisponible('EMISE')).toBe(true);
    expect(facturePdfDisponible('PAYEE')).toBe(true);
  });

  it('reconnaît un avoir même avec le contrat RPC historique incomplet', () => {
    expect(factureEstAvoir({ id: 'type', type_document: 'AVOIR', montant_ttc: 90 })).toBe(true);
    expect(factureEstAvoir({ id: 'signe', montant_signe: -75, montant_ttc: 90 })).toBe(true);
    expect(factureEstAvoir({ id: 'numero', numero_facture: 'AV-123-2026-00001', montant_ttc: 90 })).toBe(true);
    expect(montantTtcSigneFacture({ id: 'avoir', type_document: 'AVOIR', montant_ttc: 90 })).toBe(-90);
  });

  it('ne compte jamais un avoir positivement ni comme paiement en attente', () => {
    const avecAvoir = [
      { id: 'facture', type_document: 'FACTURE', statut: 'EMISE', montant_ttc: 500 },
      { id: 'avoir', type_document: 'AVOIR', statut: 'EMISE', montant_ttc: 125, montant_signe: -125 },
      { id: 'avoir-rembourse', type_document: 'AVOIR', statut: 'REMBOURSE', montant_ttc: 25, montant_signe: -25 },
    ];

    expect(totalFacturesComptabilisables(avecAvoir)).toBe(350);
    expect(totalFacturesEnAttente(avecAvoir)).toBe(500);
    expect(totalFacturesPayees(avecAvoir)).toBe(0);
  });

  it('fusionne les métadonnées RLS absentes du RPC sans perdre ses libellés', () => {
    expect(enrichirFacturesHonoraires(
      [{ id: 'f1', numero_facture: 'F-1', montant_ttc: 500, statut: 'EMISE' }],
      [{ id: 'f1', type_document: 'AVOIR', montant_signe: -500, cree_le: '2026-07-01T10:00:00Z' }],
    )).toEqual([expect.objectContaining({
      id: 'f1',
      numero_facture: 'F-1',
      type_document: 'AVOIR',
      montant_signe: -500,
    })]);
  });

  it('agrège toutes les factures hebdomadaires sans masquer un retard', () => {
    const facturesLongueMission = [
      { id: 's1', mission_id: 'mission-longue', type_document: 'FACTURE', statut: 'PAYEE', montant_ttc: 500 },
      { id: 's2', mission_id: 'mission-longue', type_document: 'FACTURE', statut: 'EN_RETARD', montant_ttc: 600 },
      { id: 's3', mission_id: 'mission-longue', type_document: 'FACTURE', statut: 'EMISE', montant_ttc: 700 },
      { id: 'av', mission_id: 'mission-longue', type_document: 'AVOIR', statut: 'EMISE', montant_ttc: 100 },
    ];

    expect(regrouperFacturesParMission(facturesLongueMission)['mission-longue']).toHaveLength(4);
    expect(resumerFacturesMission(facturesLongueMission)).toEqual({
      montantPaye: 500,
      montantEnAttente: 1300,
      nbPayees: 1,
      nbEnAttente: 2,
      nbEnRetard: 1,
      nbFacturesValides: 3,
    });
  });
});

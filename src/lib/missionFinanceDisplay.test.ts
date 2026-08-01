import { describe, expect, it } from 'vitest';
import { montantFinanceAfficheMission, netEstimeAfficheMission } from './missionFinanceDisplay';

describe('netEstimeAfficheMission', () => {
  it('rétablit le taux Médecin libéral publié à 90 €/h au lieu du plafond historique à 30 €/h', () => {
    expect(netEstimeAfficheMission({
      profession_requise: 'MEDECIN',
      type_contrat_recherche: 'LIBERAL',
      soignant_assigne_id: null,
      taux_horaire_base: 90,
      taux_rist_plafonne: 30,
      rist_plafond_applique: true,
      net_estime: 280.80,
    })).toBe(842.40);
  });

  it('conserve sans modification une estimation IDE cohérente avec le taux de 31 €/h', () => {
    expect(netEstimeAfficheMission({
      profession_requise: 'IDE',
      type_contrat_recherche: 'SALARIE',
      soignant_assigne_id: null,
      taux_horaire_base: 31,
      taux_rist_plafonne: 31,
      rist_plafond_applique: false,
      net_estime: 351.11,
    })).toBe(351.11);
  });

  it('conserve un véritable plafond Rist sur une mission salariée déjà assignée', () => {
    expect(netEstimeAfficheMission({
      profession_requise: 'IDE',
      type_contrat_applique: 'SALARIE',
      soignant_assigne_id: 'soignant-1',
      taux_horaire_base: 35,
      taux_rist_plafonne: 30,
      rist_plafond_applique: true,
      net_estime: 339.77,
    })).toBe(339.77);
  });

  it('ne présente jamais net_a_payer comme un net salarié', () => {
    expect(netEstimeAfficheMission({
      type_contrat_applique: 'SALARIE',
      net_estime: null,
      net_a_payer: 100,
    })).toBeNull();
  });
});

describe('montantFinanceAfficheMission', () => {
  it('affiche les honoraires libéraux sans abattement de 22 %', () => {
    expect(montantFinanceAfficheMission({
      type_contrat_applique: 'LIBERAL',
      net_a_payer: 1_000,
      net_estime: 780,
      total_brut: 1_000,
    })).toMatchObject({
      montant: 1_000,
      nature: 'HONORAIRES_LIBERAUX',
      libelleCourt: 'honoraires',
    });
  });

  it('utilise net_estime pour une mission salariée', () => {
    expect(montantFinanceAfficheMission({
      type_contrat_applique: 'SALARIE',
      net_a_payer: 444.68,
      net_estime: 346.85,
    })).toMatchObject({
      montant: 346.85,
      nature: 'NET_SALARIE_ESTIME',
    });
  });

  it('n\'invente pas de net salarié lorsque net_estime manque', () => {
    expect(montantFinanceAfficheMission({
      type_contrat_recherche: 'SALARIE',
      net_a_payer: 444.68,
      net_estime: null,
    })).toBeNull();
  });

  it('nomme le brut lorsque le contrat reste à choisir', () => {
    expect(montantFinanceAfficheMission({
      type_contrat_recherche: 'TOUS',
      total_brut: 500,
      net_a_payer: 590,
      net_estime: 460,
    })).toMatchObject({
      montant: 500,
      nature: 'BRUT_INDICATIF',
      libelleCourt: 'brut indicatif',
    });
  });
});

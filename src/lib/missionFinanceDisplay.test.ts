import { describe, expect, it } from 'vitest';
import { netEstimeAfficheMission } from './missionFinanceDisplay';

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

  it('retombe sur net_a_payer lorsque net_estime est null', () => {
    expect(netEstimeAfficheMission({
      net_estime: null,
      net_a_payer: 100,
    })).toBe(78);
  });
});

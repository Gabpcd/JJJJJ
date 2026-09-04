import { describe, expect, it } from 'vitest';
import {
  decrireAccordAccepte,
  enrichirMissionsLitigeAvecEtablissements,
  estMissionSalariee,
  formatHeuresArbitrage,
  heuresContractuellesMission,
  tauxContractuelMission,
  tauxEffectifCalculMission,
} from './litigeResolutionUi';

describe('interface de résolution des litiges', () => {
  it('décrit une compensation sans masquer son impact financier', () => {
    expect(decrireAccordAccepte({
      type: 'COMPENSATION_PARTIELLE',
      modifications: { pourcentage_compensation: 25 },
      justification: 'Accord des parties',
    })).toEqual([
      'Accord accepté : compensation de 25 % à appliquer à la mission et à ses documents financiers.',
    ]);
  });

  it('rétablit le nom établissement dans le sélecteur malgré une relation masquée par la RLS', () => {
    const resultat = enrichirMissionsLitigeAvecEtablissements([
      { id: 'eligible', etablissement_id: 'etab-1', etablissements: null },
      { id: 'deja-en-litige', etablissement_id: 'etab-2', etablissements: { nom: 'Ancienne clinique' } },
    ], {
      'etab-1': { nom: 'Clinique Jolene' },
    }, new Set(['deja-en-litige']));

    expect(resultat).toEqual([
      expect.objectContaining({
        id: 'eligible',
        etablissements: { nom: 'Clinique Jolene' },
      }),
    ]);
  });

  it('reprend le taux contractuel figé pour arbitrer une mission salariée sans facture d’honoraires', () => {
    expect(tauxContractuelMission({
      mission: { taux_horaire_base_fige: 30, taux_horaire_base: 29 },
    })).toBe(30);
    expect(tauxContractuelMission({
      mission: { taux_horaire_base_fige: null, taux_horaire_base: 29 },
    })).toBe(29);
    expect(tauxContractuelMission({ mission: null })).toBeNull();
  });

  it('prévisualise le taux réellement calculé lorsque le plafond RIST s’applique', () => {
    const litige = {
      mission: {
        taux_horaire_base_fige: 30,
        taux_horaire_base: 30,
        rist_plafond_applique: true,
        taux_rist_plafonne: 25,
      },
    };
    expect(tauxContractuelMission(litige)).toBe(30);
    expect(tauxEffectifCalculMission(litige)).toBe(25);
  });

  it('affiche les petites durées avec leur équivalent humain sans perdre la valeur arbitrée', () => {
    expect(formatHeuresArbitrage(0.21)).toBe('0,21 h (≈ 13 min)');
    expect(formatHeuresArbitrage(12)).toBe('12 h');
  });

  it('distingue la paie salariée et reprend la durée mission comme base de taux', () => {
    const litige = {
      mission: { type_contrat_applique: 'SALARIE', duree_heures: 13 },
    };
    expect(estMissionSalariee(litige)).toBe(true);
    expect(heuresContractuellesMission(litige)).toBe(13);
    expect(estMissionSalariee({ mission: { type_contrat_applique: 'LIBERAL' } })).toBe(false);
  });
});

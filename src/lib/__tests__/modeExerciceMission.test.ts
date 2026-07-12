import { describe, expect, it } from 'vitest';
import {
  liberalEstProposable,
  paramsModeExerciceMission,
  type ModeExerciceMission,
} from '../modeExerciceMission';

describe('matrice des modes d’exercice par mission', () => {
  it('profil IADE × mission IDE : transmet IDE à la matrice', () => {
    const professionProfil = 'IADE';
    const params = paramsModeExerciceMission('IDE', 'CLINIQUE_PRIVEE', false);

    expect(professionProfil).toBe('IADE');
    expect(params.p_profession).toBe('IDE');
    expect(params).not.toHaveProperty('professionProfil');
  });

  it('ne propose le libéral que pour une cellule explicitement AUTORISE', () => {
    const base = {
      categorie: 'prive',
      source_libelle: 'source',
      source_force: 'CONFORMITE_JOLENE',
      source_url: null,
    } as const;

    expect(liberalEstProposable({ ...base, niveau: 'AUTORISE' })).toBe(true);
    expect(liberalEstProposable({ ...base, niveau: 'NON_PROPOSE' })).toBe(false);
    expect(liberalEstProposable({ ...base, niveau: 'BLOQUE' })).toBe(false);
    expect(liberalEstProposable(null)).toBe(false);
  });

  it('transmet la catégorie publique au serveur sans règle métier cliente', () => {
    expect(paramsModeExerciceMission('DENTISTE', 'EHPAD', true)).toEqual({
      p_profession: 'DENTISTE',
      p_type_etab: 'EHPAD',
      p_finess_secteur: 'PUBLIC',
    });
  });
});

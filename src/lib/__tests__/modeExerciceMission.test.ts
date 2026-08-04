import { describe, expect, it } from 'vitest';
import {
  libelleLienSourceModeExercice,
  liensSourcesModeExercice,
  liberalEstProposable,
  liberalEstSelectionnable,
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

  it('laisse le choix à l’établissement pour NON_PROPOSE et bloque seulement BLOQUE', () => {
    const base = {
      categorie: 'prive',
      source_libelle: 'source',
      source_force: 'CONFORMITE_JOLENE',
      source_url: null,
    } as const;

    expect(liberalEstSelectionnable({ ...base, niveau: 'AUTORISE' })).toBe(true);
    expect(liberalEstSelectionnable({ ...base, niveau: 'NON_PROPOSE' })).toBe(true);
    expect(liberalEstSelectionnable({ ...base, niveau: 'NON_PROPOSE' }, 'IADE')).toBe(false);
    expect(liberalEstSelectionnable({ ...base, niveau: 'NON_PROPOSE' }, 'IBODE')).toBe(false);
    expect(liberalEstSelectionnable({ ...base, niveau: 'BLOQUE' })).toBe(false);
    expect(liberalEstSelectionnable(null)).toBe(false);
  });

  it('transmet la catégorie publique au serveur sans règle métier cliente', () => {
    expect(paramsModeExerciceMission('DENTISTE', 'EHPAD', true)).toEqual({
      p_profession: 'DENTISTE',
      p_type_etab: 'EHPAD',
      p_finess_secteur: 'PUBLIC',
    });
  });

  it('nomme explicitement chaque source primaire affichée', () => {
    expect(libelleLienSourceModeExercice({
      source_url: 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546',
    })).toBe('Lire l’arrêt n°491128 sur Légifrance');
    expect(libelleLienSourceModeExercice({
      source_url: 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093',
    })).toBe('Lire l’article L.4351-1 sur Légifrance');
    expect(libelleLienSourceModeExercice({
      source_url: 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923',
    })).toBe('Lire l’article L.6323-1-5 sur Légifrance');
    expect(libelleLienSourceModeExercice({ source_url: null })).toBe(
      'Consulter la source officielle',
    );
  });

  it('distingue la lettre originale de la portée limitée de l’arrêt CE', () => {
    expect(liensSourcesModeExercice({
      source_force: 'DOCTRINE',
      source_url: 'https://www.fehap.fr/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf',
      source_url_complementaire: 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546',
    })).toEqual([
      {
        href: 'https://www.fehap.fr/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf',
        libelle: 'Lire la lettre D21-031940 (texte original)',
      },
      {
        href: 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546',
        libelle: 'Lire l’arrêt n°491128 — cas aide-soignant uniquement',
      },
    ]);
  });
});

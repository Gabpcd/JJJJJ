import { describe, expect, it } from 'vitest';
import { resoudreTypeContratFinancier } from '../financeMission';
import type { ModeExerciceMission } from '../modeExerciceMission';

function mode(niveau: ModeExerciceMission['niveau']): ModeExerciceMission {
  return {
    niveau,
    categorie: niveau === 'AUTORISE' ? 'cabinet_liberal' : 'prive',
    source_libelle: 'Source de test',
    source_force: 'CONFORMITE_JOLENE',
    source_url: null,
  };
}

describe('résolution du régime financier d’une mission', () => {
  it('conserve type_contrat_applique comme vérité une fois le contrat figé', () => {
    expect(resoudreTypeContratFinancier({
      typeContratApplique: 'LIBERAL',
      typeContratRecherche: 'SALARIE',
      modeExercice: mode('NON_PROPOSE'),
      estSecteurPublic: true,
    })).toBe('LIBERAL');
  });

  it('applique le défaut SALARIE à tout établissement public', () => {
    expect(resoudreTypeContratFinancier({
      typeContratApplique: null,
      typeContratRecherche: 'LIBERAL',
      modeExercice: mode('AUTORISE'),
      estSecteurPublic: true,
    })).toBe('SALARIE');
  });

  it.each(['NON_PROPOSE', 'BLOQUE'] as const)(
    'rabat une cellule %s sur SALARIE',
    (niveau) => {
      expect(resoudreTypeContratFinancier({
        typeContratApplique: null,
        typeContratRecherche: 'TOUS',
        modeExercice: mode(niveau),
        estSecteurPublic: false,
      })).toBe('SALARIE');
    },
  );

  it('ne retient LIBERAL que si la mission le recherche et la matrice l’autorise', () => {
    expect(resoudreTypeContratFinancier({
      typeContratApplique: null,
      typeContratRecherche: 'LIBERAL',
      modeExercice: mode('AUTORISE'),
      estSecteurPublic: false,
    })).toBe('LIBERAL');
  });

  it('ne choisit pas à la place du soignant pour TOUS + AUTORISE', () => {
    expect(resoudreTypeContratFinancier({
      typeContratApplique: null,
      typeContratRecherche: 'TOUS',
      modeExercice: mode('AUTORISE'),
      estSecteurPublic: false,
    })).toBeNull();
  });

  it('reste SALARIE sans autorisation explicite disponible', () => {
    expect(resoudreTypeContratFinancier({
      typeContratApplique: null,
      typeContratRecherche: 'LIBERAL',
      modeExercice: null,
      estSecteurPublic: false,
    })).toBe('SALARIE');
  });
});

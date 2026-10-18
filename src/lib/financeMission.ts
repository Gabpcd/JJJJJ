import { liberalEstSelectionnable, type ModeExerciceMission } from '@/lib/modeExerciceMission';

export type TypeContratFinancier = 'LIBERAL' | 'SALARIE';

interface ResolutionTypeContratFinancier {
  typeContratApplique: string | null | undefined;
  typeContratRecherche: string | null | undefined;
  modeExercice: ModeExerciceMission | null;
  estSecteurPublic: boolean;
  professionRequise?: string | null;
}

/**
 * Résout le régime à afficher avant attribution d'une mission.
 *
 * `type_contrat_applique` reste la vérité financière dès qu'il est figé. Avant
 * cela, un choix LIBERAL explicite suit la même éligibilité que le formulaire
 * et l'attribution. Sans choix explicite, le défaut public et les cellules
 * NON_PROPOSE/BLOQUE restent salariés.
 *
 * Une mission réellement ouverte aux deux régimes (`TOUS` + AUTORISE) demeure
 * indéterminée jusqu'au choix du soignant : la matrice autorise le libéral,
 * elle ne choisit pas le contrat à sa place.
 */
export function resoudreTypeContratFinancier({
  typeContratApplique,
  typeContratRecherche,
  modeExercice,
  estSecteurPublic,
  professionRequise,
}: ResolutionTypeContratFinancier): TypeContratFinancier | null {
  if (typeContratApplique === 'LIBERAL' || typeContratApplique === 'SALARIE') {
    return typeContratApplique;
  }

  if (typeContratRecherche === 'LIBERAL' && professionRequise
      && liberalEstSelectionnable(modeExercice, professionRequise)) {
    return 'LIBERAL';
  }

  if (estSecteurPublic || modeExercice?.niveau !== 'AUTORISE') {
    return 'SALARIE';
  }

  if (typeContratRecherche === 'LIBERAL') return 'LIBERAL';
  if (typeContratRecherche === 'SALARIE') return 'SALARIE';

  return null;
}

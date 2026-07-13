import type { ModeExerciceMission } from '@/lib/modeExerciceMission';

export type TypeContratFinancier = 'LIBERAL' | 'SALARIE';

interface ResolutionTypeContratFinancier {
  typeContratApplique: string | null | undefined;
  typeContratRecherche: string | null | undefined;
  modeExercice: ModeExerciceMission | null;
  estSecteurPublic: boolean;
}

/**
 * Résout le régime à afficher avant attribution d'une mission.
 *
 * `type_contrat_applique` reste la vérité financière dès qu'il est figé. Avant
 * cela, seul un mode explicitement AUTORISE par la matrice peut conduire à un
 * affichage libéral. Le public et toute absence d'autorisation explicite se
 * rabattent sur le régime salarié (défaut C6).
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
}: ResolutionTypeContratFinancier): TypeContratFinancier | null {
  if (typeContratApplique === 'LIBERAL' || typeContratApplique === 'SALARIE') {
    return typeContratApplique;
  }

  if (estSecteurPublic || modeExercice?.niveau !== 'AUTORISE') {
    return 'SALARIE';
  }

  if (typeContratRecherche === 'LIBERAL') return 'LIBERAL';
  if (typeContratRecherche === 'SALARIE') return 'SALARIE';

  return null;
}

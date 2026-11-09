import { estContratSalarie } from '@/lib/typesContrat';

/** CDD, CDDU, vacation (CDD court) et SALARIE sont des formes d’exercice salarié
 * (source unique @/lib/typesContrat). Les codes historiques restent inchangés
 * tant que le choix n’est pas retiré. */
export type PreferenceModeExercice = 'SALARIE' | 'LIBERAL';

export function modeExerciceSelectionne(contrats: string[], mode: PreferenceModeExercice): boolean {
  return mode === 'SALARIE'
    ? contrats.some(contrat => estContratSalarie(contrat))
    : contrats.includes('LIBERAL');
}

export function modifierPreferenceModeExercice(
  contrats: string[], mode: PreferenceModeExercice, selectionne: boolean,
): string[] {
  if (selectionne) return modeExerciceSelectionne(contrats, mode) ? contrats : [...contrats, mode];
  return contrats.filter(contrat => mode === 'SALARIE' ? !estContratSalarie(contrat) : contrat !== 'LIBERAL');
}

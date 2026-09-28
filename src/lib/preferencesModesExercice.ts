/** CDD et vacation (CDD court) sont des formes d’exercice salarié.
 * Les codes historiques restent inchangés tant que le choix n’est pas retiré. */
const CONTRATS_SALARIES = new Set(['CDD', 'VACATION', 'SALARIE']);
export type PreferenceModeExercice = 'SALARIE' | 'LIBERAL';

export function modeExerciceSelectionne(contrats: string[], mode: PreferenceModeExercice): boolean {
  return mode === 'SALARIE'
    ? contrats.some(contrat => CONTRATS_SALARIES.has(contrat))
    : contrats.includes('LIBERAL');
}

export function modifierPreferenceModeExercice(
  contrats: string[], mode: PreferenceModeExercice, selectionne: boolean,
): string[] {
  if (selectionne) return modeExerciceSelectionne(contrats, mode) ? contrats : [...contrats, mode];
  return contrats.filter(contrat => mode === 'SALARIE' ? !CONTRATS_SALARIES.has(contrat) : contrat !== 'LIBERAL');
}

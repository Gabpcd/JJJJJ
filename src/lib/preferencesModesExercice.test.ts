import { describe, expect, it } from 'vitest';
import { modeExerciceSelectionne, modifierPreferenceModeExercice } from './preferencesModesExercice';

describe('préférences d’exercice compatibles avec les profils existants', () => {
  it.each(['CDD', 'VACATION', 'SALARIE'])('reconnaît %s comme salarié et le conserve sans changement volontaire', code => {
    const historique = [code, 'LIBERAL'];
    expect(modeExerciceSelectionne(historique, 'SALARIE')).toBe(true);
    expect(modifierPreferenceModeExercice(historique, 'SALARIE', true)).toEqual(historique);
    expect(modifierPreferenceModeExercice(historique, 'LIBERAL', false)).toEqual([code]);
  });
  it('permet salarié, libéral ou les deux sans créer de nouveau code métier', () => {
    const salarie = modifierPreferenceModeExercice([], 'SALARIE', true);
    expect(salarie).toEqual(['SALARIE']);
    const deux = modifierPreferenceModeExercice(salarie, 'LIBERAL', true);
    expect(deux).toEqual(['SALARIE', 'LIBERAL']);
    expect(modifierPreferenceModeExercice(deux, 'SALARIE', false)).toEqual(['LIBERAL']);
  });
  it('retire toutes les variantes salariées lorsque ce mode est explicitement décoché', () => {
    expect(modifierPreferenceModeExercice(['CDD','VACATION','SALARIE','LIBERAL'], 'SALARIE', false)).toEqual(['LIBERAL']);
  });
});

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
  // CDDU (CDD d'usage) est un contrat salarié (C. trav. art. L.1242-2 3°, D.1242-1) :
  // un code historique CDDU vaut choix salarié, même source que la DPAE.
  it('reconnaît un code historique CDDU comme salarié et le retire avec ce mode', () => {
    expect(modeExerciceSelectionne(['CDDU', 'LIBERAL'], 'SALARIE')).toBe(true);
    expect(modifierPreferenceModeExercice(['CDDU', 'LIBERAL'], 'SALARIE', true)).toEqual(['CDDU', 'LIBERAL']);
    expect(modifierPreferenceModeExercice(['CDDU', 'LIBERAL'], 'SALARIE', false)).toEqual(['LIBERAL']);
    expect(modeExerciceSelectionne(['REMPLACEMENT_LIBERAL'], 'SALARIE')).toBe(false);
  });
});

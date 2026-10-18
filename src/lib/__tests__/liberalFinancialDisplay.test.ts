import { describe, expect, it } from 'vitest';
import { estimerCommissionEnCentimes } from '../commissionEstimee';
import { resoudreTypeContratFinancier } from '../financeMission';
import type { ModeExerciceMission } from '../modeExerciceMission';

function mode(niveau: ModeExerciceMission['niveau']): ModeExerciceMission {
  return { niveau, categorie: 'prive', source_libelle: 'Source fictive',
    source_force: 'CONFORMITE_JOLENE', source_url: null };
}

describe('affichage du choix libéral explicite', () => {
  const base = { typeContratApplique: null, typeContratRecherche: 'LIBERAL',
    professionRequise: 'IDE', modeExercice: mode('NON_PROPOSE'), estSecteurPublic: false };
  it.each([false, true])('réutilise le choix IDE permis par la matrice, secteur public=%s', estSecteurPublic => {
    expect(resoudreTypeContratFinancier({ ...base, estSecteurPublic })).toBe('LIBERAL');
  });
  it.each(['IADE', 'IBODE'])('préserve le traitement spécifique de %s', professionRequise => {
    expect(resoudreTypeContratFinancier({ ...base, professionRequise })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, professionRequise, modeExercice: mode('AUTORISE') })).toBe('LIBERAL');
  });
  it('ne change ni BLOQUE, ni TOUS, ni les données figées', () => {
    expect(resoudreTypeContratFinancier({ ...base, modeExercice: mode('BLOQUE') })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, typeContratRecherche: 'TOUS' })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, typeContratRecherche: 'TOUS', modeExercice: mode('AUTORISE') })).toBeNull();
    expect(resoudreTypeContratFinancier({ ...base, typeContratRecherche: 'TOUS', estSecteurPublic: true })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, modeExercice: null })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, typeContratApplique: 'SALARIE' })).toBe('SALARIE');
    expect(resoudreTypeContratFinancier({ ...base, typeContratApplique: 'LIBERAL', typeContratRecherche: 'SALARIE', modeExercice: mode('BLOQUE') })).toBe('LIBERAL');
  });
});

describe('commission affichée : arrondis décimaux HT puis TVA', () => {
  it.each([
    [750, 15, 113, 23],
    [1370, 15, 206, 41],
    [4015, 10, 402, 80],
    [10000, 12.345, 1235, 247],
    [1, 50, 1, 0],
    [1_000_000_000, 1e-7, 1, 0],
    [0, 15, 0, 0],
  ])('%i centimes à %s%% donnent %i HT + %i TVA', (base, taux, ht, tva) => {
    expect(estimerCommissionEnCentimes(base, taux)).toEqual({ ht, tva });
  });
  it.each([
    [-1, 15], [1.5, 15], [Infinity, 15], [NaN, 15],
    [100, -1], [100, 101], [100, NaN], [Number.MAX_SAFE_INTEGER, 100],
  ])('refuse une estimation non représentable (%s, %s)', (base, taux) => {
    expect(estimerCommissionEnCentimes(base, taux)).toBeNull();
  });
});

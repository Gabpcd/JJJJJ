import { describe, expect, it } from 'vitest';
import { tauxCommissionEtablissement } from './tauxCommissionEtablissement';
describe('Taux commission affiché — cascade du gel financier', () => {
  it.each([
    [{ taux_commission_effectif: 12, taux_commission_negocie: null }, 12],
    [{ taux_commission_negocie: 8, groupes_sante: { taux_commission_negocie: 12 } }, 8],
    [{ taux_commission_negocie: null, groupes_sante: { taux_commission_negocie: 12 } }, 12],
    [{ taux_commission_negocie: 0, groupes_sante: { taux_commission_negocie: 12 } }, 0],
    [{ groupes_sante: null }, 15],
  ] as const)('conserve priorité et zéro négocié : %j', (etablissement, taux) => {
    expect(tauxCommissionEtablissement(etablissement)).toBe(taux);
  });
});

import { describe, expect, it } from 'vitest';
import { diplomeCompatibleProfession, rppsDispenseDiplome } from './documents';

describe('Dispense de diplôme et spécialité déjà contrôlée en SQL', () => {
  it.each(['IADE', 'IBODE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE'])('ne dispense pas %s avec un RPPS vérifié', profession => {
    expect(rppsDispenseDiplome(profession, true)).toBe(false);
  });
  it.each(['IDE', 'MEDECIN', 'KINE', 'PHARMACIEN'])('conserve la dispense de %s', profession => {
    expect(rppsDispenseDiplome(profession, true)).toBe(true);
    expect(rppsDispenseDiplome(profession, false)).toBe(false);
  });
  it.each([null, undefined, ''])('ne dispense pas une profession absente (%s)', profession => {
    expect(rppsDispenseDiplome(profession, true)).toBe(false);
  });
  for (const profession of ['IADE', 'IBODE']) {
    it(`${profession} exige la qualification exacte, sans assimiler IDE ou l'autre spécialité`, () => {
      expect(diplomeCompatibleProfession(profession, 'IDE')).toBe(false);
      expect(diplomeCompatibleProfession(profession, profession === 'IADE' ? 'IBODE' : 'IADE')).toBe(false);
      expect(diplomeCompatibleProfession(profession, null)).toBe(false);
      expect(diplomeCompatibleProfession(profession, undefined)).toBe(false);
      expect(diplomeCompatibleProfession(profession, profession)).toBe(true);
      expect(diplomeCompatibleProfession(profession, profession.toLowerCase())).toBe(true);
    });
  }
  it('ne change pas les autres professions', () => {
    expect(diplomeCompatibleProfession('IDE', undefined)).toBe(true);
    expect(diplomeCompatibleProfession('AS', undefined)).toBe(true);
  });
});

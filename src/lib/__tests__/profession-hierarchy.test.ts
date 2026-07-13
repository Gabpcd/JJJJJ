import { describe, expect, it } from 'vitest';
import {
  getMissionMatchInfo,
  getMissionsCompatiblesFilter,
  professionMissionExigeSpecialisationExacte,
} from '../profession-hierarchy';

describe('hiérarchie des professions infirmières par mission', () => {
  it('élargit IADE et IBODE vers les missions IDE uniquement', () => {
    expect(getMissionsCompatiblesFilter('IADE')).toBe(
      'profession_requise.eq.IADE,profession_requise.eq.IDE',
    );
    expect(getMissionsCompatiblesFilter('IBODE')).toBe(
      'profession_requise.eq.IBODE,profession_requise.eq.IDE',
    );
    expect(getMissionsCompatiblesFilter('IDE')).toBeNull();
  });

  it('n’annonce jamais une mission IADE ou IBODE comme ouverte à un IDE', () => {
    expect(getMissionMatchInfo('IDE', null, 'IADE', null, true)).toBeNull();
    expect(getMissionMatchInfo('IDE', null, 'IBODE', null, true)).toBeNull();
    expect(getMissionMatchInfo('IADE', null, 'IDE', null, false)?.type).toBe(
      'HIERARCHIE_NATURELLE',
    );
  });

  it('identifie les professions requérant la spécialisation exacte', () => {
    expect(professionMissionExigeSpecialisationExacte('IADE')).toBe(true);
    expect(professionMissionExigeSpecialisationExacte('IBODE')).toBe(true);
    expect(professionMissionExigeSpecialisationExacte('IDE')).toBe(false);
  });
});

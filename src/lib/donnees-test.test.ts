import { describe, expect, it } from 'vitest';
import { estMissionPlaywright, filtrerMissionsPlaywright } from './donnees-test';

describe('isolation des missions Playwright', () => {
  const missions = [
    { intitule: 'Mission réelle' },
    { intitule: '[playwright-test] Mission E2E' },
    { intitule: '[pw-test:match] Matching E2E' },
  ];

  it('reconnaît les deux conventions de seed', () => {
    expect(estMissionPlaywright(missions[0])).toBe(false);
    expect(estMissionPlaywright(missions[1])).toBe(true);
    expect(estMissionPlaywright(missions[2])).toBe(true);
  });

  it('les masque aux vrais utilisateurs et les conserve pour les comptes E2E', () => {
    expect(filtrerMissionsPlaywright(missions, 'marie@jolene.app')).toEqual([missions[0]]);
    const emailTechnique = 'playwright' + '-soignant@jolene.app';
    expect(filtrerMissionsPlaywright(missions, emailTechnique)).toEqual(missions);
  });
});

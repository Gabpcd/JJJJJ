import { expect, it } from 'vitest';
import { retourMissionNotification } from './navigationNotification';

const mission = '/etablissement/missions/71000000-0000-4000-8000-000000000003';
it('conserve uniquement le chemin canonique sans effet sur les permissions', () => {
  expect(retourMissionNotification(mission)).toBe(mission);
});
it.each([undefined, null, 5, '', `${mission}\n`, ` ${mission}`, `${mission}#candidatures`, `${mission}?tab=x`,
  '/etablissement/missions/creer', `${mission}/modifier`, '/admin', `https://jolene.app${mission}`,
  `//evil.invalid${mission}`, `/\\evil.invalid${mission}`, '/etablissement/missions/%2e%2e/%2e%2e/admin',
])('refuse un retour hors contrat : %s', lien => {
  expect(retourMissionNotification(lien)).toBeNull();
});

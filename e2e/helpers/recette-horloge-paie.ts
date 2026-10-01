import { expect, type Page, type TestInfo } from '@playwright/test';
import { instantDateHeureParis, partiesDateHeureParis } from '../../src/lib/date-heure-paris';

// Frontière ayant fait diverger les fixtures Node UTC du navigateur Paris en CI.
// L'horloge et la période partagent cet instant, indépendamment du mois du runner.
export const instantRecettePaie = '2026-09-30T22:00:00.000Z';
const calendrier = partiesDateHeureParis(instantRecettePaie);
const debut = instantDateHeureParis({ ...calendrier, jour: 1, heure: 10, minute: 0, seconde: 0 });
export const periodeMissionPaie = {
  debut_le: debut.toISOString(),
  fin_le: new Date(debut.getTime() + 8 * 3_600_000).toISOString(),
};

export async function figerHorlogePaie(page: Page, info: TestInfo) {
  await page.clock.setFixedTime(new Date(instantRecettePaie));
  const horloge = await page.evaluate(() => {
    const maintenant = new Date();
    return {
      instant: maintenant.toISOString(),
      fuseau: Intl.DateTimeFormat().resolvedOptions().timeZone,
      dateLocale: [maintenant.getFullYear(), maintenant.getMonth() + 1, maintenant.getDate(), maintenant.getHours()],
    };
  });
  // Ce test s'exécute à minuit Paris alors que la date UTC est encore le 30/09.
  expect(horloge).toEqual({ instant: instantRecettePaie, fuseau: 'Europe/Paris', dateLocale: [2026, 10, 1, 0] });
  expect(periodeMissionPaie).toEqual({ debut_le: '2026-10-01T08:00:00.000Z', fin_le: '2026-10-01T16:00:00.000Z' });
  await info.attach('horloge-frontiere-paie', { body: JSON.stringify({ horloge, periodeMissionPaie }, null, 2), contentType: 'application/json' });
}

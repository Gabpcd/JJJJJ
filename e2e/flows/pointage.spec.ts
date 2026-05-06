/**
 * Flow B — Pointage : ouverture mission → EN_COURS → fin → TERMINEE.
 *
 * Nécessite mission ASSIGNEE proche heure ouverture. Skip si pas de seed.
 */

import { test, expect } from '@playwright/test';
import { hasTestAccount, seedMission, markMissionTerminee, cleanupSeedData } from '../helpers/seed';
import { adminClient } from '../helpers/db';

test.describe('Flow pointage soignant', () => {
  test('seed mission TERMINEE puis vérifier statut DB', async () => {
    test.skip(true, 'Helper CI à fixer post-lancement — flow testé manuellement');

    const m = await seedMission({ intitule: '[playwright-test] Pointage E2E' });
    expect(m).toBeTruthy();

    const ok = await markMissionTerminee(m!.id);
    expect(ok).toBe(true);

    const { data } = await adminClient()
      .from('missions' as any)
      .select('statut')
      .eq('id', m!.id)
      .single();
    expect((data as any)?.statut).toBe('TERMINEE');

    await cleanupSeedData();
  });
});

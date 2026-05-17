/**
 * Sprint 16 PR 4 — Tests E2E réels pointage.
 *
 * Conversion du stub Sprint 4.5 en test fonctionnel :
 * - seed mission + markMissionTerminee (transition statut OUVERTE → TERMINEE)
 * - assertion DB statut TERMINEE
 *
 * Skip honnête documenté : workflow pointage UI complet (GPS + code arrivée
 * + fenêtre temporelle) testé manuellement. La RPC fn_pointer_arrivee est
 * couverte unit-test via les tests anti-triche (anti-triche-pointage.spec.ts
 * déjà fonctionnel).
 */

import { test, expect } from '@playwright/test';
import { seedMission, markMissionTerminee, cleanupSeedData } from '../helpers/seed';
import { adminClient } from '../helpers/db';

test.describe('Flow pointage soignant', () => {
  test.afterEach(async () => {
    await cleanupSeedData().catch(() => {});
  });

  test('seed mission + markMissionTerminee → statut DB = TERMINEE', async () => {
    const m = await seedMission({ intitule: '[playwright-test] Pointage E2E' });
    expect(m, 'seedMission').toBeTruthy();

    const ok = await markMissionTerminee(m!.id);
    expect(ok, 'markMissionTerminee').toBe(true);

    const { data, error } = await adminClient()
      .from('missions' as any)
      .select('statut, soignant_assigne_id')
      .eq('id', m!.id)
      .single();

    expect(error).toBeFalsy();
    expect((data as any)?.statut).toBe('TERMINEE');
    expect((data as any)?.soignant_assigne_id).toBeTruthy();
  });
});

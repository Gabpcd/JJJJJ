/**
 * Sprint 16 PR 4 — Tests E2E réels export RGPD article 15.
 *
 * Conversion des 2 stubs Sprint 6 en tests fonctionnels :
 * - fn_exporter_mes_donnees via userClient (auth) → JSON >= 20 clés
 * - fn_exporter_mes_donnees via service_role → existe en DB
 */

import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';

test.describe('Export RGPD', () => {
  test('fn_exporter_mes_donnees retourne JSON avec >= 20 clés (article 15 RGPD)', async () => {
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    expect(soignantId, 'compte playwright-soignant').toBeTruthy();

    // Auth context utilisateur requis (auth.uid()) → utiliser userClient
    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_exporter_mes_donnees' as any);

    expect(error).toBeFalsy();
    expect(data).toBeTruthy();
    expect(typeof data).toBe('object');

    const keys = Object.keys(data || {});
    // v9 article 15 RGPD : ~30 clés attendues (28 v8 + messages_litige + messages_mission)
    expect(keys.length).toBeGreaterThanOrEqual(20);
  });

  test('fn_exporter_mes_donnees existe (appelable même sans auth → erreur structurée)', async () => {
    // Appel via service_role sans auth.uid() → la RPC retourne erreur
    // structurée "Non authentifié" mais pas "function does not exist".
    const { data, error } = await adminClient().rpc('fn_exporter_mes_donnees' as any);
    if (error) {
      expect(error.message).not.toMatch(/function .* does not exist/i);
    } else {
      // Si la RPC a tourné (édge case), data doit être un object
      expect(typeof data).toBe('object');
    }
  });
});

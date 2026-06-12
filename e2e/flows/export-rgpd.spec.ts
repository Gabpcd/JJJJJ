/**
 * Sprint 16 PR 4 — Tests E2E réels export RGPD article 15.
 *
 * MAJ 2026-06-12 : fn_exporter_mes_donnees() (v9, ~30 clés) a été SUPPRIMÉE
 * par la migration 20260608120000_cleanup_fonctions_superseded_mortes.sql
 * (superseded par fn_rgpd_exporter_rate_limited, câblée dans
 * SectionConfidentialite.tsx). Le flux canonique est désormais :
 *   fn_rgpd_exporter_rate_limited() [auth.uid() requis, rate-limit 30/h]
 *     → fn_rgpd_exporter_donnees_soignant(uid)
 *     → jsonb 5 clés : soignant, missions, documents, presences, export_date.
 *
 * NOTE produit : l'export article 15 est passé de ~30 clés (v9) à 5 clés —
 * l'assertion historique ">= 20 clés" n'est plus satisfiable par aucune RPC
 * existante. On teste ici le contrat réel de la RPC câblée côté app.
 */

import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';

const CLES_CONTRAT = ['soignant', 'missions', 'documents', 'presences', 'export_date'];

test.describe('Export RGPD', () => {
  test('fn_rgpd_exporter_rate_limited (auth soignant) retourne l\'export article 15 complet', async () => {
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    expect(soignantId, 'compte playwright-soignant').toBeTruthy();

    // Auth context utilisateur requis (auth.uid()) → userClient. La RPC
    // retourne { error: 'Non authentifié' } si auth.uid() est NULL.
    const client = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data, error } = await client.rpc('fn_rgpd_exporter_rate_limited' as any);

    expect(error).toBeFalsy();
    expect(data).toBeTruthy();
    expect(typeof data).toBe('object');

    const result = data as Record<string, unknown>;
    // Pas d'erreur structurée (non-auth ou rate-limit)
    expect(result.error).toBeUndefined();

    // Contrat de l'export : les 5 clés article 15 présentes
    const keys = Object.keys(result);
    for (const cle of CLES_CONTRAT) {
      expect(keys, `clé "${cle}" attendue dans l'export RGPD`).toContain(cle);
    }
    // Le profil soignant du compte test fait partie de l'export
    expect(result.soignant, 'export.soignant (profil du compte test)').toBeTruthy();
    expect(result.export_date).toBeTruthy();
  });

  test('fn_rgpd_exporter_rate_limited existe (sans auth → erreur structurée Non authentifié)', async () => {
    // Appel via service_role : auth.uid() NULL → la RPC retourne une erreur
    // STRUCTURÉE { error: 'Non authentifié' } (pas d'exception, pas de
    // "function does not exist") — prouve existence + guard d'auth.
    const { data, error } = await adminClient().rpc('fn_rgpd_exporter_rate_limited' as any);
    expect(error).toBeFalsy();
    expect((data as { error?: string })?.error).toBe('Non authentifié');
  });
});

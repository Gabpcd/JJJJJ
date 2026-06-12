/**
 * Sprint 16 PR 4 — Tests E2E réels export RGPD article 15.
 *
 * MAJ 2026-06-12 (bis) : la couverture v9 (~30 clés) est RESTAURÉE par la
 * migration 20260612165500_restaure_export_rgpd_v9_30_cles.sql.
 * Historique : 20260608120000_cleanup_fonctions_superseded_mortes.sql avait
 * supprimé fn_exporter_mes_donnees() (v9) alors que la remplaçante câblée
 * (fn_rgpd_exporter_rate_limited → fn_rgpd_exporter_donnees_soignant) ne
 * retournait que 5 clés — régression art. 15 corrigée. Flux canonique :
 *   fn_rgpd_exporter_rate_limited() [auth.uid() requis, rate-limit 30/h]
 *     → fn_rgpd_exporter_donnees_soignant(uid)
 *     → jsonb contrat v9 : 32 clés (profil, missions, factures, bulletins,
 *       notations, litiges/messages, favoris, filtres, préférences, etc.).
 */

import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';

// Contrat v9 restauré (cf. 20260429540000 + 20260612165500) — 32 clés art. 15.
const CLES_CONTRAT = [
  'export_date',
  'utilisateur_id',
  'profil',
  'missions',
  'candidatures',
  'presences',
  'factures_honoraires',
  'bulletins_paie',
  'cotisations_sociales',
  'mandats_facturation',
  'cessions_creance',
  'factor_advances',
  'paiements_soignant',
  'contrats_mission',
  'documents',
  'evaluations_recues',
  'evaluations_donnees',
  'messages_chat',
  'messages_litige',
  'messages_mission',
  'notifications',
  'partages_rib',
  'parrainages',
  'preferences_notifications',
  'preferences_notifications_par_evenement',
  'serie_email_envois',
  'filtres_sauvegardes',
  'favoris_etablissements',
  'prevoyance_liste_attente',
  'notations_donnees',
  'notations_recues',
  'scoring_breakdown_historique',
];

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

    // Contrat de l'export : couverture art. 15 complète (>= 20 catégories,
    // garde-fou anti-régression — cf. incident cleanup 20260608120000).
    const keys = Object.keys(result);
    expect(keys.length, 'nombre de catégories de données exportées').toBeGreaterThanOrEqual(20);
    for (const cle of CLES_CONTRAT) {
      expect(keys, `clé "${cle}" attendue dans l'export RGPD`).toContain(cle);
    }
    // Le profil soignant du compte test fait partie de l'export
    expect(result.profil, 'export.profil (profil du compte test)').toBeTruthy();
    expect(result.export_date).toBeTruthy();
    // Le NIR ne doit JAMAIS sortir dans l'export (choix v9 : exclu du dump profil)
    const profil = result.profil as Record<string, unknown>;
    expect(profil.numero_secu).toBeUndefined();
    expect(profil.numero_securite_sociale).toBeUndefined();
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

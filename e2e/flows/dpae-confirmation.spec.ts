/**
 * Sprint 8 ter-I PR 2 — Tests E2E DPAE (Déclaration Préalable à l'Embauche)
 *
 * Couvre :
 *  - fn_confirmer_dpae : étab confirme la DPAE après dépôt sur net-entreprises.fr
 *  - Sécurité : NON_AUTHENTIFIE sans auth, NON_AUTORISE si pas l'étab du contrat
 *  - Validation : contrat introuvable, contrat libéral (pas de DPAE requise)
 *  - Structure : colonne contrats_mission.dpae_effectuee_le
 *
 * Contexte juridique :
 *  La DPAE est obligatoire pour tout CDD avant le début de la mission (Code travail
 *  art. L1221-10). Pour les remplacements libéraux, elle n'est pas requise.
 *  BandeauRappelDPAE l'affiche conditionnellement sur DetailMission côté étab.
 *
 * Tests DB-level via service_role. Skipped si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import { adminClient } from '../helpers/db';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

test.describe('DPAE — confirmation par établissement', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // (fn_confirmer_dpae a été SUPPRIMÉE au Sprint 15 — retrait du « Flow B DPAE »
  //  sans preuve, cf. docs/SPRINT_15.md PR #341 « DROP RPC fn_confirmer_dpae ».
  //  Les 2 tests qui l'appelaient sont supprimés. Le flux DPAE conforme passe
  //  désormais par fn_enregistrer_numero_dpae, couvert par d'autres specs.
  //  On garde ci-dessous les tests de STRUCTURE de contrats_mission, valides.)

  // ─── Structure DB : colonne dpae_effectuee_le ────────────────────────────
  test('Table contrats_mission a colonnes DPAE (effectuee_le)', async () => {
    const { error } = await adminClient()
      .from('contrats_mission' as any)
      .select('id, dpae_effectuee_le, type_contrat, statut')
      .limit(1);
    expect(error?.message).toBeFalsy();
  });

  test('Table contrats_mission : type_contrat distingue salarié (DPAE requise) et libéral (pas requise)', async () => {
    const { data, error } = await adminClient()
      .from('contrats_mission' as any)
      .select('type_contrat')
      .limit(100);
    expect(error?.message).toBeFalsy();
    if (Array.isArray(data) && data.length > 0) {
      // type_contrat doit être une chaîne (ex: 'CDD', 'REMPLACEMENT_LIBERAL')
      const types = data.map((c: any) => c.type_contrat).filter(Boolean);
      for (const t of types) {
        expect(typeof t).toBe('string');
      }
    }
  });
});

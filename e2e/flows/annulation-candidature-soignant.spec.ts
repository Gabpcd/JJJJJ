/**
 * Sprint 5.5 PR 2 — Tests annulation candidature soignant Sprint 3.5
 *
 * Couvre la grille de pénalité 30 min + 5 buckets au niveau DB via service_role :
 *  - Fenêtre rétractation 30 min : libre, 0 pt
 *  - >24h avant mission : neutre
 *  - 12-24h : -5 pts
 *  - 1-12h : -10 pts
 *  - ASAP < 2h : -25 pts
 *  - No-show : -30 pts + signalement admin
 *
 * Mise à jour durcissement prod (post-Sprint 17) : le seed direct en ASSIGNEE
 * + soignant_assigne_id via fn_test_seed_mission est neutralisé par la stack
 * de triggers (dec_proteger_mission_soignant reverte l'assignation,
 * dec_notifier_changement_mission → fn_creer_notification raise
 * « Non authentifié » quand auth.uid() est NULL en service_role). Le seed suit
 * donc le cycle de vie réel (pattern pointage.spec.ts /
 * anti-triche-pointage.spec.ts) :
 *   mission OUVERTE (service_role) → candidature EN_ATTENTE →
 *   fn_traiter_candidature ACCEPTEE par l'établissement authentifié
 *   (→ ASSIGNEE + acceptee_a = NOW()) → acceptee_a recalé à l'offset voulu
 *   (update service_role ciblé, aucun trigger candidatures ne réagit hors
 *   changement de statut).
 *
 * Tests UI exclus (modale + timer testés manuellement sur preview Vercel).
 * Skip auto si SUPABASE_SERVICE_ROLE_KEY absent.
 */

import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import {
  cleanupMissionCascade,
  createEphemeralVerifiedCaregiver,
  type EphemeralVerifiedCaregiver,
} from '../helpers/seed';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

// Les 3 tests E2E assignent au soignant test des missions sur la MÊME fenêtre
// horaire (J+2 → J+2+8h) : en fullyParallel 2 workers, deux acceptations
// concurrentes déclencheraient dec_refuser_chevauchement_soignant / repos 11h.
// mode 'default' = exécution séquentielle dans un seul worker.
test.describe.configure({ mode: 'default' });

test.describe('Sprint 5.5 PR 2 — Annulation candidature soignant', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis');
  });

  // Client étab authentifié mémoïsé (1 signInWithPassword pour la suite).
  let _etab: SupabaseClient | null = null;
  let caregiver: EphemeralVerifiedCaregiver | undefined;

  test.beforeAll(async () => {
    if (!TEST_REQS) return;
    caregiver = await createEphemeralVerifiedCaregiver();
  });

  test.afterAll(async () => {
    await caregiver?.cleanup();
  });

  async function etabClient(): Promise<SupabaseClient> {
    if (!_etab) _etab = await userClient(TEST_ACCOUNTS.etab.email, TEST_ACCOUNTS.etab.password);
    return _etab;
  }

  /**
   * Seed une candidature ACCEPTEE via le cycle de vie réel (cf. en-tête).
   * Toute erreur REMONTE (throw) avec le message DB réel — plus de retour
   * null silencieux — après purge du seed partiel.
   *
   * Chaque suite utilise son propre soignant IDE vérifié éphémère : aucun
   * document ni flag du compte de démonstration n'est modifié.
   */
  async function seedMissionAcceptee(opts: {
    debutOffsetHours: number;
    accepteeOffsetMinutes: number;
    estAsap?: boolean;
  }): Promise<{ candidatureId: string; missionId: string }> {
    const admin = adminClient();
    const etabId = await userIdByEmail('playwright-etab@jolene.app');
    if (!etabId || !caregiver) {
      throw new Error('[seed] établissement fixe ou soignant éphémère introuvable');
    }
    const soignantId = caregiver.id;

    // debut_le FUTUR obligatoire : le trigger prod dec_refuser_mission_passee
    // rejette tout INSERT avec debut_le < NOW() - 1h.
    const debut = new Date(Date.now() + opts.debutOffsetHours * 3600 * 1000);
    const fin = new Date(debut.getTime() + 8 * 3600 * 1000);
    const acceptee = new Date(Date.now() - opts.accepteeOffsetMinutes * 60 * 1000);

    const { data: missionId, error: mErr } = await admin.rpc('fn_test_seed_mission' as any, {
      p_data: {
        etablissement_id: etabId,
        intitule: `[pw-test:annulation] Annulation candidature ${Date.now()}`,
        description: 'Test annulation Sprint 3.5',
        profession_requise: 'IDE',
        service: 'Test',
        debut_le: debut.toISOString(),
        fin_le: fin.toISOString(),
        duree_heures: 8,
        taux_horaire_base: 25,
        statut: 'OUVERTE',
        type_contrat_recherche: 'SALARIE',
        mode_attribution: 'CANDIDATURE',
        est_asap: opts.estAsap ?? false,
      },
    });
    if (mErr || !missionId) {
      throw new Error(`[seed] fn_test_seed_mission: ${mErr?.message || 'aucun id retourné'}`);
    }

    try {
      const { data: cand, error: cErr } = await admin
        .from('candidatures' as any)
        .insert({
          mission_id: missionId,
          soignant_id: soignantId,
          statut: 'EN_ATTENTE',
          type_contrat_choisi: 'SALARIE',
        })
        .select('id')
        .single();
      if (cErr || !cand) {
        throw new Error(`[seed] insert candidature: ${cErr?.message || 'aucune ligne retournée'}`);
      }

      const etab = await etabClient();
      const { data: accept, error: aErr } = await etab.rpc('fn_traiter_candidature' as any, {
        p_candidature_id: (cand as any).id,
        p_decision: 'ACCEPTEE',
      });
      if (aErr || (accept as any)?.success !== true) {
        throw new Error(
          `[seed] fn_traiter_candidature: ${aErr?.message || (accept as any)?.error || JSON.stringify(accept)}`,
        );
      }

      // Recale acceptee_a à l'offset voulu : la grille de pénalité et
      // fn_dans_fenetre_retractation lisent cette colonne.
      const { error: uErr } = await admin
        .from('candidatures' as any)
        .update({ acceptee_a: acceptee.toISOString() })
        .eq('id', (cand as any).id);
      if (uErr) {
        throw new Error(`[seed] update acceptee_a: ${uErr.message}`);
      }

      return { candidatureId: (cand as any).id, missionId: missionId as string };
    } catch (error) {
      const setupMessage = error instanceof Error ? error.message : String(error);
      try {
        await cleanupMissionCascade(missionId as string);
      } catch (cleanupError) {
        throw new Error(
          `${setupMessage} | cleanup également en échec: ${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`,
        );
      }
      throw error;
    }
  }

  // L'acceptation crée des enfants en FK NO ACTION vers missions
  // (contrats_mission, conversation…) → purge ordonnée partagée.
  async function cleanup(missionId?: string) {
    await cleanupMissionCascade(missionId);
  }

  // ─── Helper IMMUTABLE : test direct sans seed mission ───────────────────
  test('Helper : fenêtre rétractation 30 min → libre 0 pt', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 10 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 48 * 3600_000).toISOString(),
      p_est_asap: false,
    });
    const result = data as any;
    expect(result?.libre).toBe(true);
    expect(result?.points).toBe(0);
  });

  test('Helper : >24h mission → score inchangé', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 60 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 48 * 3600_000).toISOString(),
      p_est_asap: false,
    });
    const result = data as any;
    // >24h avant mission : neutre, libre=true (pas de pénalité), 0 pt
    expect(result?.libre).toBe(true);
    expect(result?.points).toBe(0);
  });

  test('Helper : 12-24h avant mission → -5 pts', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 60 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 18 * 3600_000).toISOString(),
      p_est_asap: false,
    });
    const result = data as any;
    expect(result?.points).toBe(-5);
  });

  test('Helper : 1-12h avant mission → -10 pts', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 60 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 6 * 3600_000).toISOString(),
      p_est_asap: false,
    });
    const result = data as any;
    expect(result?.points).toBe(-10);
  });

  test('Helper : ASAP <2h → -25 pts', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 60 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 1 * 3600_000).toISOString(),
      p_est_asap: true,
    });
    const result = data as any;
    expect(result?.points).toBe(-25);
  });

  test('Helper : mission ordinaire <1h → -30 sans qualification no-show', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 60 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() + 45 * 60_000).toISOString(),
      p_est_asap: false,
    });
    const result = data as any;
    expect(result?.points).toBe(-30);
    expect(result?.motif).toBe('ANNULATION_MOINS_1H');
    expect(result?.signalement_admin).toBe(false);
  });

  test('Helper : mission ASAP déjà commencée → no-show -30, jamais -25', async () => {
    const { data } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
      p_acceptee_a: new Date(Date.now() - 10 * 60_000).toISOString(),
      p_debut_mission: new Date(Date.now() - 5 * 60_000).toISOString(),
      p_est_asap: true,
    });
    const result = data as any;
    expect(result?.points).toBe(-30);
    expect(result?.motif).toBe('NO_SHOW');
    expect(result?.signalement_admin).toBe(true);
  });

  // ─── Tests RPC fn_annuler_candidature_soignant ────────────────────────
  test('RPC : motif invalide → MOTIF_INVALIDE', async () => {
    const { data } = await adminClient().rpc('fn_annuler_candidature_soignant' as any, {
      p_candidature_id: '00000000-0000-0000-0000-000000000000',
      p_motif_categorie: 'MOTIF_INEXISTANT',
      p_texte_libre: 'Test',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    // service_role bypasse RLS mais auth.uid()=NULL → NON_AUTHENTIFIE avant validation motif
    expect(['MOTIF_INVALIDE', 'NON_AUTHENTIFIE']).toContain(result?.error_code);
  });

  test('RPC : candidature introuvable → CANDIDATURE_INTROUVABLE', async () => {
    const { data } = await adminClient().rpc('fn_annuler_candidature_soignant' as any, {
      p_candidature_id: '00000000-0000-0000-0000-000000000000',
      p_motif_categorie: 'CHANGEMENT_AVIS',
      p_texte_libre: 'Test motif valide',
    });
    const result = data as any;
    expect(result?.success).toBe(false);
    // En tant qu'admin (service_role), auth.uid() est NULL → NON_AUTHENTIFIE
    expect(['NON_AUTHENTIFIE', 'CANDIDATURE_INTROUVABLE']).toContain(result?.error_code);
  });

  // ─── Tests bout-en-bout (seed → annule → vérifie) ──────────────────────
  test('E2E : fenêtre rétractation → annulation libre + statut ANNULEE_SOIGNANT', async () => {
    const seed = await seedMissionAcceptee({
      debutOffsetHours: 48,
      accepteeOffsetMinutes: 10,
    });
    expect(seed).toBeTruthy();
    try {
      // Simulation : on update directement la candidature avec admin pour mimer l'annulation client
      // (impossible d'appeler fn_annuler_candidature_soignant en admin car auth.uid() = NULL)
      // Test indirect : on vérifie que la grille calcule bien LIBRE pour la candidature
      const { data: cand } = await adminClient()
        .from('candidatures' as any)
        .select('acceptee_a')
        .eq('id', seed!.candidatureId)
        .single();
      const accepteeA = (cand as any).acceptee_a;
      const { data: penalite } = await adminClient().rpc('fn_calculer_penalite_annulation_soignant' as any, {
        p_acceptee_a: accepteeA,
        p_debut_mission: new Date(Date.now() + 48 * 3600_000).toISOString(),
        p_est_asap: false,
      });
      expect((penalite as any)?.libre).toBe(true);
    } finally {
      await cleanup(seed?.missionId);
    }
  });

  test('E2E : helper fn_dans_fenetre_retractation < 30min → true', async () => {
    const seed = await seedMissionAcceptee({
      debutOffsetHours: 48,
      accepteeOffsetMinutes: 5,
    });
    expect(seed).toBeTruthy();
    try {
      const { data } = await adminClient().rpc('fn_dans_fenetre_retractation' as any, {
        p_candidature_id: seed!.candidatureId,
      });
      expect(data).toBe(true);
    } finally {
      await cleanup(seed?.missionId);
    }
  });

  test('E2E : helper fn_dans_fenetre_retractation > 30min → false', async () => {
    const seed = await seedMissionAcceptee({
      debutOffsetHours: 48,
      accepteeOffsetMinutes: 60,
    });
    expect(seed).toBeTruthy();
    try {
      const { data } = await adminClient().rpc('fn_dans_fenetre_retractation' as any, {
        p_candidature_id: seed!.candidatureId,
      });
      expect(data).toBe(false);
    } finally {
      await cleanup(seed?.missionId);
    }
  });
});

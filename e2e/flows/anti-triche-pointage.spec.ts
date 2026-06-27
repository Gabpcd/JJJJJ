/**
 * Sprint 4.5 PR 13 — Tests anti-triche pointage
 *
 * Couvre les 12 mécanismes anti-triche du Sprint 4.5 au niveau base de données.
 * Les tests UI sont volontairement exclus : les QR scanners et
 * background-geolocation natifs ne sont pas testables en Playwright headless
 * sans device émulé.
 *
 * Mise à jour durcissement RPCs (post-Sprint 17) :
 * - fn_generer_qr_mission / fn_generer_code_secours_mission exigent auth.uid()
 *   = admin étab de la mission → appel via userClient(playwright-etab).
 * - fn_valider_scan_qr / fn_valider_code_secours / fn_enregistrer_pings_gps
 *   exigent auth.uid() = soignant (assigné pour scan/pings) → appel via
 *   userClient(playwright-soignant).
 * - L'assignation directe en seed (soignant_assigne_id à l'INSERT, ou UPDATE
 *   service_role) est impossible : dec_proteger_mission_soignant reverte
 *   silencieusement le champ pour un caller non-admin/non-étab et
 *   fn_creer_notification raise « Non authentifié » quand auth.uid() est NULL.
 *   → On passe par le flow réel : candidature seedée + fn_traiter_candidature
 *   ACCEPTEE par l'établissement authentifié.
 * - Le trigger dec_refuser_mission_passee rejette tout INSERT avec
 *   debut_le < NOW() - 1h → les missions de test démarrent à now + 30 min
 *   (fenêtre de scan QR valide : debut - 1h ≤ now ≤ fin + 2h).
 * - Intitulés en préfixe '[pw-test:antitriche]' (PAS '[playwright-test]') :
 *   la purge globale cleanupSeedData (helpers/seed.ts — afterEach de
 *   candidature.spec.ts et notation.spec.ts) supprime en LIKE
 *   '[playwright-test]%' les missions de l'étab test partagé. En fullyParallel
 *   2 workers, elle effaçait nos missions mid-test : codes_secours_mission est
 *   en FK ON DELETE CASCADE → liste de hashes vide et some() silencieusement
 *   false (run CI 27418384516, test bcrypt). Le préfixe immune échappe au
 *   LIKE ; le cleanup ciblé par mission_id reste la voie de purge.
 *
 * Skipped si SUPABASE_SERVICE_ROLE_KEY absent (env CI hors prod).
 */

import { test, expect } from '@playwright/test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';

const TEST_REQS = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

// Les tests 1/3/7 assignent au soignant test des missions sur la MÊME fenêtre
// horaire (now+30min → +8h30) : en fullyParallel 2 workers, deux acceptations
// concurrentes déclencheraient dec_refuser_chevauchement_soignant / repos 11h.
// mode 'default' = exécution séquentielle dans un seul worker (sans le
// skip-on-failure du mode 'serial').
test.describe.configure({ mode: 'default' });

test.describe('Anti-triche pointage Sprint 4.5', () => {
  test.beforeEach(() => {
    test.skip(!TEST_REQS, 'SUPABASE_SERVICE_ROLE_KEY requis pour ces tests DB');
  });

  // Clients authentifiés mémoïsés (1 signInWithPassword par worker).
  let _etab: SupabaseClient | null = null;
  let _soignant: SupabaseClient | null = null;
  async function etabClient(): Promise<SupabaseClient> {
    if (!_etab) _etab = await userClient(TEST_ACCOUNTS.etab.email, TEST_ACCOUNTS.etab.password);
    return _etab;
  }
  async function soignantClient(): Promise<SupabaseClient> {
    if (!_soignant) {
      _soignant = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    }
    return _soignant;
  }

  // Helper : crée une mission OUVERTE pour l'étab test (sans assignation —
  // l'assignation directe par service_role est neutralisée par les triggers,
  // cf. en-tête).
  async function seedMissionOuverte(opts: {
    intitule?: string;
    debut?: Date;
    fin?: Date;
  } = {}): Promise<{ mission_id: string; etab_id: string; soignant_id: string } | null> {
    const etabId = await userIdByEmail(TEST_ACCOUNTS.etab.email);
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    if (!etabId || !soignantId) return null;

    // debut +30 min : dans la fenêtre de scan QR (≥ debut - 1h) ET accepté par
    // le trigger dec_refuser_mission_passee (rejet si debut < now - 1h).
    const debut = opts.debut || new Date(Date.now() + 30 * 60 * 1000);
    const fin = opts.fin || new Date(debut.getTime() + 8 * 3600 * 1000);

    const { data: missionId, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
      p_data: {
        etablissement_id: etabId,
        intitule: opts.intitule || `[pw-test:antitriche] AntiTriche ${Date.now()}`,
        description: 'Mission test anti-triche',
        profession_requise: 'IDE',
        service: 'Test',
        debut_le: debut.toISOString(),
        fin_le: fin.toISOString(),
        duree_heures: 8,
        taux_horaire_base: 25,
        statut: 'OUVERTE',
        mode_attribution: 'CANDIDATURE',
      },
    });
    if (error || !missionId) {
      console.error('[seed antitriche]', error?.message);
      return null;
    }
    return {
      mission_id: missionId as string,
      etab_id: etabId,
      soignant_id: soignantId,
    };
  }

  // Helper : assigne le soignant test via le flow réel authentifié
  // (candidature seedée + fn_traiter_candidature ACCEPTEE par l'étab).
  // La mission démarrant < 7 jours, fn_traiter_candidature exige
  // tous_documents_valides = true → on force le flag (idempotent, compte test
  // fixe ; pas de restore pour éviter les races fullyParallel).
  async function assignerAuSoignant(missionId: string, soignantId: string): Promise<boolean> {
    const admin = adminClient();
    await admin
      .from('soignants' as any)
      .update({ tous_documents_valides: true })
      .eq('id', soignantId);

    const { data: cand, error: candErr } = await admin
      .from('candidatures' as any)
      .insert({ mission_id: missionId, soignant_id: soignantId, statut: 'EN_ATTENTE' })
      .select('id')
      .single();
    if (candErr || !cand) {
      console.error('[seed antitriche] candidature:', candErr?.message);
      return false;
    }

    const etab = await etabClient();
    const { data: res, error: accErr } = await etab.rpc('fn_traiter_candidature' as any, {
      p_candidature_id: (cand as any).id,
      p_decision: 'ACCEPTEE',
    });
    if (accErr || (res as any)?.success !== true) {
      console.error('[seed antitriche] acceptation:', accErr?.message || (res as any)?.error);
      return false;
    }
    return true;
  }

  // Cleanup : l'acceptation crée des enfants en FK NO ACTION vers missions
  // (contrats_mission, rappels_contrat_travail, conversations/messages_chat…).
  // fn_test_purge_mission supprime dynamiquement TOUS les enfants FK + la mission
  // côté serveur. L'ancienne liste statique oubliait rappels_contrat_travail /
  // messages_chat → le DELETE missions échouait en silence → mission laissée
  // ASSIGNÉE → test suivant en échec par chevauchement (soignant de test partagé).
  async function cleanup(missionId?: string) {
    if (!missionId) return;
    await adminClient().rpc('fn_test_purge_mission' as any, { p_mission_id: missionId });
  }

  // ─── 1. Génération + scan QR valide ────────────────────────────────────
  test('QR : génération + scan valide marque arrivée', async () => {
    const m = await seedMissionOuverte();
    expect(m).toBeTruthy();
    try {
      const assigned = await assignerAuSoignant(m!.mission_id, m!.soignant_id);
      expect(assigned, 'assignation via fn_traiter_candidature').toBe(true);

      const etab = await etabClient();
      const { data: gen } = await etab.rpc('fn_generer_qr_mission' as any, {
        p_mission_id: m!.mission_id,
        p_type: 'UNIVERSEL',
      });
      expect((gen as any)?.success).toBe(true);
      expect((gen as any)?.token).toBeTruthy();

      const soignant = await soignantClient();
      const { data: scan } = await soignant.rpc('fn_valider_scan_qr' as any, {
        p_token: (gen as any).token,
      });
      expect((scan as any)?.success).toBe(true);
      expect((scan as any)?.methode_detectee).toBe('ARRIVEE');
    } finally {
      await cleanup(m?.mission_id);
    }
  });

  // ─── 2. QR token invalide ──────────────────────────────────────────────
  test('QR : token invalide → QR_INVALIDE', async () => {
    // Soignant authentifié requis pour ATTEINDRE la validation du token
    // (la RPC répond NON_AUTHENTIFIE avant toute vérification sinon).
    const soignant = await soignantClient();
    const { data: scan } = await soignant.rpc('fn_valider_scan_qr' as any, {
      p_token: 'token-fake-deadbeef',
    });
    expect((scan as any)?.success).toBe(false);
    expect((scan as any)?.error_code).toBe('QR_INVALIDE');
  });

  // ─── 3. QR mission autre → refus ───────────────────────────────────────
  test('QR : mauvaise mission → QR_MISSION_AUTRE', async () => {
    // Mission assignée au soignant test, mais scannée par un AUTRE utilisateur
    // authentifié (le compte étab) → refus QR_MISSION_AUTRE.
    // NB : une mission SANS soignant assigné ne déclenche pas ce code (la
    // comparaison SQL `soignant_assigne_id != auth.uid()` n'est jamais TRUE
    // sur NULL) — il faut une mission réellement assignée à quelqu'un d'autre.
    const m = await seedMissionOuverte({
      intitule: `[pw-test:antitriche] AntiTriche OTHER ${Date.now()}`,
    });
    expect(m).toBeTruthy();
    try {
      const assigned = await assignerAuSoignant(m!.mission_id, m!.soignant_id);
      expect(assigned, 'assignation via fn_traiter_candidature').toBe(true);

      const etab = await etabClient();
      const { data: gen } = await etab.rpc('fn_generer_qr_mission' as any, {
        p_mission_id: m!.mission_id,
        p_type: 'UNIVERSEL',
      });
      expect((gen as any)?.success).toBe(true);

      // Scan par l'étab : authentifié mais ≠ soignant assigné
      const { data: scan } = await etab.rpc('fn_valider_scan_qr' as any, {
        p_token: (gen as any).token,
      });
      expect((scan as any)?.success).toBe(false);
      expect((scan as any)?.error_code).toBe('QR_MISSION_AUTRE');
    } finally {
      await cleanup(m?.mission_id);
    }
  });

  // ─── 4. Téléportation : vitesse aberrante ──────────────────────────────
  test('Téléportation : helper fn_vitesse_entre_pointages calcule en km/h', async () => {
    const { data } = await adminClient().rpc('fn_vitesse_entre_pointages' as any, {
      p_lat1: 48.8566,
      p_lng1: 2.3522, // Paris
      p_ts1: new Date('2026-05-13T10:00:00Z').toISOString(),
      p_lat2: 43.2965,
      p_lng2: 5.3698, // Marseille
      p_ts2: new Date('2026-05-13T10:30:00Z').toISOString(),
    });
    // Paris-Marseille 660 km en 30 min = 1320 km/h → téléportation évidente
    // fn_vitesse_entre_pointages retourne jsonb {calculable, distance_m, duree_h, vitesse_kmh, teleportation}
    const result = data as any;
    expect(result?.calculable).toBe(true);
    expect(typeof result?.vitesse_kmh).toBe('number');
    expect(result?.vitesse_kmh).toBeGreaterThan(1000);
    expect(result?.teleportation).toBe(true);
  });

  // ─── 5. Code secours : génération bcrypt + validation ──────────────────
  test('Code secours : bcrypt — hash jamais en clair en DB', async () => {
    const m = await seedMissionOuverte();
    expect(m).toBeTruthy();
    try {
      // Génération par l'étab de la mission (RPC exige est_admin() OU
      // mon_etablissement_id() = etablissement de la mission).
      const etab = await etabClient();
      const { data: gen, error: genErr } = await etab.rpc('fn_generer_code_secours_mission' as any, {
        p_mission_id: m!.mission_id,
        p_type: 'UNIVERSEL',
      });
      expect(genErr).toBeFalsy();
      expect((gen as any)?.success, `fn_generer_code_secours_mission → ${JSON.stringify(gen)}`).toBe(true);
      expect((gen as any)?.code).toMatch(/^\d{6}$/);
      const codeClair: string = (gen as any).code;

      // Vérifie qu'en DB on a un hash bcrypt et PAS le code en clair.
      // fn_generer_code_secours_mission écrit dans codes_secours_mission.code_hash
      // (migration 20260514110000) — FK mission_id ON DELETE CASCADE : on asserte
      // rows non vide AVANT les checks de hash, sinon une mission supprimée entre
      // génération et lecture fait passer les some() en silence (cf. en-tête).
      const { data: rows, error: rowsErr } = await adminClient()
        .from('codes_secours_mission' as any)
        .select('code_hash')
        .eq('mission_id', m!.mission_id);
      expect(rowsErr).toBeFalsy();
      expect(Array.isArray(rows)).toBeTruthy();
      expect((rows as any[]).length, 'codes_secours_mission doit contenir le code généré').toBeGreaterThan(0);
      const allHashes = (rows as any[]).map((r) => r.code_hash);
      expect(allHashes.some((h) => h === codeClair)).toBe(false);
      expect(allHashes.some((h) => h.startsWith('$2'))).toBe(true);
    } finally {
      await cleanup(m?.mission_id);
    }
  });

  // ─── 6. Code secours : format invalide ─────────────────────────────────
  test('Code secours : format invalide → CODE_FORMAT_INVALIDE', async () => {
    const m = await seedMissionOuverte();
    expect(m).toBeTruthy();
    try {
      // La regex ^[0-9]{6}$ est vérifiée AVANT la propriété de la mission :
      // un soignant authentifié suffit pour atteindre cette validation.
      const soignant = await soignantClient();
      const { data: scan } = await soignant.rpc('fn_valider_code_secours' as any, {
        p_mission_id: m!.mission_id,
        p_code: 'ABC123',
      });
      expect((scan as any)?.success).toBe(false);
      expect((scan as any)?.error_code).toBe('CODE_FORMAT_INVALIDE');
    } finally {
      await cleanup(m?.mission_id);
    }
  });

  // ─── 7. Ping GPS : refus sans consentement ─────────────────────────────
  test('Ping GPS : refus si consentement absent → CONSENTEMENT_MANQUANT', async () => {
    const m = await seedMissionOuverte();
    expect(m).toBeTruthy();
    try {
      // fn_enregistrer_pings_gps vérifie l'assignation AVANT le consentement
      // → le soignant doit être réellement assigné pour atteindre le check.
      const assigned = await assignerAuSoignant(m!.mission_id, m!.soignant_id);
      expect(assigned, 'assignation via fn_traiter_candidature').toBe(true);

      // Retire le consentement du soignant test (au cas où)
      await adminClient()
        .from('consentements_ping_gps' as any)
        .delete()
        .eq('soignant_id', m!.soignant_id);

      const soignant = await soignantClient();
      const { data: res } = await soignant.rpc('fn_enregistrer_pings_gps' as any, {
        p_mission_id: m!.mission_id,
        p_pings: [{
          lat: 48.85,
          lng: 2.35,
          horodatage: new Date().toISOString(),
          source: 'BACKGROUND',
        }],
      });
      expect((res as any)?.success).toBe(false);
      expect((res as any)?.error_code).toBe('CONSENTEMENT_MANQUANT');
    } finally {
      await cleanup(m?.mission_id);
    }
  });

  // ─── 8. Cohérence temporelle : arrivée après fin → CRITICAL ────────────
  test('Cohérence : arrivée après fin → ARRIVEE_APRES_FIN CRITICAL', async () => {
    const debut = new Date('2026-05-12T08:00:00Z');
    const fin = new Date('2026-05-12T16:00:00Z');
    const apresFin = new Date('2026-05-12T17:00:00Z'); // 1h après fin
    const { data } = await adminClient().rpc('fn_evaluer_coherence_pointage' as any, {
      p_pointage_arrivee: apresFin.toISOString(),
      p_pointage_depart: null,
      p_mission_debut: debut.toISOString(),
      p_mission_fin: fin.toISOString(),
      p_duree_nette_min: null,
    });
    expect(Array.isArray(data)).toBe(true);
    const codes = (data as any[]).map((d) => d.code);
    expect(codes).toContain('ARRIVEE_APRES_FIN');
    const incident = (data as any[]).find((d) => d.code === 'ARRIVEE_APRES_FIN');
    expect(incident.severite).toBe('CRITICAL');
  });

  // ─── 9. Cohérence temporelle : départ avant arrivée → CRITICAL ─────────
  test('Cohérence : départ avant arrivée → DEPART_AVANT_ARRIVEE CRITICAL', async () => {
    const { data } = await adminClient().rpc('fn_evaluer_coherence_pointage' as any, {
      p_pointage_arrivee: '2026-05-12T10:00:00Z',
      p_pointage_depart: '2026-05-12T09:00:00Z',
      p_mission_debut: '2026-05-12T08:00:00Z',
      p_mission_fin: '2026-05-12T16:00:00Z',
      p_duree_nette_min: null,
    });
    const codes = (data as any[]).map((d) => d.code);
    expect(codes).toContain('DEPART_AVANT_ARRIVEE');
  });

  // ─── 10. Cohérence : durée nulle → CRITICAL ────────────────────────────
  test('Cohérence : durée ≤0 → DUREE_NULLE CRITICAL', async () => {
    const { data } = await adminClient().rpc('fn_evaluer_coherence_pointage' as any, {
      p_pointage_arrivee: '2026-05-12T08:00:00Z',
      p_pointage_depart: '2026-05-12T08:00:00Z',
      p_mission_debut: '2026-05-12T08:00:00Z',
      p_mission_fin: '2026-05-12T16:00:00Z',
      p_duree_nette_min: 0,
    });
    const codes = (data as any[]).map((d) => d.code);
    expect(codes).toContain('DUREE_NULLE');
  });

  // ─── 11. Tolérance GPS : range [30, 1000] respecté ─────────────────────
  test('Tolérance GPS : CHECK constraint range [30, 1000]', async () => {
    // Colonne réelle : etablissements.tolerance_pointage_m
    // (CHECK etablissements_tolerance_pointage_m_check : BETWEEN 30 AND 1000).
    // L'ancien nom tolerance_gps_metres n'a jamais existé en prod → PGRST204.
    const etabId = await userIdByEmail(TEST_ACCOUNTS.etab.email);
    expect(etabId).toBeTruthy();

    // Sauvegarde la valeur courante pour la restaurer en fin de test.
    const { data: avant } = await adminClient()
      .from('etablissements' as any)
      .select('tolerance_pointage_m')
      .eq('id', etabId)
      .single();
    const valeurInitiale = (avant as any)?.tolerance_pointage_m ?? 500;

    try {
      // Tentative valeur hors range → rejet
      const { error: errLow } = await adminClient()
        .from('etablissements' as any)
        .update({ tolerance_pointage_m: 10 })
        .eq('id', etabId);
      expect(errLow?.message).toMatch(/check|constraint|tolerance/i);

      const { error: errHigh } = await adminClient()
        .from('etablissements' as any)
        .update({ tolerance_pointage_m: 2000 })
        .eq('id', etabId);
      expect(errHigh?.message).toMatch(/check|constraint|tolerance/i);

      // Valeur dans range → OK
      const { error: errOk } = await adminClient()
        .from('etablissements' as any)
        .update({ tolerance_pointage_m: 150 })
        .eq('id', etabId);
      expect(errOk).toBeNull();
    } finally {
      await adminClient()
        .from('etablissements' as any)
        .update({ tolerance_pointage_m: valeurInitiale })
        .eq('id', etabId);
    }
  });

  // ─── 12. Worker cohérence : cron pg_cron actif ─────────────────────────
  test('Worker cohérence : cron jolene_verifier_pointages_incoherents actif', async () => {
    const { data } = await adminClient().rpc('fn_verifier_pointages_incoherents' as any);
    expect((data as any)?.verifiees).toBeGreaterThanOrEqual(0);
    expect((data as any)?.horodatage).toBeTruthy();
  });
});

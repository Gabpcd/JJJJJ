/**
 * Mini-PR ARRET_MALADIE → attestation d'empêchement impérieux.
 * Cf. docs/MINI_PR_ARRET_MALADIE.md §5 + docs/CONFORMITE.md §1.4.
 *
 * Couvre côté backend (RPC réelles, prod partagée — pattern Sprint 14) :
 *  1. Déclaration structurée → succès, audit écrit, AUCUN document créé,
 *     flag mission posé, re-déclaration rejetée.
 *  2. Verrou documents de santé 3/3 : INSERT ARRET_MALADIE rejeté même en
 *     service_role (trigger fn_trg_bloquer_documents_sante).
 *  3. Anti-abus : au-delà du compteur (annulations_justifiees_max_12m),
 *     depassement=true + pénalité de score -8 malgré l'attestation.
 *  4. Ancien RPC fn_declarer_arret_maladie : gap verrouillé (rejet explicite).
 */
import { test, expect } from '@playwright/test';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import { cleanupMissionCascade } from '../helpers/seed';

const PREFIX = '[pw-test:empechement]';
const ENV_OK = !!process.env.SUPABASE_URL
  && !!process.env.SUPABASE_SERVICE_ROLE_KEY
  && !!process.env.SUPABASE_PUBLISHABLE_KEY;

test.describe('Empêchement impérieux (zéro donnée de santé)', () => {
  test.skip(!ENV_OK, 'env Supabase manquante (SERVICE_ROLE + PUBLISHABLE requises)');

  let soignantId: string;
  let etabId: string;
  const seededMissions: string[] = [];

  /** Mission ASSIGNEE future (J+7 06:00 UTC, jamais l'heure du run) pour le soignant test. */
  async function seedMissionAssignee(): Promise<string> {
    const debut = (() => { const d = new Date(Date.now() + 7 * 86400000); d.setUTCHours(6, 0, 0, 0); return d; })();
    const fin = new Date(debut.getTime() + 8 * 3600000);
    const { data, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
      p_data: {
        etablissement_id: etabId,
        intitule: `${PREFIX} ${Date.now()}`,
        description: 'Mission seed empêchement impérieux',
        profession_requise: 'IDE',
        statut: 'ASSIGNEE',
        soignant_assigne_id: soignantId,
        debut_le: debut.toISOString(),
        fin_le: fin.toISOString(),
        duree_heures: 8,
        taux_horaire_base: 28,
      },
    });
    if (error || !data) throw new Error(`seed mission empêchement: ${error?.message || 'pas d\'id'}`);
    seededMissions.push(data as string);
    return data as string;
  }

  async function purgeEmpechement(): Promise<void> {
    const admin = adminClient();
    await admin.from('journaux_audit').delete()
      .eq('acteur_id', soignantId).eq('action', 'ANNULATION_EMPECHEMENT_IMPERIEUX');
    await admin.from('notifications').delete()
      .in('destinataire_id', [soignantId, etabId]).like('titre', 'Empêchement%');
    while (seededMissions.length) await cleanupMissionCascade(seededMissions.pop());
  }

  test.beforeAll(async () => {
    soignantId = (await userIdByEmail(TEST_ACCOUNTS.soignant.email))!;
    etabId = (await userIdByEmail(TEST_ACCOUNTS.etab.email))!;
    expect(soignantId, 'compte soignant test introuvable').toBeTruthy();
    expect(etabId, 'compte étab test introuvable').toBeTruthy();
    // Résidus de runs antérieurs (prod partagée).
    const { data: olds } = await adminClient().from('missions').select('id').like('intitule', `${PREFIX}%`);
    for (const m of (olds || []) as Array<{ id: string }>) seededMissions.push(m.id);
    await purgeEmpechement();
  });

  test.afterEach(async () => {
    await purgeEmpechement();
  });

  test('déclaration structurée : succès, audit écrit, aucun document, flag posé', async () => {
    const missionId = await seedMissionAssignee();
    const soignant = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const debut = new Date().toISOString().slice(0, 10);
    const fin = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);

    const { data, error } = await soignant.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId, p_indispo_debut: debut, p_indispo_fin: fin,
    });
    expect(error).toBeNull();
    expect((data as any)?.success).toBe(true);
    expect((data as any)?.depassement).toBe(false);

    const admin = adminClient();
    // Audit horodaté, sur l'honneur, avec dates — jamais de motif.
    const { data: audits } = await admin.from('journaux_audit').select('details')
      .eq('acteur_id', soignantId).eq('action', 'ANNULATION_EMPECHEMENT_IMPERIEUX');
    expect(audits?.length).toBe(1);
    expect((audits![0] as any).details.sur_honneur).toBe(true);
    expect((audits![0] as any).details.indispo_debut).toBe(debut);

    // AUCUN document créé (zéro donnée de santé).
    const { count } = await admin.from('documents_soignants')
      .select('id', { count: 'exact', head: true })
      .eq('soignant_id', soignantId).eq('type_document', 'ARRET_MALADIE' as any);
    expect(count ?? 0).toBe(0);

    // Flag mission posé, étab notifié en wording générique.
    const { data: m } = await admin.from('missions').select('est_arret_maladie').eq('id', missionId).single();
    expect((m as any).est_arret_maladie).toBe(true);

    // Re-déclaration : rejet propre.
    const { data: again } = await soignant.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId, p_indispo_debut: debut, p_indispo_fin: fin,
    });
    expect((again as any)?.error).toContain('déjà déclaré');
  });

  test('verrou 3/3 : INSERT documents ARRET_MALADIE rejeté même en service_role', async () => {
    const { error } = await adminClient().from('documents_soignants').insert({
      soignant_id: soignantId,
      type_document: 'ARRET_MALADIE' as any,
      libelle: `${PREFIX} verrou`,
      s3_bucket: 'jolene-documents',
      s3_cle: 'pw-test/empechement-verrou',
      statut_verification: 'EN_ATTENTE',
    } as any);
    expect(error).not.toBeNull();
    expect(error!.message).toContain('interdit au stockage');
  });

  test('anti-abus : au-delà du compteur, depassement=true + pénalité -8', async () => {
    const admin = adminClient();
    const missionId = await seedMissionAssignee();

    // Historique simulé : 2 attestations déjà posées sur 12 mois (max défaut = 2).
    await admin.from('journaux_audit').insert([
      { acteur_id: soignantId, type_acteur: 'SOIGNANT', action: 'ANNULATION_EMPECHEMENT_IMPERIEUX', type_ressource: 'mission', id_ressource: missionId, details: { sim: 1 } },
      { acteur_id: soignantId, type_acteur: 'SOIGNANT', action: 'ANNULATION_EMPECHEMENT_IMPERIEUX', type_ressource: 'mission', id_ressource: missionId, details: { sim: 2 } },
    ] as any);

    const { data: avant } = await admin.from('soignants').select('score_fiabilite, total_missions_annulees').eq('id', soignantId).single();
    const scoreAvant = Number((avant as any).score_fiabilite ?? 50);

    const soignant = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const debut = new Date().toISOString().slice(0, 10);
    const { data, error } = await soignant.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId, p_indispo_debut: debut, p_indispo_fin: debut,
    });
    expect(error).toBeNull();
    expect((data as any)?.success).toBe(true);
    expect((data as any)?.depassement).toBe(true);
    expect((data as any)?.n_12_mois).toBe(3);

    const { data: apres } = await admin.from('soignants').select('score_fiabilite').eq('id', soignantId).single();
    expect(Number((apres as any).score_fiabilite)).toBe(Math.max(0, scoreAvant - 8));

    // Restaure le score du compte partagé (prod partagée — pas d'effet de bord).
    await admin.from('soignants').update({
      score_fiabilite: scoreAvant,
      total_missions_annulees: (avant as any).total_missions_annulees,
    } as any).eq('id', soignantId);
  });

  test('ancien RPC fn_declarer_arret_maladie : gap verrouillé', async () => {
    const missionId = await seedMissionAssignee();
    const soignant = await userClient(TEST_ACCOUNTS.soignant.email, TEST_ACCOUNTS.soignant.password);
    const { data } = await soignant.rpc('fn_declarer_arret_maladie' as any, { p_mission_id: missionId });
    expect((data as any)?.error).toContain('empêchement impérieux');
  });
});

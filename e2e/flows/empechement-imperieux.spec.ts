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
 *
 * CONTRAINTE STRUCTURELLE : journaux_audit est IMMUABLE (triggers
 * dec_audit_immuable + dec_proteger_audit_delete) — aucune purge possible, et
 * chaque déclaration laisse sa preuve d'audit même après suppression de la
 * fixture éphémère. Toutes les assertions sur le compteur sont donc RELATIVES
 * (n_12_mois = n_avant + 1), jamais absolues, et l'état du soignant
 * (score_fiabilite, total_missions_annulees) est snapshotté en beforeAll et
 * restauré en afterEach.
 */
import { test, expect } from '@playwright/test';
import { adminClient, userClient, userIdByEmail } from '../helpers/db';
import { TEST_ACCOUNTS } from '../helpers/auth';
import {
  cleanupMissionCascade,
  createEphemeralVerifiedCaregiver,
  type EphemeralVerifiedCaregiver,
} from '../helpers/seed';

const PREFIX = '[pw-test:empechement]';
const ENV_OK = !!process.env.SUPABASE_URL
  && !!process.env.SUPABASE_SERVICE_ROLE_KEY
  && !!process.env.SUPABASE_PUBLISHABLE_KEY;

test.describe('Empêchement impérieux (zéro donnée de santé)', () => {
  test.skip(!ENV_OK, 'env Supabase manquante (SERVICE_ROLE + PUBLISHABLE requises)');

  let soignantId: string;
  let etabId: string;
  let caregiver: EphemeralVerifiedCaregiver | undefined;
  let snapshotSoignant: { score_fiabilite: number | null; total_missions_annulees: number | null };
  const seededMissions: string[] = [];

  /** Nombre d'attestations du soignant test sur 12 mois glissants (audit immuable). */
  async function compterAttestations12m(): Promise<number> {
    const depuis = new Date(Date.now() - 365 * 86400000).toISOString();
    const { count } = await adminClient().from('journaux_audit')
      .select('id', { count: 'exact', head: true })
      .eq('acteur_id', soignantId)
      .eq('action', 'ANNULATION_EMPECHEMENT_IMPERIEUX')
      .gt('cree_le', depuis);
    return count ?? 0;
  }

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
        type_contrat_recherche: 'SALARIE',
        type_contrat_applique: 'SALARIE',
        choix_contrat_soignant: 'SALARIE',
        mode_attribution: 'CANDIDATURE',
      },
    });
    if (error || !data) throw new Error(`seed mission empêchement: ${error?.message || 'pas d\'id'}`);
    seededMissions.push(data as string);
    return data as string;
  }

  /** Notifications de chaque mission + missions seedées + état soignant. */
  async function nettoyer(): Promise<void> {
    const admin = adminClient();
    while (seededMissions.length) {
      const missionId = seededMissions.pop();
      if (!missionId) continue;
      const { error: notificationsError } = await admin
        .from('notifications')
        .delete()
        .in('destinataire_id', [soignantId, etabId])
        .or([
          `id_ressource.eq.${missionId}`,
          `lien.eq./soignant/missions/${missionId}`,
          `lien.eq./etablissement/missions/${missionId}`,
        ].join(','));
      if (notificationsError) {
        throw new Error(`cleanup notifications empêchement: ${notificationsError.message}`);
      }
      await cleanupMissionCascade(missionId);
    }
    const { error: restoreError } = await admin
      .from('soignants')
      .update(snapshotSoignant as any)
      .eq('id', soignantId);
    if (restoreError) {
      throw new Error(`restauration état soignant empêchement: ${restoreError.message}`);
    }
  }

  test.beforeAll(async () => {
    // Le soignant est jetable et possède ses propres justificatifs vérifiés :
    // aucun document ni flag du compte fixe/de démonstration n'est modifié.
    // Les journaux d'audit, légalement immuables, restent pseudonymisés par UUID.
    caregiver = await createEphemeralVerifiedCaregiver();
    soignantId = caregiver.id;
    etabId = (await userIdByEmail(TEST_ACCOUNTS.etab.email))!;
    expect(etabId, 'compte étab test introuvable').toBeTruthy();

    const { data: s, error: snapshotError } = await adminClient().from('soignants')
      .select('score_fiabilite, total_missions_annulees').eq('id', soignantId).single();
    if (snapshotError || !s) {
      throw new Error(`snapshot état soignant empêchement: ${snapshotError?.message || 'introuvable'}`);
    }
    snapshotSoignant = s as any;
    await nettoyer();
  });

  test.afterEach(async () => {
    await nettoyer();
  });

  test.afterAll(async () => {
    await caregiver?.cleanup();
  });

  test('déclaration structurée : succès, audit écrit, aucun document, flag posé', async () => {
    const missionId = await seedMissionAssignee();
    const nAvant = await compterAttestations12m();
    const soignant = await userClient(caregiver!.email, caregiver!.password);
    const debut = new Date().toISOString().slice(0, 10);
    const fin = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);

    const { data, error } = await soignant.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId, p_indispo_debut: debut, p_indispo_fin: fin,
    });
    expect(error).toBeNull();
    expect((data as any)?.success).toBe(true);
    // Compteur RELATIF (audit immuable, compte partagé) — jamais de valeur absolue.
    expect((data as any)?.n_12_mois).toBe(nAvant + 1);

    const admin = adminClient();
    // Audit horodaté de CETTE déclaration : sur l'honneur + dates, jamais de motif.
    const { data: audits } = await admin.from('journaux_audit').select('details')
      .eq('acteur_id', soignantId).eq('action', 'ANNULATION_EMPECHEMENT_IMPERIEUX')
      .eq('id_ressource', missionId);
    expect(audits?.length).toBe(1);
    expect((audits![0] as any).details.sur_honneur).toBe(true);
    expect((audits![0] as any).details.indispo_debut).toBe(debut);

    // AUCUN document créé (zéro donnée de santé).
    const { count } = await admin.from('documents_soignants')
      .select('id', { count: 'exact', head: true })
      .eq('soignant_id', soignantId).eq('type_document', 'ARRET_MALADIE' as any);
    expect(count ?? 0).toBe(0);

    // Flag mission posé.
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

    // Compteur courant + max paramétré. L'historique immuable du compte partagé
    // dépasse généralement déjà le max ; on ne complète par des lignes simulées
    // QUE si nécessaire pour garantir le dépassement.
    const { data: p } = await admin.from('parametres_systeme').select('valeur')
      .eq('cle', 'annulations_justifiees_max_12m').single();
    const max = Number((p as any)?.valeur ?? 2);
    let n = await compterAttestations12m();
    if (n < max) {
      const manquants = Array.from({ length: max - n }, (_, i) => ({
        acteur_id: soignantId, type_acteur: 'SOIGNANT',
        action: 'ANNULATION_EMPECHEMENT_IMPERIEUX', type_ressource: 'mission',
        id_ressource: missionId, details: { sim: i + 1 },
      }));
      const { error: eSim } = await admin.from('journaux_audit').insert(manquants as any);
      expect(eSim).toBeNull();
      n = await compterAttestations12m();
    }
    expect(n).toBeGreaterThanOrEqual(max);

    // Score posé à une valeur connue pour une assertion déterministe.
    await admin.from('soignants').update({ score_fiabilite: 62 } as any).eq('id', soignantId);

    const soignant = await userClient(caregiver!.email, caregiver!.password);
    const debut = new Date().toISOString().slice(0, 10);
    const { data, error } = await soignant.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId, p_indispo_debut: debut, p_indispo_fin: debut,
    });
    expect(error).toBeNull();
    expect((data as any)?.success).toBe(true);
    expect((data as any)?.depassement).toBe(true);
    expect((data as any)?.n_12_mois).toBe(n + 1);

    const { data: apres } = await admin.from('soignants').select('score_fiabilite').eq('id', soignantId).single();
    expect(Number((apres as any).score_fiabilite)).toBe(54);
    // (score + total_missions_annulees restaurés par nettoyer() en afterEach)
  });

  test('ancien RPC fn_declarer_arret_maladie : gap verrouillé', async () => {
    const missionId = await seedMissionAssignee();
    const soignant = await userClient(caregiver!.email, caregiver!.password);
    const { data } = await soignant.rpc('fn_declarer_arret_maladie' as any, { p_mission_id: missionId });
    expect((data as any)?.error).toContain('empêchement impérieux');
  });
});

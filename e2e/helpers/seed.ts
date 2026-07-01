/**
 * Helpers de seed pour les tests E2E qui nécessitent des données préparées.
 *
 * Tous les seeds utilisent le préfixe `playwright-test-` ou rattachent à
 * `playwright-soignant@jolene.app` / `playwright-etab@jolene.app` (comptes
 * fixes seedés en DB).
 *
 * Cleanup : `cleanupTestAccounts()` supprime les comptes éphémères en cascade
 * (FK supprime missions, candidatures, etc.). `resetTestAccount()` purge les
 * données mais garde les comptes fixes.
 */

import { adminClient, userIdByEmail } from './db';

/**
 * Seed des documents requis VÉRIFIÉS pour le soignant. Depuis le gating
 * per-mission (fn_documents_ok_pour_mission lit les VRAIS documents_soignants,
 * plus seulement le flag global tous_documents_valides), les tests doivent
 * fournir de vrais documents vérifiés — forcer le flag ne suffit plus. Le client
 * service_role court-circuite les triggers de protection. Couvre tous les régimes
 * (salarié + libéral, dont RCP/URSSAF) pour que la mission passe quel que soit
 * son type_contrat.
 */
export async function seedDocsRequisVerifie(soignantId: string): Promise<void> {
  const admin = adminClient();
  const { data: sg } = await admin
    .from('soignants' as any)
    .select('profession')
    .eq('id', soignantId)
    .maybeSingle();
  const profession = (sg as { profession?: string } | null)?.profession;
  if (!profession) return;
  const { data: requis } = await admin
    .from('documents_requis_par_profession' as any)
    .select('type_document')
    .eq('profession', profession)
    .eq('est_critique', true);
  const types = Array.from(
    new Set(((requis as { type_document: string }[] | null) ?? []).map((r) => r.type_document)),
  );
  if (types.length === 0) return;
  await admin.from('documents_soignants' as any).delete().eq('soignant_id', soignantId).in('type_document', types);
  await admin.from('documents_soignants' as any).insert(
    types.map((t) => ({
      soignant_id: soignantId,
      type_document: t,
      s3_bucket: 'jolene-documents',
      s3_cle: `${soignantId}/seed/${t}.pdf`,
      nom_fichier: `${t}.pdf`,
      statut_verification: 'VERIFIE',
      valide_jusqua: null,
    })),
  );
}

/** Crée une mission OUVERTE pour le compte étab test. */
export async function seedMission(opts: {
  intitule?: string;
  profession?: string;
  debut?: Date;
  fin?: Date;
  tauxHoraire?: number;
} = {}): Promise<{ id: string; etablissement_id: string } | null> {
  const etabId = await userIdByEmail('playwright-etab@jolene.app');
  if (!etabId) return null;

  const debut = opts.debut || new Date(Date.now() + 7 * 86400000); // J+7
  const fin = opts.fin || new Date(debut.getTime() + 8 * 3600000); // 8h plus tard

  const { data: missionId, error } = await adminClient().rpc('fn_test_seed_mission' as any, {
    p_data: {
      etablissement_id: etabId,
      intitule: opts.intitule || `[playwright-test] Mission ${Date.now()}`,
      description: 'Mission générée par les tests Playwright',
      profession_requise: opts.profession || 'IDE',
      service: 'Test',
      debut_le: debut.toISOString(),
      fin_le: fin.toISOString(),
      duree_heures: 8,
      taux_horaire_base: opts.tauxHoraire || 25,
      statut: 'OUVERTE',
      mode_attribution: 'CANDIDATURE',
    },
  });

  if (error) {
    console.error('[seed] seedMission failed:', error.message);
    return null;
  }
  return { id: missionId as string, etablissement_id: etabId };
}

/** Crée une candidature pour le compte soignant test sur la mission donnée. */
export async function seedCandidature(missionId: string): Promise<{ id: string } | null> {
  const soignantId = await userIdByEmail('playwright-soignant@jolene.app');
  if (!soignantId) return null;

  const { data, error } = await adminClient()
    .from('candidatures' as any)
    .insert({
      mission_id: missionId,
      soignant_id: soignantId,
      statut: 'EN_ATTENTE',
    })
    .select('id')
    .single();

  if (error) {
    console.error('[seed] seedCandidature failed:', error.message);
    return null;
  }
  return data as { id: string };
}

/**
 * Marque une mission comme TERMINEE (pour tester flow notation).
 *
 * @deprecated Neutralisé par le durcissement prod post-Sprint 17 :
 * fn_valider_transition_statut_mission rejette OUVERTE → TERMINEE direct,
 * dec_proteger_mission_soignant reverte soignant_assigne_id pour un caller
 * service_role (auth.uid() NULL) et fn_creer_notification raise
 * « Non authentifié ». Utiliser le cycle de vie réel à la place :
 * seedCandidature + fn_traiter_candidature ACCEPTEE via userClient étab,
 * puis transitions ASSIGNEE → EN_COURS → TERMINEE par l'étab
 * (cf. e2e/flows/pointage.spec.ts et notation.spec.ts).
 */
export async function markMissionTerminee(missionId: string): Promise<boolean> {
  const soignantId = await userIdByEmail('playwright-soignant@jolene.app');
  if (!soignantId) return false;

  const { error } = await adminClient().rpc('fn_test_update_mission' as any, {
    p_mission_id: missionId,
    p_data: { statut: 'TERMINEE', soignant_assigne_id: soignantId },
  });

  return !error;
}

/**
 * Purge ordonnée d'une mission seedée et de ses enfants en FK NO ACTION vers
 * missions (bulletin de paie, cotisations, conformité, contrats,
 * conversation…) créés par fn_traiter_candidature / la clôture TERMINEE.
 * Sans cette purge préalable, le DELETE missions échoue en silence
 * (pattern pointage.spec.ts / anti-triche-pointage.spec.ts).
 * Chaque DELETE est tolérant aux erreurs (table absente, ligne déjà purgée).
 */
export async function cleanupMissionCascade(missionId?: string | null): Promise<void> {
  if (!missionId) return;
  // fn_test_purge_mission supprime dynamiquement TOUS les enfants FK (y compris
  // rappels_contrat_travail et messages_chat, que l'ancienne liste statique
  // oubliait) puis la mission, côté serveur. Sans ça le DELETE missions échouait
  // en silence → mission laissée ASSIGNÉE → test suivant en échec par chevauchement
  // sur le soignant de test partagé (run CI à 1 worker, donc en série).
  await adminClient()
    .rpc('fn_test_purge_mission' as any, { p_mission_id: missionId })
    .then(() => {}, () => {});
}

/** Supprime toutes les données seedées par les helpers (cleanup test) */
export async function cleanupSeedData(): Promise<void> {
  const etabId = await userIdByEmail('playwright-etab@jolene.app');
  if (!etabId) return;

  // Cascade : missions étab test → candidatures, notations, etc.
  await adminClient()
    .from('missions' as any)
    .delete()
    .eq('etablissement_id', etabId)
    .like('intitule', '[playwright-test]%');
}

/**
 * Garde-fou : skip un test si compte test fixe pas seedé.
 *
 * Les comptes `playwright-soignant@jolene.app` et `playwright-etab@jolene.app`
 * sont seedés via la migration 20260503050000_playwright_seed_test_accounts.sql.
 * La présence des secrets SUPABASE_SERVICE_ROLE_KEY + PLAYWRIGHT_TEST_PASSWORD
 * en CI est la condition suffisante (la migration a été appliquée à la prod).
 *
 * On évite l'appel `auth.admin.listUsers()` qui peut échouer silencieusement
 * (pagination, timeout, rate limit) et créer de faux skips.
 */
export async function hasTestAccount(_role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT'): Promise<boolean> {
  return !!process.env.SUPABASE_SERVICE_ROLE_KEY && !!process.env.PLAYWRIGHT_TEST_PASSWORD;
}

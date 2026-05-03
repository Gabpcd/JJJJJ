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

  const { data, error } = await adminClient()
    .from('missions' as any)
    .insert({
      etablissement_id: etabId,
      intitule: opts.intitule || `[playwright-test] Mission ${Date.now()}`,
      description: 'Mission générée par les tests Playwright',
      profession_requise: opts.profession || 'INFIRMIER',
      service: 'Test',
      debut_le: debut.toISOString(),
      fin_le: fin.toISOString(),
      taux_horaire_base: opts.tauxHoraire || 25,
      statut: 'OUVERTE',
      mode_attribution: 'CANDIDATURE',
    })
    .select('id, etablissement_id')
    .single();

  if (error) {
    console.error('[seed] seedMission failed:', error.message);
    return null;
  }
  return data as { id: string; etablissement_id: string };
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

/** Marque une mission comme TERMINEE (pour tester flow notation). */
export async function markMissionTerminee(missionId: string): Promise<boolean> {
  const soignantId = await userIdByEmail('playwright-soignant@jolene.app');
  if (!soignantId) return false;

  const { error } = await adminClient()
    .from('missions' as any)
    .update({ statut: 'TERMINEE', soignant_assigne_id: soignantId })
    .eq('id', missionId);

  return !error;
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
 * Usage : await requireTestAccount('SOIGNANT', test);
 */
export async function hasTestAccount(role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT'): Promise<boolean> {
  const email = role === 'SOIGNANT' ? 'playwright-soignant@jolene.app' : 'playwright-etab@jolene.app';
  try {
    const id = await userIdByEmail(email);
    return !!id;
  } catch {
    return false;
  }
}

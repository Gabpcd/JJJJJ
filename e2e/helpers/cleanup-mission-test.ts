import type { PostgrestError, SupabaseClient } from '@supabase/supabase-js';

export const PURGE_MISSION_RPC_TIMEOUT_MS = 25_000;

/**
 * Appelle l'unique purge SQL des missions techniques avec une borne réseau.
 *
 * Le timeout SQL de la fonction annule la transaction côté PostgreSQL ; cette
 * borne légèrement plus longue empêche aussi un proxy ou une connexion HTTP
 * interrompue de retenir indéfiniment le global setup Playwright.
 */
export async function purgerMissionTechniqueAvecTimeout(
  admin: SupabaseClient<any>,
  missionId: string,
): Promise<PostgrestError | null> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    PURGE_MISSION_RPC_TIMEOUT_MS,
  );

  try {
    const { error } = await admin
      .rpc('fn_test_purge_mission' as any, { p_mission_id: missionId })
      .abortSignal(controller.signal);
    return error;
  } finally {
    clearTimeout(timeout);
  }
}

export interface MissionTechniqueCleanup {
  id: string;
  intitule: string | null;
  etablissement_id: string | null;
  soignant_assigne_id?: string | null;
  fige_le?: string | null;
  statut?: string | null;
}

export type PreparationPurgeMission = 'PREPAREE' | 'QUARANTAINEE';

interface ErreurPurgeTechnique {
  code?: string | null;
  message: string;
}

export function estBlocagePurgeTechniqueAttendu(
  error: ErreurPurgeTechnique,
): boolean {
  if (
    error.code !== '23514'
    || error.message.includes('[PURGE_E2E_DURABLE]')
  ) {
    return false;
  }
  return (
    error.message.includes('Créneaux PREVISIONNEL immutables après gel')
    || error.message.includes(
      'Impossible de modifier les créneaux : une facture émise existe',
    )
  );
}

/** La quarantaine n'existe que pour la PR qui précède le déploiement SQL. */
export function estQuarantainePurgeAutorisee(): boolean {
  return (
    process.env.E2E_ALLOW_FROZEN_TEST_QUARANTINE === 'true'
    && process.env.GITHUB_EVENT_NAME === 'pull_request'
    && process.env.GITHUB_BASE_REF === 'main'
  );
}

export function estMissionTechniquePlaywright(
  intitule: string | null | undefined,
): boolean {
  return Boolean(
    intitule?.startsWith('[pw-test:')
      || intitule?.startsWith('[playwright-test]'),
  );
}

/**
 * Prépare une mission technique gelée pour une purge E2E exécutée contre le
 * schéma de production qui ne contient pas encore le purgeur durci de la PR.
 *
 * Le service_role ne suffit jamais à autoriser cette opération : le préfixe,
 * l'établissement, le soignant assigné et chaque candidat doivent tous être
 * explicitement marqués comme données de test.
 */
export async function preparerMissionTechniquePourPurge(
  admin: SupabaseClient<any>,
  mission: MissionTechniqueCleanup,
  etablissementTechniqueAttendu?: string,
): Promise<PreparationPurgeMission> {
  if (!mission.id || !estMissionTechniquePlaywright(mission.intitule)) {
    throw new Error(
      `[cleanup mission] dégel refusé hors mission Playwright (${mission.id || 'id absent'})`,
    );
  }
  if (!mission.etablissement_id) {
    throw new Error(`[cleanup mission] mission ${mission.id} sans établissement`);
  }
  if (
    etablissementTechniqueAttendu
    && mission.etablissement_id !== etablissementTechniqueAttendu
  ) {
    throw new Error(
      `[cleanup mission] mission ${mission.id} hors établissement Playwright attendu`,
    );
  }

  const { data: etablissement, error: etablissementError } = await admin
    .from('etablissements')
    .select('id, est_compte_test')
    .eq('id', mission.etablissement_id)
    .maybeSingle();
  if (etablissementError || etablissement?.est_compte_test !== true) {
    throw new Error(
      `[cleanup mission] mission ${mission.id} rattachée à un établissement non-test`,
    );
  }

  const soignantsLies = new Set<string>();
  if (mission.soignant_assigne_id) {
    soignantsLies.add(mission.soignant_assigne_id);
  }
  const { data: candidatures, error: candidaturesError } = await admin
    .from('candidatures')
    .select('soignant_id')
    .eq('mission_id', mission.id);
  if (candidaturesError) {
    throw new Error(
      `[cleanup mission] contrôle candidatures ${mission.id}: ${candidaturesError.message}`,
    );
  }
  for (const candidature of candidatures ?? []) {
    if (candidature.soignant_id) soignantsLies.add(candidature.soignant_id);
  }
  if (soignantsLies.size > 0) {
    const ids = [...soignantsLies];
    const { data: soignants, error: soignantsError } = await admin
      .from('soignants')
      .select('id, est_compte_test')
      .in('id', ids);
    if (
      soignantsError
      || (soignants ?? []).length !== ids.length
      || (soignants ?? []).some((soignant) => soignant.est_compte_test !== true)
    ) {
      throw new Error(
        `[cleanup mission] mission ${mission.id} liée à un soignant non-test`,
      );
    }
  }

  const annulationValide = [
    'OUVERTE',
    'ASSIGNEE',
    'EN_COURS',
    'LITIGE',
  ].includes(String(mission.statut ?? ''));

  // L'ancien backend ne possède pas l'override audité qui autorise le dégel.
  // On ne touche donc jamais à fige_le ici : une mission active devient
  // terminale et perd son soignant partagé ; une mission déjà terminale garde
  // son statut. Le purgeur durable supprimera ensuite le planning gelé.
  const { error: neutralisationError } = await admin.rpc(
    'fn_test_update_mission',
    {
      p_mission_id: mission.id,
      p_data: {
        ...(annulationValide
          ? { statut: 'ANNULEE_PAR_ETABLISSEMENT' }
          : {}),
        soignant_assigne_id: null,
      },
    },
  );
  if (neutralisationError) {
    throw new Error(
      `[cleanup mission] neutralisation ${mission.id}: ${neutralisationError.message}`,
    );
  }

  const { data: missionNeutralisee, error: verificationError } = await admin
    .from('missions')
    .select('fige_le, soignant_assigne_id, statut')
    .eq('id', mission.id)
    .maybeSingle();
  if (
    verificationError
    || missionNeutralisee?.soignant_assigne_id
    || (
      annulationValide
      && missionNeutralisee?.statut !== 'ANNULEE_PAR_ETABLISSEMENT'
    )
  ) {
    throw new Error(
      `[cleanup mission] neutralisation non confirmée ${mission.id}: ${verificationError?.message || 'état inattendu'}`,
    );
  }
  return mission.fige_le ? 'QUARANTAINEE' : 'PREPAREE';
}

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.99.2';

export type OperationalTestAccountResult =
  | { ok: true; isTest: boolean }
  | { ok: false; error: string };

type TestFlagRow = { est_compte_test: boolean | null };
type MissionSourceRow = {
  etablissement_id: string | null;
  soignant_assigne_id: string | null;
};
type EstablishmentMemberRow = {
  etablissement_id: string;
  etablissements:
    | TestFlagRow
    | TestFlagRow[]
    | null;
};

function memberTestFlag(
  member: EstablishmentMemberRow,
): boolean | null {
  const establishment = Array.isArray(member.etablissements)
    ? member.etablissements[0]
    : member.etablissements;
  return typeof establishment?.est_compte_test === 'boolean'
    ? establishment.est_compte_test
    : null;
}

/**
 * Résout le marqueur applicatif d'un compte opérationnel.
 *
 * L'appelant doit utiliser un client service_role. Une erreur de lecture est
 * distincte d'un compte non trouvé afin que les dispatchers externes puissent
 * échouer fermés au lieu d'envoyer « par défaut ».
 */
export async function resolveOperationalTestAccount(
  client: SupabaseClient,
  userId: string,
): Promise<OperationalTestAccountResult> {
  // Les profils historiques utilisent leur Auth UUID comme clé primaire.
  const [soignantResult, etablissementResult] = await Promise.all([
    client
      .from('soignants')
      .select('est_compte_test')
      .eq('id', userId)
      .maybeSingle(),
    client
      .from('etablissements')
      .select('est_compte_test')
      .eq('id', userId)
      .maybeSingle(),
  ]);

  if (soignantResult.error || etablissementResult.error) {
    return {
      ok: false,
      error: soignantResult.error?.message
        || etablissementResult.error?.message
        || 'classification compte indisponible',
    };
  }

  const directRows = [
    soignantResult.data as TestFlagRow | null,
    etablissementResult.data as TestFlagRow | null,
  ].filter(
    (row): row is TestFlagRow => row !== null && typeof row === 'object',
  );

  if (directRows.length > 0) {
    if (directRows.some((row) => typeof row.est_compte_test !== 'boolean')) {
      return { ok: false, error: 'classification compte incomplète' };
    }
    return {
      ok: true,
      isTest: directRows.some((row) => row.est_compte_test === true),
    };
  }

  // Les utilisateurs d'un établissement multi-comptes n'ont pas forcément
  // de ligne établissements à leur propre UUID. Leur classification se déduit
  // donc exclusivement de leurs établissements actifs.
  const [membersResult, adminResult] = await Promise.all([
    client
      .from('membres_etablissement')
      .select(
        'etablissement_id, etablissements!inner(est_compte_test)',
      )
      .eq('user_id', userId)
      .eq('actif', true),
    client
      .from('equipe_admin')
      .select('actif')
      .eq('user_id', userId)
      .eq('actif', true)
      .maybeSingle(),
  ]);

  if (membersResult.error || adminResult.error) {
    return {
      ok: false,
      error: membersResult.error?.message
        || adminResult.error?.message
        || 'classification rattachement indisponible',
    };
  }

  const members = (membersResult.data || []) as EstablishmentMemberRow[];
  if (members.length > 0) {
    const flags = members.map(memberTestFlag);
    if (flags.some((flag) => flag === null)) {
      return { ok: false, error: 'classification établissement incomplète' };
    }
    return {
      ok: true,
      // Fail-safe pour un membre multi-établissements : une seule fixture
      // suffit à neutraliser tout effet externe à son adresse.
      isTest: flags.some((flag) => flag === true),
    };
  }

  if (adminResult.data?.actif === true) {
    return { ok: true, isTest: false };
  }

  // Aucun type de compte opérationnel reconnu : ne jamais considérer cet UUID
  // comme réel par défaut.
  return { ok: false, error: 'compte opérationnel inconnu' };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function sourceValue(
  payload: Record<string, unknown>,
  key: string,
): unknown {
  if (payload[key] !== undefined) return payload[key];
  const nested = payload.data;
  if (
    nested
    && typeof nested === 'object'
    && !Array.isArray(nested)
  ) {
    return (nested as Record<string, unknown>)[key];
  }
  return undefined;
}

function sourceUuid(
  payload: Record<string, unknown>,
  key: string,
): { provided: false } | { provided: true; value: string | null } {
  const raw = sourceValue(payload, key);
  if (raw === undefined || raw === null || raw === '') {
    return { provided: false };
  }
  return {
    provided: true,
    value: typeof raw === 'string' && UUID_PATTERN.test(raw) ? raw : null,
  };
}

/**
 * Défense en profondeur pour les alertes adressées à un compte réel (souvent
 * un admin) mais issues d'une mission/litige de recette.
 */
export async function resolveOperationalTestSource(
  client: SupabaseClient,
  rawPayload: unknown,
): Promise<OperationalTestAccountResult> {
  if (
    !rawPayload
    || typeof rawPayload !== 'object'
    || Array.isArray(rawPayload)
  ) {
    return { ok: true, isTest: false };
  }
  const payload = rawPayload as Record<string, unknown>;
  const missionSource = sourceUuid(payload, 'mission_id');
  const disputeSource = sourceUuid(payload, 'litige_id');
  const establishmentSource = sourceUuid(payload, 'etablissement_id');
  const caregiverSource = sourceUuid(payload, 'soignant_id');

  for (const source of [
    missionSource,
    disputeSource,
    establishmentSource,
    caregiverSource,
  ]) {
    if (source.provided && source.value === null) {
      return { ok: false, error: 'identifiant source invalide' };
    }
  }

  let missionId = missionSource.provided ? missionSource.value : null;
  if (disputeSource.provided) {
    const { data, error } = await client
      .from('litiges')
      .select('mission_id')
      .eq('id', disputeSource.value!)
      .maybeSingle();
    if (error || !data || typeof data.mission_id !== 'string') {
      return {
        ok: false,
        error: error?.message || 'source litige introuvable',
      };
    }
    if (missionId && missionId !== data.mission_id) {
      return { ok: false, error: 'sources mission/litige incohérentes' };
    }
    missionId = data.mission_id;
  }

  const accountIds: string[] = [];
  if (missionId) {
    const { data, error } = await client
      .from('missions')
      .select('etablissement_id, soignant_assigne_id')
      .eq('id', missionId)
      .maybeSingle();
    const mission = data as MissionSourceRow | null;
    if (
      error
      || !mission
      || typeof mission.etablissement_id !== 'string'
      || !UUID_PATTERN.test(mission.etablissement_id)
      || (
        mission.soignant_assigne_id !== null
        && (
          typeof mission.soignant_assigne_id !== 'string'
          || !UUID_PATTERN.test(mission.soignant_assigne_id)
        )
      )
    ) {
      return {
        ok: false,
        error: error?.message || 'source mission introuvable',
      };
    }
    accountIds.push(mission.etablissement_id);
    if (mission.soignant_assigne_id) {
      accountIds.push(mission.soignant_assigne_id);
    }
  }
  if (establishmentSource.provided) {
    accountIds.push(establishmentSource.value!);
  }
  if (caregiverSource.provided) {
    accountIds.push(caregiverSource.value!);
  }

  for (const accountId of [...new Set(accountIds)]) {
    const classification = await resolveOperationalTestAccount(
      client,
      accountId,
    );
    if (!classification.ok) return classification;
    if (classification.isTest) return { ok: true, isTest: true };
  }
  return { ok: true, isTest: false };
}

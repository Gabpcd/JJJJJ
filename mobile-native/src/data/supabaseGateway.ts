import type { SupabaseClient } from '@supabase/supabase-js';
import { filtrerMissionsPlaywright } from '../../../src/lib/donnees-test';
import { defaultFilters, enrichMission, filterMissions, getMissionsCompatiblesFilter, throwIfAborted, validateContext } from './business';
import type { EtablissementSummary, Mission, MissionFilters, MissionGateway, MissionReadContext, MissionRecord, MissionSlot, RoleResult, SoignantProfile } from './types';

export const MISSION_SELECT = [
  'id', 'intitule', 'description', 'service', 'profession_requise',
  'specialite_medicale_requise', 'accepte_non_specialises', 'debut_le', 'fin_le',
  'duree_heures', 'nb_creneaux', 'taux_horaire_base', 'taux_rist_plafonne',
  'rist_plafond_applique', 'total_brut', 'net_a_payer', 'est_urgente',
  'niveau_urgence', 'statut', 'etablissement_id', 'type_contrat_recherche',
  'boostee_le', 'mode_remuneration', 'retrocession_pct',
].join(',');

const PROFILE_SELECT = 'id,profession,adresse_lat,adresse_lng,rayon_deplacement_km,tous_documents_valides,type_contrat,types_contrat_acceptes,type_exercice,taux_horaire_minimum';

/** Inject an ordinary authenticated client, never a service-role client.
 * All visibility, exclusions and TEST cohort restrictions stay in backend RLS.
 * No create/update/delete/payment/candidature endpoint exists in this adapter.
 */
export class SupabaseMissionGateway implements MissionGateway {
  readonly mode = 'supabase' as const;

  constructor(private readonly client: SupabaseClient, private readonly now: () => Date = () => new Date()) {}

  async getRole(signal?: AbortSignal): Promise<RoleResult> {
    throwIfAborted(signal);
    let request = this.client.rpc('fn_get_my_role');
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de vérifier votre espace. Réessayez.');
    return {
      role: typeof data?.role === 'string' ? data.role : 'INCONNU',
      etablissement_id: typeof data?.etablissement_id === 'string' ? data.etablissement_id : null,
    };
  }

  async getProfile(userId: string, signal?: AbortSignal): Promise<SoignantProfile | null> {
    throwIfAborted(signal);
    if (!userId) throw new Error('Session absente.');
    let request = this.client.from('soignants').select(PROFILE_SELECT).eq('id', userId);
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request.maybeSingle();
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger votre profil. Réessayez.');
    if (!data) return null;
    if (data.id !== userId) throw new Error('Le profil retourné ne correspond pas à la session.');
    // Onboarding uses fn_explorer_missions_inscription, a separate contract.
    // This first native slice must not turn an unfinished profile into a broad query.
    if (!data.profession) return null;
    return data as unknown as SoignantProfile;
  }

  async listMissions(context: MissionReadContext, input: MissionFilters = {}, signal?: AbortSignal): Promise<Mission[]> {
    validateContext(context);
    throwIfAborted(signal);
    const filters = { ...defaultFilters(context.profile), ...input };
    let request = this.client.from('missions').select(MISSION_SELECT)
      .eq('statut', 'OUVERTE').gte('debut_le', this.now().toISOString())
      .order('boostee_le', { ascending: false, nullsFirst: false })
      .order('est_urgente', { ascending: false }).order('debut_le', { ascending: true }).limit(500);
    const profession = filters.profession || context.profile.profession;
    const compatible = !filters.profession ? getMissionsCompatiblesFilter(profession) : null;
    request = compatible ? request.or(compatible) : request.eq('profession_requise', profession);
    if ((filters.tauxMin ?? 0) > 0) request = request.gte('taux_horaire_base', filters.tauxMin!);
    if (filters.urgentesOnly) request = request.eq('est_urgente', true);
    if (filters.etablissementId) request = request.eq('etablissement_id', filters.etablissementId);
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger les missions. Réessayez.');
    const records = filtrerMissionsPlaywright((data ?? []) as unknown as MissionRecord[], context.email);
    return filterMissions(await this.enrich(records, context, signal), context, filters);
  }

  async getMission(id: string, context: MissionReadContext, signal?: AbortSignal): Promise<Mission | null> {
    validateContext(context);
    throwIfAborted(signal);
    if (!id) return null;
    // Re-read under the current JWT. Navigation state is never an access grant.
    let request = this.client.from('missions').select(MISSION_SELECT).eq('id', id);
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request.maybeSingle();
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger cette mission. Réessayez.');
    if (!data) return null;
    const record = data as unknown as MissionRecord;
    if (record.id !== id) throw new Error('La mission retournée ne correspond pas à la demande.');
    if (filtrerMissionsPlaywright([record], context.email).length === 0) return null;
    return (await this.enrich([record], context, signal))[0] ?? null;
  }

  private async enrich(records: MissionRecord[], context: MissionReadContext, signal?: AbortSignal): Promise<Mission[]> {
    if (!records.length) return [];
    const [establishments, slots] = await Promise.all([
      this.establishments(records.map(m => m.etablissement_id), signal),
      this.slots(records.map(m => m.id), signal),
    ]);
    throwIfAborted(signal);
    return records.map(record => enrichMission(record, context,
      establishments.get(record.etablissement_id) ?? null, slots.filter(s => s.mission_id === record.id)));
  }

  private async establishments(ids: string[], signal?: AbortSignal): Promise<Map<string, EtablissementSummary>> {
    const unique = [...new Set(ids.filter(Boolean))];
    if (!unique.length) return new Map();
    let request = this.client.rpc('fn_etablissements_safe', { p_ids: unique });
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger les établissements des missions. Réessayez.');
    return new Map((data ?? []).filter((row: EtablissementSummary) => unique.includes(row.id))
      .map((row: EtablissementSummary): [string, EtablissementSummary] => [row.id, {
        id: row.id, nom: row.nom, adresse_ville: row.adresse_ville,
        adresse_code_postal: row.adresse_code_postal, adresse_lat: row.adresse_lat,
        adresse_lng: row.adresse_lng, type: row.type, logo_url: row.logo_url,
      }]));
  }

  /** Same bounded pagination as the web: never display a truncated schedule as exact. */
  private async slots(ids: string[], signal?: AbortSignal): Promise<MissionSlot[]> {
    const unique = [...new Set(ids)];
    const result: MissionSlot[] = [];
    for (let start = 0; start < unique.length; start += 50) {
      const batch = unique.slice(start, start + 50);
      const found = new Map<string, MissionSlot>();
      let offset = 0;
      let expected: number | null = null;
      while (expected === null || offset < expected) {
        throwIfAborted(signal);
        let request = this.client.from('mission_creneaux')
          .select('id,mission_id,debut,fin,est_pause,type_creneau', { count: 'exact' })
          .in('mission_id', batch).eq('type_creneau', 'PREVISIONNEL').eq('est_pause', false)
          .order('mission_id', { ascending: true }).order('debut', { ascending: true })
          .order('id', { ascending: true }).range(offset, offset + 499);
        if (signal) request = request.abortSignal(signal);
        const { data, error, count } = await request;
        throwIfAborted(signal);
        if (error) throw new Error('Impossible de charger le planning détaillé. Réessayez.');
        if (count === null || !Number.isInteger(count) || count < 0) throw new Error('Le nombre de créneaux ne peut pas être vérifié.');
        if (expected !== null && count !== expected) throw new Error('Le planning a changé pendant son chargement. Réessayez.');
        expected = count;
        const page = (data ?? []) as MissionSlot[];
        if (page.length === 0 && offset < expected) throw new Error('Le planning détaillé est incomplet.');
        for (const slot of page) {
          if (!slot.id || !slot.mission_id || !batch.includes(slot.mission_id)
            || slot.type_creneau !== 'PREVISIONNEL' || slot.est_pause || found.has(slot.id)) {
            throw new Error('Le planning détaillé contient des créneaux incohérents.');
          }
          found.set(slot.id, slot);
        }
        offset += page.length;
        if (offset > expected) throw new Error('Le planning détaillé contient des créneaux incohérents.');
      }
      if (found.size !== expected) throw new Error('Le planning détaillé est incomplet.');
      result.push(...found.values());
    }
    return result;
  }
}

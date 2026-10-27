import type { SupabaseClient } from '@supabase/supabase-js';
import { analyserCompletudePlanningMission } from '../../../src/lib/completude-planning-mission';
import { filtrerMissionsPlaywright } from '../../../src/lib/donnees-test';
import { throwIfAborted } from '../data/business';
import { MISSION_SELECT } from '../data/supabaseGateway';
import type { Mission, MissionRecord, MissionSlot } from '../data/types';
import { DEMO_ESTABLISHMENT_CONTEXT, DEMO_ESTABLISHMENT_PROFILE, demonstrationMissions } from './demo';
import { ESTABLISHMENT_PERMISSION_KEYS, MISSION_STATUS_OPTIONS, type EstablishmentContext, type EstablishmentMissionFilters, type EstablishmentMissionPage, type EstablishmentProfile, type EstablishmentReadGateway } from './types';

export const ESTABLISHMENT_PAGE_SIZE = 50;
const safeText = (value: unknown) => typeof value === 'string' ? value : null;
const safeBoolean = (value: unknown) => typeof value === 'boolean' ? value : null;

function validateContext(context: EstablishmentContext): void {
  if (!context.userId || !context.etablissementId || !context.permissions
    || ESTABLISHMENT_PERMISSION_KEYS.some(key => typeof context.permissions[key] !== 'boolean')
    || !context.permissions.lecture) throw new Error('Votre accès à cet établissement doit être vérifié.');
}
function filters(input: EstablishmentMissionFilters) {
  const offset = input.offset ?? 0;
  const status = input.status ?? '';
  if (!Number.isInteger(offset) || offset < 0 || offset % ESTABLISHMENT_PAGE_SIZE !== 0) throw new Error('Page de missions invalide.');
  if (!MISSION_STATUS_OPTIONS.some(option => option.value === status)) throw new Error('Statut de mission invalide.');
  return { offset, status, search: (input.search ?? '').trim().slice(0, 120) };
}
function asMission(record: MissionRecord, slots: MissionSlot[]): Mission {
  const planning = analyserCompletudePlanningMission(record, slots);
  return { ...record, etablissements: null, distance_km: null,
    creneaux_planifies: planning.creneauxPlanifies, planning_exact: planning.complet, erreur_planning: !planning.complet };
}
function assertRecords(records: MissionRecord[], context: EstablishmentContext, expectedId?: string): void {
  const ids = new Set<string>();
  for (const row of records) {
    if (!row || typeof row.id !== 'string' || !row.id || ids.has(row.id)
      || row.etablissement_id !== context.etablissementId || (expectedId && row.id !== expectedId)
      || typeof row.intitule !== 'string' || typeof row.statut !== 'string'
      || ['taux_horaire_base', 'retrocession_pct'].some(key => {
        const value = row[key as 'taux_horaire_base' | 'retrocession_pct'];
        return value !== null && (typeof value !== 'number' || !Number.isFinite(value));
      })
      || !Number.isFinite(Date.parse(row.debut_le)) || !Number.isFinite(Date.parse(row.fin_le))) {
      throw new Error('Les missions retournées ne correspondent pas à votre établissement.');
    }
    ids.add(row.id);
  }
}

/** Ordinary authenticated Supabase client only. Null explicitly selects offline demo.
 * RLS remains authoritative; no write endpoint or auth credential lives here. */
export class EstablishmentGateway implements EstablishmentReadGateway {
  readonly mode: 'demo' | 'supabase';
  constructor(private readonly client: SupabaseClient | null, private readonly now: () => Date = () => new Date()) {
    this.mode = client === null ? 'demo' : 'supabase';
  }
  private check(context: EstablishmentContext, signal?: AbortSignal): void {
    throwIfAborted(signal);
    validateContext(context);
    if (!this.client && (context.userId !== DEMO_ESTABLISHMENT_CONTEXT.userId
      || context.etablissementId !== DEMO_ESTABLISHMENT_CONTEXT.etablissementId
      || context.email !== DEMO_ESTABLISHMENT_CONTEXT.email)) throw new Error('Le contexte ne correspond pas à la démonstration.');
  }
  async getProfile(context: EstablishmentContext, signal?: AbortSignal): Promise<EstablishmentProfile | null> {
    this.check(context, signal);
    if (!this.client) return { ...DEMO_ESTABLISHMENT_PROFILE };
    let request = this.client.rpc('fn_mon_etablissement_complet');
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error || data?.error) throw new Error('Impossible de charger votre établissement.');
    if (!data) return null;
    if (data.id !== context.etablissementId || typeof data.nom !== 'string') throw new Error('Le profil retourné ne correspond pas à votre établissement.');
    // Do not propagate the full RPC payload (billing keys, bank metadata, etc.).
    return { id: data.id, nom: data.nom, type: safeText(data.type), siret: safeText(data.siret), finess: safeText(data.finess),
      adresse_rue: safeText(data.adresse_rue), adresse_ville: safeText(data.adresse_ville), adresse_code_postal: safeText(data.adresse_code_postal),
      email_contact: safeText(data.email_contact), telephone_contact: safeText(data.telephone_contact),
      statut_verification: safeText(data.statut_verification), contrat_service_signe: safeBoolean(data.contrat_service_signe),
      peut_publier_missions: safeBoolean(data.peut_publier_missions) };
  }
  async listMissions(context: EstablishmentContext, input: EstablishmentMissionFilters = {}, signal?: AbortSignal): Promise<EstablishmentMissionPage> {
    this.check(context, signal);
    const { offset, status, search } = filters(input);
    if (!this.client) {
      const { records, slots } = demonstrationMissions(this.now());
      const rows = records.filter(row => (!status || row.statut === status)
        && (!search || row.intitule.toLocaleLowerCase('fr').includes(search.toLocaleLowerCase('fr'))))
        .sort((a, b) => b.debut_le.localeCompare(a.debut_le) || a.id.localeCompare(b.id));
      return { missions: rows.slice(offset, offset + ESTABLISHMENT_PAGE_SIZE).map(row => asMission(row, slots.filter(slot => slot.mission_id === row.id))),
        nextOffset: offset + ESTABLISHMENT_PAGE_SIZE < rows.length ? offset + ESTABLISHMENT_PAGE_SIZE : null };
    }
    let request = this.client.from('missions').select(MISSION_SELECT, { count: 'exact' })
      .eq('etablissement_id', context.etablissementId)
      .order('debut_le', { ascending: false }).order('id', { ascending: true }).range(offset, offset + ESTABLISHMENT_PAGE_SIZE - 1);
    if (status) request = request.eq('statut', status);
    if (search) request = request.ilike('intitule', `%${search.replace(/[\\%_]/g, '\\$&')}%`);
    if (signal) request = request.abortSignal(signal);
    const { data, error, count } = await request;
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger les missions de votre établissement.');
    if (!Array.isArray(data) || count === null || !Number.isInteger(count) || count < 0
      || data.length !== Math.min(ESTABLISHMENT_PAGE_SIZE, Math.max(0, count - offset))) throw new Error('La liste des missions est incomplète.');
    const rows = data as unknown as MissionRecord[];
    assertRecords(rows, context);
    const visible = filtrerMissionsPlaywright(rows, context.email);
    const slots = await this.slots(visible.map(row => row.id), signal);
    return { missions: visible.map(row => asMission(row, slots.filter(slot => slot.mission_id === row.id))),
      nextOffset: offset + rows.length < count ? offset + ESTABLISHMENT_PAGE_SIZE : null };
  }
  async getMission(id: string, context: EstablishmentContext, signal?: AbortSignal): Promise<Mission | null> {
    this.check(context, signal);
    if (!id) return null;
    if (!this.client) {
      const { records, slots } = demonstrationMissions(this.now());
      const row = records.find(record => record.id === id);
      return row ? asMission(row, slots.filter(slot => slot.mission_id === id)) : null;
    }
    let request = this.client.from('missions').select(MISSION_SELECT)
      .eq('etablissement_id', context.etablissementId).eq('id', id);
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request.maybeSingle();
    throwIfAborted(signal);
    if (error) throw new Error('Impossible de charger cette mission.');
    if (!data) return null;
    const row = data as unknown as MissionRecord;
    assertRecords([row], context, id);
    if (filtrerMissionsPlaywright([row], context.email).length === 0) return null;
    return asMission(row, await this.slots([id], signal));
  }
  private async slots(ids: string[], signal?: AbortSignal): Promise<MissionSlot[]> {
    if (!ids.length || !this.client) return [];
    const found = new Map<string, MissionSlot>();
    let offset = 0;
    let expected: number | null = null;
    while (expected === null || offset < expected) {
      throwIfAborted(signal);
      let request = this.client.from('mission_creneaux').select('id,mission_id,debut,fin,est_pause,type_creneau', { count: 'exact' })
        .in('mission_id', ids).eq('type_creneau', 'PREVISIONNEL').eq('est_pause', false)
        .order('mission_id', { ascending: true }).order('debut', { ascending: true }).order('id', { ascending: true })
        .range(offset, offset + 499);
      if (signal) request = request.abortSignal(signal);
      const { data, error, count } = await request;
      throwIfAborted(signal);
      if (error) throw new Error('Impossible de charger le planning détaillé.');
      if (!Array.isArray(data) || count === null || !Number.isInteger(count) || count < 0
        || (expected !== null && count !== expected) || (data.length === 0 && offset < count)) throw new Error('Le planning détaillé est incomplet ou a changé.');
      expected = count;
      for (const slot of data as MissionSlot[]) {
        if (!slot.id || !slot.mission_id || !ids.includes(slot.mission_id) || found.has(slot.id)
          || slot.type_creneau !== 'PREVISIONNEL' || slot.est_pause) throw new Error('Le planning contient des créneaux incohérents.');
        found.set(slot.id, slot);
      }
      offset += data.length;
      if (offset > expected) throw new Error('Le planning contient des créneaux incohérents.');
    }
    return [...found.values()];
  }
}

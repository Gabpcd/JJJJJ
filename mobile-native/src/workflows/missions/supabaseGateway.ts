import type { SupabaseClient } from '@supabase/supabase-js';
import { calculerCompletionProfil } from '../../../../src/lib/profil-soignant';
import { creneauxConfirmesPourAction } from '../../../../src/components/planning/planning-candidat';
import { filtrerMissionsPlaywright } from '../../../../src/lib/donnees-test';
import { throwIfAborted, validateContext } from '../../data/business';
import { SupabaseMissionGateway } from '../../data/supabaseGateway';
import type { MissionReadContext } from '../../data/types';
import { acceptanceEmailJobs, sendAcceptanceEmails } from './acceptanceEmails';
import { alreadyApplied, applicationAction, hasActiveAssignment, isTerminalMission, statusLabel, type AcceptanceEmailReceipt, type ApplicationRecord, type ApplicationSnapshot, type ApplyInput,
  type ApplyResult, type ContractOption, type MissionWorkflowGateway, type MyMission, type MyMissionsPage, type MyMissionsTab } from './types';

const PAGE_SIZE = 20;
const MINE_SELECT = 'id,intitule,debut_le,fin_le,statut,etablissement_id,type_contrat_applique,type_contrat_recherche,soignant_assigne_id';
type Row = { id: string; intitule: string; debut_le: string; fin_le: string; statut: string; etablissement_id: string;
  type_contrat_applique: string | null; type_contrat_recherche: string | null; soignant_assigne_id: string | null };
const RECONCILE_MESSAGE = 'L’envoi ne peut pas être confirmé. Rechargez l’état de la mission avant toute nouvelle tentative.';

/** Ordinary authenticated STAGING client, already admitted by nativeRuntime. Provider access stays server-side. */
export class SupabaseMissionWorkflowGateway implements MissionWorkflowGateway {
  readonly mode = 'supabase' as const;
  private readonly missions: SupabaseMissionGateway;
  private readonly inFlight = new Set<string>();
  private readonly emailJobs = new Map<string, ReturnType<typeof acceptanceEmailJobs>>();
  private readonly emailPreparationFailures = new Map<string, AcceptanceEmailReceipt[]>();
  constructor(private readonly client: SupabaseClient) { this.missions = new SupabaseMissionGateway(client); }

  async listMine(context: MissionReadContext, tab: MyMissionsTab, page = 0, signal?: AbortSignal): Promise<MyMissionsPage> {
    validateContext(context); throwIfAborted(signal);
    if (!Number.isInteger(page) || page < 0) throw new Error('Page invalide.');
    let rows: Row[] = []; let hasMore = false;
    const applications = new Map<string, ApplicationRecord>();
    if (tab === 'candidatures') {
      let query = this.client.from('candidatures').select('id,mission_id,statut,type_contrat_choisi', { count: 'exact' })
        .eq('soignant_id', context.userId).order('cree_le', { ascending: false }).order('id', { ascending: false })
        .range(0, (page + 1) * PAGE_SIZE - 1);
      if (signal) query = query.abortSignal(signal);
      const { data, error, count } = await query; throwIfAborted(signal);
      if (error || !Array.isArray(data) || count === null) throw new Error('Les candidatures ne peuvent pas être chargées.');
      hasMore = count > (page + 1) * PAGE_SIZE;
      for (const row of data) if (!applications.has(row.mission_id)) applications.set(row.mission_id, row);
      if (applications.size) {
        let missions = this.client.from('missions').select(MINE_SELECT).in('id', [...applications.keys()]);
        if (signal) missions = missions.abortSignal(signal);
        const result = await missions; throwIfAborted(signal);
        if (result.error || !Array.isArray(result.data)) throw new Error('Les missions des candidatures ne peuvent pas être chargées.');
        const byId = new Map(result.data.map(row => [row.id, row as Row]));
        rows = [...applications.keys()].flatMap(id => byId.has(id) ? [byId.get(id)!] : []);
      }
    } else {
      let query = this.client.from('missions').select(MINE_SELECT, { count: 'exact' })
        .eq('soignant_assigne_id', context.userId)
        .in('statut', tab === 'actives' ? ['ASSIGNEE', 'EN_COURS']
          : ['TERMINEE', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT', 'ABSENCE', 'LITIGE'])
        .order('debut_le', { ascending: tab === 'actives' }).order('id', { ascending: true })
        .range(0, (page + 1) * PAGE_SIZE - 1);
      if (signal) query = query.abortSignal(signal);
      const result = await query; throwIfAborted(signal);
      if (result.error || !Array.isArray(result.data) || result.count === null) throw new Error('Vos missions ne peuvent pas être chargées.');
      rows = result.data as Row[]; hasMore = result.count > (page + 1) * PAGE_SIZE;
      if (rows.some(row => row.soignant_assigne_id !== context.userId)) throw new Error('La liste ne correspond pas à votre compte.');
    }
    rows = filtrerMissionsPlaywright(rows, context.email);
    const ids = [...new Set(rows.map(row => row.etablissement_id))];
    let establishments: Array<{ id: string; nom: string; adresse_ville: string | null }> = [];
    if (ids.length) {
      let query = this.client.rpc('fn_etablissements_safe', { p_ids: ids });
      if (signal) query = query.abortSignal(signal);
      const result = await query; throwIfAborted(signal);
      if (result.error || !Array.isArray(result.data)) throw new Error('Les établissements ne peuvent pas être chargés.');
      establishments = result.data;
    }
    const mapped: MyMission[] = rows.map(row => {
      const establishment = establishments.find(item => item.id === row.etablissement_id);
      const application = applications.get(row.id);
      return { id: row.id, title: row.intitule, startsAt: row.debut_le, endsAt: row.fin_le, status: row.statut,
        establishment: establishment?.nom ?? 'Établissement', city: establishment?.adresse_ville ?? null,
        contract: row.type_contrat_applique ?? application?.type_contrat_choisi ?? row.type_contrat_recherche,
        applicationId: application?.id ?? null, applicationStatus: application?.statut ?? null };
    });
    return { rows: mapped, page, hasMore };
  }

  async readApplication(context: MissionReadContext, missionId: string, signal?: AbortSignal): Promise<ApplicationSnapshot | null> {
    validateContext(context); throwIfAborted(signal);
    let meta = this.client.from('missions').select('id,mode_attribution,soignant_assigne_id,type_contrat_applique,modifie_le').eq('id', missionId);
    let profile = this.client.rpc('fn_mon_profil_soignant_complet');
    let applications = this.client.from('candidatures').select('id,statut,type_contrat_choisi')
      .eq('mission_id', missionId).eq('soignant_id', context.userId)
      .order('cree_le', { ascending: false }).order('id', { ascending: false }).limit(1);
    if (signal) { meta = meta.abortSignal(signal); profile = profile.abortSignal(signal); applications = applications.abortSignal(signal); }
    const [mission, metadata, completeProfile, candidature] = await Promise.all([
      this.missions.getMission(missionId, context, signal), meta.maybeSingle(), profile, applications,
    ]);
    throwIfAborted(signal);
    if (metadata.error || completeProfile.error || candidature.error) throw new Error('Le dossier de candidature ne peut pas être vérifié.');
    if (!mission || !metadata.data) return null;
    if (metadata.data.id !== missionId || !completeProfile.data || completeProfile.data.id !== context.userId
      || !Array.isArray(candidature.data)) throw new Error('Le dossier ne correspond pas à votre compte.');
    const completion = calculerCompletionProfil(completeProfile.data);
    return { userId: context.userId, mission, attribution: metadata.data.mode_attribution,
      assignedTo: metadata.data.soignant_assigne_id, appliedContract: metadata.data.type_contrat_applique,
      assignmentRevision: metadata.data.modifie_le,
      application: candidature.data[0] ?? null, canApply: completion.peut_candidater,
      missingProfile: completion.items_obligatoires_manquants.map(item => item.label),
      documentsComplete: completeProfile.data.tous_documents_valides === true,
      caregiver: { firstName: String(completeProfile.data.prenom ?? ''), lastName: String(completeProfile.data.nom ?? ''), profession: String(completeProfile.data.profession ?? '') },
      acceptanceEmails: this.emailJobs.get(`${context.userId}:${missionId}`)?.map(job => ({ ...job.receipt }))
        ?? this.emailPreparationFailures.get(`${context.userId}:${missionId}`)?.map(receipt => ({ ...receipt })),
      exactPersistedPlanning: mission.planning_exact && !mission.erreur_planning
        && mission.creneaux_planifies.length > 0 && mission.creneaux_planifies.every(slot => Boolean(slot.id && slot.fin)) };
  }

  async apply(context: MissionReadContext, snapshot: ApplicationSnapshot, input: ApplyInput, signal?: AbortSignal): Promise<ApplyResult> {
    validateContext(context); throwIfAborted(signal);
    const action = applicationAction(snapshot);
    const slots = creneauxConfirmesPourAction(snapshot.mission);
    if (snapshot.userId !== context.userId || !action || !slots) throw new Error('Rechargez la mission et confirmez son planning avant de continuer.');
    if (input.contractChoice && !['SALARIE', 'LIBERAL'].includes(input.contractChoice)) throw new Error('Choix de contrat invalide.');
    if (input.message.length > 2000) throw new Error('Le message doit contenir au maximum 2 000 caractères.');
    const key = `${context.userId}:${snapshot.mission.id}`;
    if (this.inFlight.has(key)) throw new Error('Une demande est déjà en cours. Patientez puis rechargez la mission.');
    this.inFlight.add(key);
    try {
      const session = await this.client.auth.getSession(); throwIfAborted(signal);
      const token = session.data.session?.access_token;
      if (session.error || !token || session.data.session?.user.id !== context.userId) throw new Error('Votre session a changé. Reconnectez-vous avant de continuer.');
      const identity = await this.client.auth.getUser(token); throwIfAborted(signal);
      if (identity.error || identity.data.user?.id !== context.userId) throw new Error('Votre session a changé. Reconnectez-vous avant de continuer.');
      let response: { data: any; error: unknown };
      try {
        // Never auto-retry a mutation. The bounded runtime fetch handles network timeout.
        response = await this.client.rpc('fn_confirmer_action_planning_v1', {
          p_mission_id: snapshot.mission.id, p_action: action, p_creneaux_confirmes: slots,
          p_message: action === 'POSTULER' ? input.message.trim() || null : null,
          p_choix_contrat: input.contractChoice ?? null, p_candidature_id: null,
        }).setHeader('Authorization', `Bearer ${token}`);
      } catch { response = { data: null, error: new Error(RECONCILE_MESSAGE) }; }
      throwIfAborted(signal);
      let fresh: ApplicationSnapshot | null = null;
      try { fresh = await this.readApplication(context, snapshot.mission.id, signal); } catch { /* No invented success after a failed readback. */ }
      throwIfAborted(signal);
      const data = response.data;
      if (fresh && isTerminalMission(fresh)) return { kind: 'rejected', snapshot: fresh,
        message: `${statusLabel(fresh.mission.statut)}. Son état a changé ; aucun email d’acceptation n’est envoyé.` };
      if (fresh && (action === 'ACCEPTER' ? fresh.assignedTo === context.userId : alreadyApplied(fresh))) {
        if (action === 'ACCEPTER') {
          try {
            const prepared = acceptanceEmailJobs(fresh, typeof data?.contrat_id === 'string' ? data.contrat_id : undefined);
            if (this.emailJobs.get(key)?.[0]?.body.idempotency_key !== prepared[0]?.body.idempotency_key) this.emailJobs.set(key, prepared);
            this.emailPreparationFailures.delete(key);
            fresh.acceptanceEmails = await sendAcceptanceEmails(this.client, token, this.emailJobs.get(key)!, signal);
          } catch {
            // Assignment is already confirmed. An email preparation error must never replay it.
            fresh.acceptanceEmails = [{ recipient: 'soignant', state: 'failed', reason: 'preparation_failed' },
              { recipient: 'etablissement', state: 'failed', reason: 'preparation_failed' }];
            this.emailPreparationFailures.set(key, fresh.acceptanceEmails);
          }
          throwIfAborted(signal);
        }
        return { kind: 'confirmed', snapshot: fresh, documentsToComplete: data?.docs_a_completer === true || !fresh.documentsComplete };
      }
      if (response.error || !data || !fresh) return { kind: 'unconfirmed', snapshot: fresh, message: RECONCILE_MESSAGE };
      if (data.choix_requis === true) {
        const options: ContractOption[] = Array.isArray(data.options) ? data.options
          .filter((option: any) => option && ['SALARIE', 'LIBERAL'].includes(option.value) && typeof option.label === 'string')
          .map((option: ContractOption) => ({ value: option.value, label: option.label })) : [];
        if (!options.length) return { kind: 'rejected', snapshot: fresh, message: 'Les choix de contrat sont indisponibles. Rechargez la mission.' };
        return { kind: 'choice', snapshot: fresh, options };
      }
      if (data.error || data.success === false || data.ok === false) {
        return { kind: 'rejected', snapshot: fresh, message: typeof data.error === 'string' ? data.error : 'Le serveur a refusé cette demande. Vérifiez votre dossier.' };
      }
      return { kind: 'unconfirmed', snapshot: fresh, message: RECONCILE_MESSAGE };
    } finally { this.inFlight.delete(key); }
  }

  async retryAcceptanceEmails(context: MissionReadContext, missionId: string, signal?: AbortSignal) {
    validateContext(context); throwIfAborted(signal);
    const key = `${context.userId}:${missionId}`;
    const jobs = this.emailJobs.get(key);
    if (!jobs) throw new Error('Aucun envoi à reprendre dans cette session. Consultez votre mission pour vérifier son état.');
    if (this.inFlight.has(key)) throw new Error('Une demande est déjà en cours.');
    this.inFlight.add(key);
    try {
      const session = await this.client.auth.getSession(); throwIfAborted(signal);
      const token = session.data.session?.access_token;
      if (session.error || !token || session.data.session?.user.id !== context.userId) throw new Error('Votre session a changé. Reconnectez-vous.');
      const identity = await this.client.auth.getUser(token); throwIfAborted(signal);
      if (identity.error || identity.data.user?.id !== context.userId) throw new Error('Votre session ne peut pas être vérifiée.');
      const fresh = await this.readApplication(context, missionId, signal);
      if (!fresh || !hasActiveAssignment(fresh)) throw new Error('L’attribution n’est plus active. Aucun email n’a été relancé.');
      return await sendAcceptanceEmails(this.client, token, jobs, signal);
    } finally { this.inFlight.delete(key); }
  }
}

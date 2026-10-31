import type { SupabaseClient } from '@supabase/supabase-js';
import { ACTIVE_PRESENCE_STATUSES, HISTORY_PRESENCE_STATUSES, PRESENCE_ID, PRESENCE_STAGING_ORIGIN,
  availability, parsePresenceCode, proofMatchesSegment, rejectedScanMessage, validGps } from './business';
import { PresenceWorkflowError, type PresenceClockPort, type PresenceContext, type PresenceContract, type PresenceDetails,
  type PresenceGateway, type PresenceGpsPort, type PresenceMission, type PresencePage, type PresenceProof,
  type PresenceQrPort, type PresenceScanResult, type PresenceSegment, type GpsObservation, type QrCapture,
  type PresenceAttemptJournal, type PresenceAttemptReceipt } from './types';

const MISSION = 'id,etablissement_id,soignant_assigne_id,intitule,service,statut,debut_le,fin_le,nb_creneaux';
const SEGMENT = 'id,mission_id,debut,fin,est_pause,type_creneau';
const CONTRACT = 'id,mission_id,etablissement_id,soignant_id,statut,cree_le';
// code_saisi and id_terminal are filters only, never returned to the screen or logged.
const PROOF = 'id,mission_id,soignant_id,numero_scan,type_scan,scanne_le,horodatage_arrondi,creneau_effectif_id,validation_etab_requise,valide_par_etab';
type Reply = { data: any; error: any; count?: number | null };
type Identity = { context: PresenceContext; authorization: string; gpsConsent: boolean; test: boolean;
  displayCode: boolean; readContracts: boolean };
type Attempt = { id: string; userId: string; code: string; baseline: Set<string>; terminalId: string;
  gps: GpsObservation['kind']; reply: any | null; receipt: PresenceAttemptReceipt };
function attemptFrom(receipt: PresenceAttemptReceipt): Attempt {
  return { id: receipt.attemptId, userId: receipt.userId, code: receipt.enteredCode, baseline: new Set(receipt.baselineProofIds),
    terminalId: receipt.terminalId, gps: receipt.gps, reply: null, receipt };
}
const date = (value: unknown): value is string => typeof value === 'string' && Number.isFinite(Date.parse(value));
const id = (value: unknown): value is string => typeof value === 'string' && PRESENCE_ID.test(value);
function invalid(): never { throw new PresenceWorkflowError('INVALID_SCOPE', 'Ce pointage ne correspond pas à votre compte ou à vos droits.'); }
function unavailable(): never { throw new PresenceWorkflowError('UNAVAILABLE', 'Le pointage ne peut pas être relu complètement. Rechargez son état.'); }
function abort(signal?: AbortSignal): void {
  if (signal?.aborted) throw Object.assign(new Error('Opération interrompue.'), { name: 'AbortError' });
}
function isSameContext(a: PresenceContext | null, b: PresenceContext): boolean {
  return !!a && a.userId === b.userId && a.epoch === b.epoch && a.kind === b.kind
    && (a.kind !== 'etablissement' || b.kind === 'etablissement' && a.etablissementId === b.etablissementId);
}
function checkedMission(raw: any, identity: Identity, requestedId?: string): PresenceMission {
  if (!raw || !id(raw.id) || !id(raw.etablissement_id) || raw.soignant_assigne_id !== null && !id(raw.soignant_assigne_id)
    || requestedId && raw.id !== requestedId || typeof raw.intitule !== 'string' || typeof raw.statut !== 'string'
    || raw.service !== null && typeof raw.service !== 'string' || !date(raw.debut_le) || !date(raw.fin_le)
    || raw.nb_creneaux !== null && (!Number.isInteger(raw.nb_creneaux) || raw.nb_creneaux < 0)) invalid();
  const context = identity.context;
  if (context.kind === 'soignant' ? raw.soignant_assigne_id !== context.userId : raw.etablissement_id !== context.etablissementId) invalid();
  return { id: raw.id, etablissement_id: raw.etablissement_id, soignant_assigne_id: raw.soignant_assigne_id,
    intitule: raw.intitule, service: raw.service, statut: raw.statut, debut_le: raw.debut_le, fin_le: raw.fin_le, nb_creneaux: raw.nb_creneaux };
}
function checkedSegment(raw: any, missionId: string): PresenceSegment {
  if (!raw || !id(raw.id) || raw.mission_id !== missionId || !date(raw.debut) || raw.fin !== null && !date(raw.fin)
    || typeof raw.est_pause !== 'boolean' || !['PREVISIONNEL', 'EFFECTIF'].includes(raw.type_creneau)) invalid();
  return { id: raw.id, mission_id: missionId, debut: raw.debut, fin: raw.fin, est_pause: raw.est_pause, type_creneau: raw.type_creneau };
}
function checkedProof(raw: any, userId: string): PresenceProof {
  if (!raw || !id(raw.id) || !id(raw.mission_id) || raw.soignant_id !== userId || !id(raw.creneau_effectif_id)
    || !Number.isInteger(raw.numero_scan) || raw.numero_scan < 1 || !['OUVERTURE', 'FERMETURE'].includes(raw.type_scan)
    || !date(raw.scanne_le) || !date(raw.horodatage_arrondi) || typeof raw.validation_etab_requise !== 'boolean'
    || typeof raw.valide_par_etab !== 'boolean') invalid();
  return { id: raw.id, mission_id: raw.mission_id, soignant_id: userId, creneau_effectif_id: raw.creneau_effectif_id,
    numero_scan: raw.numero_scan, type_scan: raw.type_scan, scanne_le: raw.scanne_le, horodatage_arrondi: raw.horodatage_arrondi,
    validation_etab_requise: raw.validation_etab_requise, valide_par_etab: raw.valide_par_etab };
}

/** Ordinary-user STAGING transport. Only fn_scanner_code_pointage mutates; no direct table writes. */
export class SupabasePresenceGateway implements PresenceGateway {
  readonly mode = 'supabase' as const;
  private readonly inFlight = new Set<string>();
  private readonly cleanupUnverified = new Set<string>();
  constructor(private readonly client: SupabaseClient, private readonly options: {
    currentSession: () => PresenceContext | null;
    terminalId: string;
    newAttemptId: () => string;
    clock: PresenceClockPort;
    journal: PresenceAttemptJournal;
    gps?: PresenceGpsPort;
  }) {
    const sentinel = new URL(client.storage.from('documents').getPublicUrl('native-presence-origin').data.publicUrl);
    if (sentinel.origin !== PRESENCE_STAGING_ORIGIN || sentinel.pathname !== '/storage/v1/object/public/documents/native-presence-origin'
      || sentinel.username || sentinel.password || sentinel.search || sentinel.hash
      || !/^[A-Za-z0-9._:-]{1,160}$/.test(options.terminalId)) invalid();
  }
  private assertContext(context: PresenceContext, signal?: AbortSignal): void {
    abort(signal);
    if (!context || !id(context.userId) || !Number.isSafeInteger(context.epoch) || context.epoch < 0
      || !['soignant', 'etablissement'].includes(context.kind)
      || context.kind === 'etablissement' && !id(context.etablissementId)) invalid();
    if (!isSameContext(this.options.currentSession(), context)) {
      throw new PresenceWorkflowError('SESSION_CHANGED', 'Votre session a changé. Revenez à votre espace avant de continuer.');
    }
  }
  private async current(identity: Identity, signal?: AbortSignal): Promise<void> {
    this.assertContext(identity.context, signal);
    const session = await this.client.auth.getSession(); this.assertContext(identity.context, signal);
    if (session.error || session.data.session?.user.id !== identity.context.userId || !session.data.session?.access_token) {
      throw new PresenceWorkflowError('SESSION_CHANGED', 'Reconnectez-vous avant de continuer.');
    }
  }
  private async query(identity: Identity, request: any, signal?: AbortSignal): Promise<Reply> {
    await this.current(identity, signal);
    request = request.setHeader('Authorization', identity.authorization);
    // maybeSingle removes abortSignal from the builder; its caller already bound the signal before conversion.
    if (signal && typeof request.abortSignal === 'function') request = request.abortSignal(signal);
    let response: Reply;
    try { response = await request; } catch { response = { data: null, error: true }; }
    await this.current(identity, signal); return response;
  }
  private rpc(identity: Identity, name: string, args: Record<string, unknown>, signal?: AbortSignal) {
    return this.query(identity, this.client.rpc(name, args), signal);
  }
  private async identity(context: PresenceContext, signal?: AbortSignal): Promise<Identity> {
    context = { ...context }; this.assertContext(context, signal);
    const session = await this.client.auth.getSession(); this.assertContext(context, signal);
    const token = session.data.session?.access_token;
    if (session.error || !token || session.data.session?.user.id !== context.userId) invalid();
    const auth = await this.client.auth.getUser(token); this.assertContext(context, signal);
    if (auth.error || auth.data.user?.id !== context.userId || !auth.data.user.email_confirmed_at) invalid();
    const identity: Identity = { context, authorization: `Bearer ${token}`, gpsConsent: false, test: false,
      displayCode: false, readContracts: context.kind === 'soignant' };
    const role = await this.rpc(identity, 'fn_get_my_role', {}, signal);
    if (role.error || !role.data || role.data.parcours_incomplet === true
      || role.data.user_id && role.data.user_id !== context.userId) invalid();
    if (context.kind === 'soignant') {
      if (role.data.role !== 'SOIGNANT') invalid();
    } else {
      if (!['ETABLISSEMENT', 'ADMIN_ETABLISSEMENT'].includes(role.data.role)
        || role.data.etablissement_id && role.data.etablissement_id !== context.etablissementId) invalid();
      const scope = await this.rpc(identity, 'fn_mes_permissions_etab', { p_etablissement_id: context.etablissementId }, signal);
      if (scope.error || scope.data?.success !== true || scope.data.etablissement_id !== context.etablissementId
        || typeof scope.data.role !== 'string' || !scope.data.role) invalid();
      for (const permission of ['lecture_pointage', 'pointage', 'lecture_contrats']) {
        const result = await this.rpc(identity, 'fn_a_permission_etablissement', {
          p_permission: permission, p_etablissement_id: context.etablissementId,
        }, signal);
        if (result.error || typeof result.data !== 'boolean') unavailable();
        if (permission === 'lecture_pointage' && !result.data) invalid();
        if (permission === 'pointage') identity.displayCode = result.data;
        if (permission === 'lecture_contrats') identity.readContracts = result.data;
      }
    }
    const target = context.kind === 'soignant' ? context.userId : context.etablissementId;
    let profile = this.client.from(context.kind === 'soignant' ? 'soignants' : 'etablissements')
      .select(context.kind === 'soignant' ? 'id,est_compte_test,consentement_gps' : 'id,est_compte_test').eq('id', target);
    if (signal) profile = profile.abortSignal(signal);
    const result = await this.query(identity, profile.maybeSingle(), signal);
    if (result.error || result.data?.id !== target) invalid();
    identity.test = result.data.est_compte_test === true;
    identity.gpsConsent = context.kind === 'soignant' && result.data.consentement_gps === true;
    return identity;
  }
  /** Canonical read only. OS permission and the UI switch never grant server consent. */
  async readGpsConsent(context: PresenceContext, signal?: AbortSignal): Promise<boolean> {
    const identity = await this.identity(context, signal);
    return context.kind === 'soignant' && identity.gpsConsent;
  }
  private missionQuery(identity: Identity, count = false) {
    const context = identity.context;
    return this.client.from('missions').select(MISSION, count ? { count: 'exact' } : undefined)
      .eq(context.kind === 'soignant' ? 'soignant_assigne_id' : 'etablissement_id',
        context.kind === 'soignant' ? context.userId : context.etablissementId);
  }
  private async mission(identity: Identity, missionId: string, signal?: AbortSignal): Promise<PresenceMission> {
    if (!id(missionId)) invalid();
    let request = this.missionQuery(identity).eq('id', missionId); if (signal) request = request.abortSignal(signal);
    const response = await this.query(identity, request.maybeSingle(), signal);
    if (response.error || !response.data) unavailable();
    return checkedMission(response.data, identity, missionId);
  }
  /** Exact-count pages prevent silently losing scheduled periods or reconciliation evidence. */
  private async all(identity: Identity, query: (offset: number) => any, signal?: AbortSignal): Promise<any[]> {
    const rows: any[] = []; const ids = new Set<string>(); let expected: number | null = null;
    do {
      const response = await this.query(identity, query(rows.length), signal);
      if (response.error || !Array.isArray(response.data) || !Number.isSafeInteger(response.count) || response.count! < 0
        || response.count! > 10_000 || expected !== null && response.count !== expected) unavailable();
      expected = response.count!;
      if (!response.data.length && rows.length < expected || rows.length + response.data.length > expected) unavailable();
      for (const row of response.data) { if (!id(row?.id) || ids.has(row.id)) unavailable(); ids.add(row.id); rows.push(row); }
    } while (rows.length < expected!);
    return rows;
  }
  async list(context: PresenceContext, options: { status?: 'active' | 'history'; offset?: number } = {}, signal?: AbortSignal): Promise<PresencePage> {
    const offset = options.offset ?? 0; const status = options.status ?? 'active';
    if (!Number.isSafeInteger(offset) || offset < 0 || offset > 100_000 || !['active', 'history'].includes(status)) invalid();
    const identity = await this.identity(context, signal);
    const statuses = status === 'active' ? ACTIVE_PRESENCE_STATUSES : HISTORY_PRESENCE_STATUSES;
    const result = await this.query(identity, this.missionQuery(identity, true).in('statut', [...statuses])
      .order('debut_le', { ascending: status === 'active' }).order('id', { ascending: true }).range(offset, offset + 29), signal);
    if (result.error || !Array.isArray(result.data) || !Number.isSafeInteger(result.count) || result.count! < 0
      || result.data.length > 30 || offset + result.data.length > result.count! && result.data.length > 0
      || !result.data.length && offset < result.count!) unavailable();
    const rows = result.data.map(row => checkedMission(row, identity));
    if (new Set(rows.map(row => row.id)).size !== rows.length || rows.some(row => !(statuses as readonly string[]).includes(row.statut))) invalid();
    return { rows, offset, total: result.count!, nextOffset: offset + rows.length < result.count! ? offset + rows.length : null };
  }
  async read(context: PresenceContext, missionId: string, signal?: AbortSignal): Promise<PresenceDetails> {
    const identity = await this.identity(context, signal); const mission = await this.mission(identity, missionId, signal);
    const rows = await this.all(identity, offset => this.client.from('mission_creneaux').select(SEGMENT, { count: 'exact' })
      .eq('mission_id', missionId).order('debut', { ascending: true }).order('id', { ascending: true }).range(offset, offset + 99), signal);
    const segments = rows.map(row => checkedSegment(row, missionId));
    let contracts: PresenceContract[] | null = null; let contractReadFailed = false;
    let signedForPointage: boolean | undefined;
    if (identity.readContracts) {
      let raw: any[] | null = null;
      try {
        raw = await this.all(identity, offset => this.client.from('contrats_mission').select(CONTRACT, { count: 'exact' })
          .eq('mission_id', missionId).eq('etablissement_id', mission.etablissement_id)
          .eq('soignant_id', mission.soignant_assigne_id ?? '00000000-0000-0000-0000-000000000000')
          .order('cree_le', { ascending: false }).order('id', { ascending: true }).range(offset, offset + 99), signal);
      } catch (error) {
        // Contract availability cannot suppress departure from an independently verified open EFFECTIF.
        // Cancellation, identity changes and invalid-scope data still propagate.
        await this.current(identity, signal);
        if (!(error instanceof PresenceWorkflowError) || error.code !== 'UNAVAILABLE') throw error;
        contractReadFailed = true;
      }
      if (raw) contracts = raw.map(row => {
        if (row.mission_id !== missionId || row.etablissement_id !== mission.etablissement_id || row.soignant_id !== mission.soignant_assigne_id
          || typeof row.statut !== 'string' || row.cree_le !== null && !date(row.cree_le)) invalid();
        return { id: row.id, mission_id: row.mission_id, etablissement_id: row.etablissement_id,
          soignant_id: row.soignant_id, statut: row.statut, cree_le: row.cree_le };
      });
    }
    // POINTAGE_ONLY cannot read contracts. This bounded server predicate checks the
    // current parties and signature without returning any contractual content.
    if (!identity.readContracts && identity.displayCode) {
      const eligibility = await this.rpc(identity, 'fn_contrat_signe_pour_pointage', { p_mission_id: missionId }, signal);
      if (eligibility.error || typeof eligibility.data !== 'boolean') contractReadFailed = true;
      else signedForPointage = eligibility.data;
    }
    const result = await this.rpc(identity, 'fn_etat_pointage_mission', { p_mission_id: missionId }, signal);
    const state = result.data;
    if (result.error || !state || state.error || state.statut !== mission.statut || state.intitule !== mission.intitule
      || !['OUVERTURE', 'FERMETURE'].includes(state.prochain_type_scan) || !Number.isSafeInteger(state.nb_scans) || state.nb_scans < 0
      || typeof state.segment_ouvert !== 'boolean' || !Array.isArray(state.segments)
      // The existing RPC returns NULL for an assigned caregiver without an establishment.
      // Ownership was checked on the mission above; no other nullable or truthy value is accepted.
      || (context.kind === 'etablissement' ? state.est_etab !== true : state.est_etab !== false && state.est_etab !== null)) unavailable();
    const effective = segments.filter(segment => segment.type_creneau === 'EFFECTIF');
    if (state.segments.length !== effective.length || new Set(state.segments.map((row: any) => row?.id)).size !== effective.length
      || state.segments.some((row: any) => !effective.some(segment => row.id === segment.id && date(row.debut)
        && Date.parse(row.debut) === Date.parse(segment.debut)
        && (row.fin === null && segment.fin === null || date(row.fin) && date(segment.fin) && Date.parse(row.fin) === Date.parse(segment.fin))))
      || state.segment_ouvert !== effective.some(segment => !segment.fin)) unavailable();
    // A secret returned to the wrong party is never forwarded or logged.
    if (context.kind === 'soignant' && state.code_pointage_actif !== null) invalid();
    let observedServerAt: string | null = null;
    try {
      const observed = await this.options.clock.read({ userId: context.userId, authorization: identity.authorization, signal });
      if (date(observed)) observedServerAt = observed;
    } catch { /* Availability remains explicit when the clock cannot be verified. */ }
    await this.current(identity, signal);
    const evaluated = availability(mission, segments, contracts, observedServerAt, signedForPointage);
    if (contractReadFailed && evaluated.availability.reason === 'CONTRACT_PERMISSION') evaluated.availability.reason = 'CONTRACT_UNAVAILABLE';
    const establishmentCode = context.kind === 'etablissement' && identity.displayCode && evaluated.availability.canScan
      && typeof state.code_pointage_actif === 'string' && /^\d{6}$/.test(state.code_pointage_actif) ? state.code_pointage_actif : null;
    return { userId: context.userId, mission, segments, planned: evaluated.planning.creneauxPlanifies,
      planningComplete: evaluated.planning.complet, contractStatus: evaluated.contractStatus, availability: evaluated.availability,
      observedServerAt, nextAction: state.prochain_type_scan, numberOfScans: state.nb_scans, hasOpenSegment: state.segment_ouvert,
      permissions: { read: true, displayCode: identity.displayCode }, gpsConsent: identity.gpsConsent, establishmentCode };
  }
  async captureCode(context: PresenceContext, camera: PresenceQrPort, signal?: AbortSignal): Promise<QrCapture> {
    const identity = await this.identity(context, signal); if (context.kind !== 'soignant') invalid();
    const capture = await camera.scan(signal); await this.current(identity, signal);
    if (capture.kind !== 'code') return capture;
    try { return { kind: 'code', code: parsePresenceCode(capture.text) }; } catch { return { kind: 'invalid' }; }
  }
  async pending(context: PresenceContext) {
    this.assertContext(context); const receipt = await this.options.journal.read(context.userId); this.assertContext(context);
    if (receipt === null) this.cleanupUnverified.delete(context.userId);
    return receipt ? { attemptId: receipt.attemptId, gps: receipt.gps } : null;
  }
  private async exclusive<T>(context: PresenceContext, operation: () => Promise<T>): Promise<T> {
    this.assertContext(context);
    if (this.inFlight.has(context.userId)) throw new PresenceWorkflowError('BUSY', 'Un pointage est déjà en cours. Patientez.');
    this.inFlight.add(context.userId); try { return await operation(); } finally { this.inFlight.delete(context.userId); }
  }
  private clear(attempt: Attempt, expectedPhase?: PresenceAttemptReceipt['phase']): Promise<void> {
    return this.options.journal.clear(attempt.userId, attempt.id, expectedPhase);
  }
  private async proofs(identity: Identity, code: string, terminalId: string, signal?: AbortSignal): Promise<PresenceProof[]> {
    const rows = await this.all(identity, offset => this.client.from('scans_pointage').select(PROOF, { count: 'exact' })
      .eq('soignant_id', identity.context.userId).eq('code_saisi', code).eq('id_terminal', terminalId)
      .order('scanne_le', { ascending: true }).order('id', { ascending: true }).range(offset, offset + 99), signal);
    return rows.map(row => checkedProof(row, identity.context.userId));
  }
  private unresolved(attempt: Attempt): PresenceScanResult {
    return { kind: 'unconfirmed', attemptId: attempt.id, gps: attempt.gps, mission: null, proof: null, segment: null,
      message: 'Le résultat de ce scan n’est pas encore confirmé. Relisez le pointage avant toute nouvelle saisie : ne scannez pas de nouveau le code.' };
  }
  private async reconcileWith(identity: Identity, attempt: Attempt, signal?: AbortSignal): Promise<PresenceScanResult> {
    try {
      if (attempt.receipt.phase === 'prepared' || attempt.receipt.phase === 'not_sent') {
        // Phase CAS prevents a concurrent started barrier from being erased by this read-only recovery.
        await this.current(identity, signal);
        await this.clear(attempt, attempt.receipt.phase); await this.current(identity, signal);
        return { kind: 'rejected', attemptId: attempt.id, gps: attempt.gps, mission: null, proof: null, segment: null,
          message: 'Cette tentative a été interrompue avant l’envoi. Aucun pointage n’a été envoyé ; vous pouvez saisir un nouveau code.' };
      }
      if (attempt.receipt.rejectionCode) {
        await this.clear(attempt); await this.current(identity, signal);
        return { kind: 'rejected', attemptId: attempt.id, gps: attempt.gps, mission: null, proof: null, segment: null,
          message: rejectedScanMessage({ code: attempt.receipt.rejectionCode })! };
      }
      const proofs = await this.proofs(identity, attempt.code, attempt.terminalId, signal);
      const created = proofs.filter(proof => !attempt.baseline.has(proof.id));
      if (created.length !== 1) return this.unresolved(attempt);
      const proof = created[0];
      const mission = await this.mission(identity, proof.mission_id, signal);
      let request = this.client.from('mission_creneaux').select(SEGMENT).eq('mission_id', mission.id).eq('id', proof.creneau_effectif_id);
      if (signal) request = request.abortSignal(signal);
      const result = await this.query(identity, request.maybeSingle(), signal);
      if (result.error || !result.data) return this.unresolved(attempt);
      const segment = checkedSegment(result.data, mission.id);
      if (!proofMatchesSegment(proof, segment)) return this.unresolved(attempt);
      const reply = attempt.reply;
      if (reply && (reply.creneau_effectif_id !== proof.creneau_effectif_id || reply.type_scan_effectue !== proof.type_scan
        || reply.numero_scan !== proof.numero_scan || !date(reply.horodatage_effectif)
        || Date.parse(reply.horodatage_effectif) !== Date.parse(proof.scanne_le))) return this.unresolved(attempt);
      await this.current(identity, signal);
      let journalStatus: 'cleared' | 'unverified' = 'cleared';
      try { await this.clear(attempt); this.cleanupUnverified.delete(identity.context.userId); }
      catch { journalStatus = 'unverified'; this.cleanupUnverified.add(identity.context.userId); }
      await this.current(identity, signal);
      return { kind: 'confirmed', attemptId: attempt.id, gps: attempt.gps, journalStatus, mission, proof, segment,
        message: proof.type_scan === 'OUVERTURE' ? 'Arrivée enregistrée pour la mission affichée.' : 'Départ enregistré pour la mission affichée.' };
    } catch {
      await this.current(identity, signal); return this.unresolved(attempt);
    }
  }
  async reconcile(context: PresenceContext, attemptId: string, signal?: AbortSignal): Promise<PresenceScanResult> {
    context = { ...context };
    return this.exclusive(context, async () => {
      if (context.kind !== 'soignant') invalid();
      const receipt = await this.options.journal.read(context.userId); this.assertContext(context, signal);
      if (!receipt || receipt.attemptId !== attemptId) invalid();
      const attempt = attemptFrom(receipt);
      const identity = await this.identity(context, signal);
      return this.reconcileWith(identity, attempt, signal);
    });
  }
  async scan(context: PresenceContext, code: string, signal?: AbortSignal): Promise<PresenceScanResult> {
    context = { ...context }; code = parsePresenceCode(code);
    return this.exclusive(context, async () => {
      if (context.kind !== 'soignant') invalid();
      if (this.cleanupUnverified.has(context.userId)) throw new PresenceWorkflowError('RECONCILIATION_REQUIRED', 'Le pointage est enregistré. Relisez son suivi sécurisé avant de saisir un autre code.');
      if (await this.options.journal.read(context.userId)) throw new PresenceWorkflowError('RECONCILIATION_REQUIRED', 'Relisez le scan précédent avant de pointer à nouveau.');
      const identity = await this.identity(context, signal);
      if (!identity.test) throw new PresenceWorkflowError('TEST_NOT_ADMITTED', 'Le pointage du pilote est réservé aux comptes de TEST.');
      let gps: GpsObservation = { kind: 'not_requested' };
      if (identity.gpsConsent && this.options.gps) {
        try { gps = await this.options.gps.locate(signal); }
        catch { gps = { kind: 'unavailable' }; }
        await this.current(identity, signal);
        if (gps.kind === 'available' && !validGps(gps)) gps = { kind: 'unavailable' };
      } else if (identity.gpsConsent) gps = { kind: 'unavailable' };
      const baseline = await this.proofs(identity, code, this.options.terminalId, signal);
      const attemptId = this.options.newAttemptId(); if (!id(attemptId)) invalid();
      const receipt: PresenceAttemptReceipt = { version: 2, phase: 'prepared', attemptId, userId: context.userId, sessionEpoch: context.epoch,
        enteredCode: code, baselineProofIds: baseline.map(proof => proof.id), terminalId: this.options.terminalId,
        gps: gps.kind, rejectionCode: null };
      const attempt = attemptFrom(receipt);
      const metadata: Record<string, unknown> = { id_terminal: this.options.terminalId };
      if (gps.kind === 'available') Object.assign(metadata, { latitude: gps.latitude, longitude: gps.longitude, precision_gps_m: gps.accuracyMeters });
      await this.current(identity, signal); let invoked = false; let response: Reply;
      try {
        // The durable, re-read receipt precedes every possible network send.
        await this.options.journal.write(context.userId, receipt);
        await this.current(identity, signal);
        attempt.receipt = { ...receipt, phase: 'started' };
        await this.options.journal.write(context.userId, attempt.receipt);
        await this.current(identity, signal);
        let request = this.client.rpc('fn_scanner_code_pointage', { p_code: code, p_metadata: metadata })
          .setHeader('Authorization', identity.authorization).retry(false);
        if (signal) request = request.abortSignal(signal);
        invoked = true;
        response = await request;
      } catch (error) {
        if (!invoked) {
          // Never downgrade started after a possibly persisted write. Record a terminal known-not-sent
          // outcome before cleanup, so a failed delete can be recovered after a process restart.
          try {
            const saved = await this.options.journal.read(context.userId);
            if (saved?.attemptId === attempt.id) await this.options.journal.write(context.userId, { ...saved, phase: 'not_sent' });
          } catch { /* If storage cannot persist either outcome, retain the conservative existing phase. */ }
          // No RPC was invoked; cleanup is safe even after unmount/account change, and is always CAS.
          try { await this.clear(attempt); } catch { /* A retained receipt keeps subsequent writes blocked. */ }
          throw error;
        }
        response = { data: null, error: true };
      }
      const rejection = rejectedScanMessage(response.error);
      if (rejection) {
        attempt.receipt = { ...attempt.receipt, rejectionCode: response.error.code as PresenceAttemptReceipt['rejectionCode'] };
        try { await this.options.journal.write(context.userId, attempt.receipt); await this.clear(attempt); }
        catch { await this.current(identity, signal); return this.unresolved(attempt); }
        await this.current(identity, signal);
        return { kind: 'rejected', attemptId: attempt.id, gps: attempt.gps, mission: null, proof: null, segment: null, message: rejection };
      }
      if (!response.error && response.data && typeof response.data === 'object') {
        // Whitelist the correlation fields; never retain nouveau_code or nouveau_hmac.
        attempt.reply = { creneau_effectif_id: response.data.creneau_effectif_id, type_scan_effectue: response.data.type_scan_effectue,
          numero_scan: response.data.numero_scan, horodatage_effectif: response.data.horodatage_effectif };
      }
      await this.current(identity, signal);
      return this.reconcileWith(identity, attempt, signal);
    });
  }
}

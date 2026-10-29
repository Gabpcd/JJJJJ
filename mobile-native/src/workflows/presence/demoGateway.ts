import { availability, parsePresenceCode, rejectedScanMessage } from './business';
import { PresenceWorkflowError, type PresenceContext, type PresenceContract, type PresenceDetails, type PresenceGateway,
  type PresenceMission, type PresencePage, type PresenceProof, type PresenceQrPort, type PresenceScanResult,
  type PresenceSegment, type ConfirmedPresenceScan, type QrCapture } from './types';

const USERS = new Set(['demo-soignant', 'demo-inscription']);
const ETAB_USER = 'demo-etablissement-user'; const ETAB = 'demo-etablissement';
const START = Date.parse('2026-10-27T10:00:00.000Z');
type State = { missions: PresenceMission[]; segments: PresenceSegment[]; contracts: PresenceContract[];
  proofs: PresenceProof[]; codes: Map<string, string>; counter: number; clock: number;
  pending: ConfirmedPresenceScan | null; uncertaintyUsed: boolean };
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
function fixture(userId: string): State {
  const missions: PresenceMission[] = ['a', 'b'].map((letter, index) => ({
    id: `demo-presence-${letter}`, etablissement_id: ETAB, soignant_assigne_id: userId,
    intitule: `Mission ${letter.toUpperCase()} fictive`, service: index ? 'Service de démonstration B' : 'Service de démonstration A',
    statut: 'ASSIGNEE', debut_le: new Date(START).toISOString(), fin_le: new Date(START + 8 * 3_600_000).toISOString(), nb_creneaux: 1,
  }));
  return { missions, segments: missions.map(row => ({ id: `${row.id}-planned`, mission_id: row.id,
    debut: row.debut_le, fin: row.fin_le, est_pause: false, type_creneau: 'PREVISIONNEL' })),
  contracts: missions.map(row => ({ id: `${row.id}-contract`, mission_id: row.id, etablissement_id: ETAB,
    soignant_id: userId, statut: 'SIGNE_COMPLET', cree_le: new Date(START).toISOString() })),
  proofs: [], codes: new Map([['demo-presence-a', '123456'], ['demo-presence-b', '654321']]),
  counter: 0, clock: START, pending: null, uncertaintyUsed: false };
}

/** Synthetic memory only. Not constructed on STAGING and never used as a fallback for a real error. */
export class DemoPresenceGateway implements Omit<PresenceGateway, 'mode'> {
  readonly mode = 'demo' as const;
  private readonly worlds = new Map<string, State>(); private readonly inFlight = new Set<string>();
  constructor(private readonly options: { currentSession: () => PresenceContext | null;
    /** Opt-in only in a dedicated demo scenario: the scan is simulated then explicitly reconciled. */
    scenario?: 'uncertain-first-scan' }) {}
  private check(context: PresenceContext, signal?: AbortSignal): void {
    if (signal?.aborted) throw Object.assign(new Error('Simulation interrompue.'), { name: 'AbortError' });
    if ((context.kind !== 'soignant' && context.kind !== 'etablissement') || !Number.isSafeInteger(context.epoch) || context.epoch < 0)
      throw new PresenceWorkflowError('INVALID_SCOPE', 'Le contexte de démonstration est invalide.');
    const current = this.options.currentSession();
    if (!current || current.userId !== context.userId || current.epoch !== context.epoch || current.kind !== context.kind
      || context.kind === 'etablissement' && (current.kind !== 'etablissement' || current.etablissementId !== context.etablissementId))
      throw new PresenceWorkflowError('SESSION_CHANGED', 'La session de démonstration a changé.');
    if (context.kind === 'soignant' ? !USERS.has(context.userId) : context.userId !== ETAB_USER || context.etablissementId !== ETAB)
      throw new PresenceWorkflowError('INVALID_SCOPE', 'Ce compte n’appartient pas à la démonstration.');
  }
  private state(context: PresenceContext): State {
    const owner = context.kind === 'soignant' ? context.userId : 'demo-soignant';
    if (!this.worlds.has(owner)) this.worlds.set(owner, fixture(owner));
    return this.worlds.get(owner)!;
  }
  async list(context: PresenceContext, options: { status?: 'active' | 'history'; offset?: number } = {}, signal?: AbortSignal): Promise<PresencePage> {
    this.check(context, signal); const offset = options.offset ?? 0;
    if (!Number.isSafeInteger(offset) || offset < 0) throw new PresenceWorkflowError('INVALID_INPUT', 'Page invalide.');
    const rows = options.status === 'history' ? [] : this.state(context).missions;
    return { rows: copy(rows.slice(offset, offset + 30)), offset, total: rows.length, nextOffset: null };
  }
  async read(context: PresenceContext, missionId: string, signal?: AbortSignal): Promise<PresenceDetails> {
    this.check(context, signal); const state = this.state(context); const mission = state.missions.find(row => row.id === missionId);
    if (!mission) throw new PresenceWorkflowError('INVALID_SCOPE', 'Cette mission ne fait pas partie de la démonstration.');
    const segments = state.segments.filter(row => row.mission_id === missionId);
    const observedServerAt = new Date(state.clock).toISOString();
    const evaluated = availability(mission, segments, state.contracts.filter(row => row.mission_id === missionId), observedServerAt);
    const hasOpenSegment = segments.some(row => row.type_creneau === 'EFFECTIF' && !row.fin);
    return copy({ userId: context.userId, mission, segments, planned: evaluated.planning.creneauxPlanifies,
      planningComplete: evaluated.planning.complet, contractStatus: evaluated.contractStatus, availability: evaluated.availability,
      observedServerAt, nextAction: hasOpenSegment ? 'FERMETURE' : 'OUVERTURE',
      numberOfScans: state.proofs.filter(row => row.mission_id === missionId).length, hasOpenSegment,
      permissions: { read: true, displayCode: context.kind === 'etablissement' }, gpsConsent: false,
      establishmentCode: context.kind === 'etablissement' && evaluated.availability.canScan ? state.codes.get(missionId) ?? null : null });
  }
  async captureCode(context: PresenceContext, _camera: PresenceQrPort, signal?: AbortSignal): Promise<QrCapture> {
    this.check(context, signal); return { kind: 'unavailable' };
  }
  async pending(context: PresenceContext) {
    this.check(context); if (context.kind !== 'soignant') return null;
    const receipt = this.state(context).pending; return receipt ? { attemptId: receipt.attemptId, gps: receipt.gps } : null;
  }
  async reconcile(context: PresenceContext, attemptId: string, signal?: AbortSignal): Promise<PresenceScanResult> {
    this.check(context, signal); const state = this.state(context);
    if (context.kind !== 'soignant' || !state.pending || state.pending.attemptId !== attemptId)
      throw new PresenceWorkflowError('INVALID_SCOPE', 'Aucune simulation à réconcilier pour ce compte.');
    const result = copy(state.pending);
    const proof = state.proofs.find(row => row.id === result.proof.id);
    const segment = state.segments.find(row => row.id === result.segment.id);
    if (!proof || !segment || proof.soignant_id !== context.userId) throw new PresenceWorkflowError('UNAVAILABLE', 'La simulation ne peut pas être relue.');
    this.check(context, signal); state.pending = null; return result;
  }
  async scan(context: PresenceContext, value: string, signal?: AbortSignal): Promise<PresenceScanResult> {
    this.check(context, signal); if (context.kind !== 'soignant') throw new PresenceWorkflowError('INVALID_SCOPE', 'Ce scénario utilise le compte soignant fictif.');
    if (this.inFlight.has(context.userId)) throw new PresenceWorkflowError('BUSY', 'Une simulation est déjà en cours.');
    this.inFlight.add(context.userId);
    try {
      const code = parsePresenceCode(value); const state = this.state(context);
      if (state.pending) throw new PresenceWorkflowError('RECONCILIATION_REQUIRED', 'Relisez la simulation précédente.');
      await Promise.resolve(); this.check(context, signal);
      const missionId = [...state.codes].find(([, active]) => active === code)?.[0];
      const attemptId = `demo-presence-attempt-${context.userId}-${state.counter + 1}`;
      if (this.options.scenario === 'uncertain-first-scan' && code === '000000') {
        return { kind: 'rejected', attemptId, gps: 'unavailable', mission: null, proof: null, segment: null,
          message: rejectedScanMessage({ code: 'PGRST301' })! };
      }
      if (!missionId) return { kind: 'rejected', attemptId, gps: 'unavailable', mission: null, proof: null, segment: null,
        message: 'Ce code fictif est invalide ou a déjà été renouvelé. Consultez le code de l’établissement de démonstration.' };
      const mission = state.missions.find(row => row.id === missionId)!;
      const open = state.segments.find(row => row.mission_id === missionId && row.type_creneau === 'EFFECTIF' && !row.fin);
      const kind = open ? 'FERMETURE' as const : 'OUVERTURE' as const;
      const now = new Date(state.clock).toISOString(); state.counter += 1;
      const segment = open ?? { id: `demo-presence-effective-${state.counter}`, mission_id: missionId, debut: now,
        fin: null, est_pause: false, type_creneau: 'EFFECTIF' };
      if (open) open.fin = now; else state.segments.push(segment);
      const proof: PresenceProof = { id: `demo-presence-proof-${state.counter}`, mission_id: missionId, soignant_id: context.userId,
        numero_scan: state.proofs.filter(row => row.mission_id === missionId).length + 1,
        type_scan: kind, scanne_le: now, horodatage_arrondi: now, creneau_effectif_id: segment.id,
        validation_etab_requise: false, valide_par_etab: false };
      state.proofs.push(proof); mission.statut = 'EN_COURS';
      state.codes.set(missionId, String(100000 + state.counter)); state.clock += 3 * 60_000;
      const confirmed: ConfirmedPresenceScan = copy({ kind: 'confirmed', attemptId, gps: 'unavailable', journalStatus: 'cleared',
        mission, proof, segment, message: 'Simulation fictive enregistrée en mémoire. Aucun pointage réel n’a été envoyé.' });
      state.pending = confirmed;
      await Promise.resolve(); this.check(context, signal);
      if (this.options.scenario === 'uncertain-first-scan' && !state.uncertaintyUsed) {
        state.uncertaintyUsed = true;
        return { kind: 'unconfirmed', attemptId, gps: 'unavailable', mission: null, proof: null, segment: null,
          message: 'Démonstration d’une réponse perdue. Relisez la simulation sans saisir de nouveau code.' };
      }
      return await this.reconcile(context, attemptId, signal);
    } finally { this.inFlight.delete(context.userId); }
  }
}

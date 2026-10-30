import type { DefiniteTransactionRollbackCode } from '../rpcOutcome';

export type PresenceContext = { kind: 'soignant'; userId: string; epoch: number }
  | { kind: 'etablissement'; userId: string; epoch: number; etablissementId: string };
export type ScanKind = 'OUVERTURE' | 'FERMETURE';
export interface PresenceMission {
  id: string; etablissement_id: string; soignant_assigne_id: string | null;
  intitule: string; service: string | null; statut: string;
  debut_le: string; fin_le: string; nb_creneaux: number | null;
}
export interface PresenceSegment {
  id: string; mission_id: string; debut: string; fin: string | null;
  est_pause: boolean; type_creneau: string;
}
export interface PresenceContract {
  id: string; mission_id: string; etablissement_id: string; soignant_id: string;
  statut: string; cree_le: string | null;
}
/** Safe projection: no raw code, GPS coordinates, terminal ID, IP or next secret. */
export interface PresenceProof {
  id: string; mission_id: string; soignant_id: string; numero_scan: number;
  type_scan: ScanKind; scanne_le: string; horodatage_arrondi: string;
  creneau_effectif_id: string; validation_etab_requise: boolean; valide_par_etab: boolean;
}
export interface PresenceAvailability {
  canScan: boolean; action: ScanKind | null;
  reason: 'TERMINAL' | 'PLANNING_INCOMPLETE' | 'CONTRACT_PERMISSION' | 'CONTRACT_UNAVAILABLE' | 'SERVER_TIME_UNAVAILABLE'
    | 'CONTRAT' | 'HORS_CRENEAU' | 'AUCUN_CRENEAU' | null;
}
export interface PresenceDetails {
  userId: string; mission: PresenceMission; segments: PresenceSegment[];
  planningComplete: boolean; planned: Array<Omit<PresenceSegment, 'mission_id' | 'id'> & { id?: string }>;
  contractStatus: string | null; availability: PresenceAvailability;
  /** Authenticated HTTP server time for advisory display, not the database scan timestamp. */
  observedServerAt: string | null;
  nextAction: ScanKind; numberOfScans: number; hasOpenSegment: boolean;
  permissions: { read: true; displayCode: boolean }; gpsConsent: boolean;
  /** Only an authorized establishment gets the code, and only while the existing UI rules allow it. */
  establishmentCode: string | null;
}
export interface PresencePage { rows: PresenceMission[]; offset: number; nextOffset: number | null; total: number }
export type GpsObservation = { kind: 'available'; latitude: number; longitude: number; accuracyMeters: number }
  | { kind: 'denied' | 'unavailable' | 'not_requested' };
export interface PresenceGpsPort { locate(signal?: AbortSignal): Promise<GpsObservation> }
export type QrCapture = { kind: 'code'; code: string } | { kind: 'cancelled' | 'denied' | 'unavailable' | 'invalid' };
export interface PresenceQrPort { scan(signal?: AbortSignal): Promise<{ kind: 'code'; text: string } | { kind: 'cancelled' | 'denied' | 'unavailable' }> }
export interface PresenceClockPort {
  read(input: { userId: string; authorization: string; signal?: AbortSignal }): Promise<string>;
}
export interface PendingPresenceScan { attemptId: string; gps: GpsObservation['kind'] }
export type PresenceAttemptPhase = 'prepared' | 'started' | 'not_sent';
/** Secure journal only. This is never a screen model and contains no JWT, next code or GPS coordinate. */
export interface PresenceAttemptReceipt {
  version: 2; phase: PresenceAttemptPhase; userId: string; attemptId: string; sessionEpoch: number; terminalId: string;
  /** The code already entered by this user is needed for the existing SQL readback filter. */
  enteredCode: string; baselineProofIds: string[]; gps: GpsObservation['kind'];
  rejectionCode: 'P0002' | '42501' | '23514' | 'PGRST202' | 'PGRST300' | 'PGRST301' | 'PGRST302' | 'PGRST303' | DefiniteTransactionRollbackCode | null;
}
export interface PresenceAttemptJournal {
  read(userId: string): Promise<PresenceAttemptReceipt | null>;
  /** Persists and re-reads before resolving. Refuses to replace an unresolved, different attempt. */
  write(userId: string, receipt: PresenceAttemptReceipt): Promise<void>;
  /** Serialized compare-and-clear; recovery of a non-sent attempt also compares its phase. */
  clear(userId: string, expectedAttemptId: string, expectedPhase?: PresenceAttemptPhase): Promise<void>;
}
export interface ConfirmedPresenceScan {
  kind: 'confirmed'; attemptId: string; gps: GpsObservation['kind'];
  /** Business success is already proven; this only describes the local recovery receipt cleanup. */
  journalStatus: 'cleared' | 'unverified';
  /** This is the mission actually selected by the code and re-read, not an initiating screen's mission. */
  mission: PresenceMission; proof: PresenceProof; segment: PresenceSegment; message: string;
}
export type PresenceScanResult = ConfirmedPresenceScan | {
  kind: 'rejected' | 'unconfirmed'; attemptId: string; gps: GpsObservation['kind'];
  mission: null; proof: null; segment: null; message: string;
};
export interface PresenceGateway {
  readonly mode: 'supabase';
  list(context: PresenceContext, options?: { status?: 'active' | 'history'; offset?: number }, signal?: AbortSignal): Promise<PresencePage>;
  read(context: PresenceContext, missionId: string, signal?: AbortSignal): Promise<PresenceDetails>;
  captureCode(context: PresenceContext, camera: PresenceQrPort, signal?: AbortSignal): Promise<QrCapture>;
  /** Account operation: the server resolves the mission from this code. No missionId argument by design. */
  scan(context: PresenceContext, code: string, signal?: AbortSignal): Promise<PresenceScanResult>;
  pending(context: PresenceContext): Promise<PendingPresenceScan | null>;
  /** Read-only. Never resends the RPC and never silently discards an ambiguous attempt. */
  reconcile(context: PresenceContext, attemptId: string, signal?: AbortSignal): Promise<PresenceScanResult>;
}
export class PresenceWorkflowError extends Error {
  constructor(readonly code: 'INVALID_SCOPE' | 'SESSION_CHANGED' | 'INVALID_INPUT' | 'UNAVAILABLE' | 'BUSY'
    | 'RECONCILIATION_REQUIRED' | 'TEST_NOT_ADMITTED' | 'JOURNAL_UNAVAILABLE', message: string) {
    super(message); this.name = 'PresenceWorkflowError';
  }
}

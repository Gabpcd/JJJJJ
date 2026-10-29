import { analyserCompletudePlanningMission } from '../../../../src/lib/completude-planning-mission';
import { choisirContratPointage, evaluerDisponibilitePointage } from '../../../../src/lib/disponibilite-pointage';
import { PresenceWorkflowError, type GpsObservation, type PresenceAvailability, type PresenceContract,
  type PresenceMission, type PresenceProof, type PresenceSegment } from './types';

export const PRESENCE_STAGING_ORIGIN = 'https://mejpriaetwgtcstbgfid.supabase.co';
export const PRESENCE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ACTIVE_PRESENCE_STATUSES = ['ASSIGNEE', 'EN_COURS'] as const;
export const HISTORY_PRESENCE_STATUSES = ['TERMINEE', 'LITIGE', 'ABSENCE'] as const;
export function parsePresenceCode(value: string): string {
  if (typeof value !== 'string' || !/^\d{6}$/.test(value.trim())) {
    throw new PresenceWorkflowError('INVALID_INPUT', 'Saisissez les six chiffres du code affiché par l’établissement.');
  }
  return value.trim();
}
export function validGps(observation: GpsObservation): boolean {
  return observation.kind === 'available' && [observation.latitude, observation.longitude, observation.accuracyMeters].every(Number.isFinite)
    && Math.abs(observation.latitude) <= 90 && Math.abs(observation.longitude) <= 180 && observation.accuracyMeters >= 0;
}
export function availability(mission: PresenceMission, segments: PresenceSegment[], contracts: PresenceContract[] | null,
  serverAt: string | null, signedForPointage?: boolean): { availability: PresenceAvailability; planning: ReturnType<typeof analyserCompletudePlanningMission>; contractStatus: string | null } {
  const planning = analyserCompletudePlanningMission(mission, segments);
  const contractStatus = contracts ? choisirContratPointage(contracts)?.statut ?? null : signedForPointage === true ? 'SIGNE_COMPLET' : null;
  const blocked = (reason: PresenceAvailability['reason']) => ({ availability: { canScan: false, action: null, reason }, planning, contractStatus });
  if (!(ACTIVE_PRESENCE_STATUSES as readonly string[]).includes(mission.statut)) return blocked('TERMINAL');
  const effective = segments.filter(segment => segment.type_creneau === 'EFFECTIF');
  const open = effective.some(segment => !segment.est_pause && !segment.fin);
  if (!open && !planning.complet) return blocked('PLANNING_INCOMPLETE');
  if (!open && contracts === null && signedForPointage === undefined) return blocked('CONTRACT_PERMISSION');
  if (!open && (!serverAt || !Number.isFinite(Date.parse(serverAt)))) return blocked('SERVER_TIME_UNAVAILABLE');
  const evaluated = evaluerDisponibilitePointage({ creneaux: [...planning.creneauxPlanifies, ...effective],
    contratStatut: contractStatus, maintenant: new Date(serverAt ?? 0) });
  return { availability: { canScan: evaluated.peutPointer, action: evaluated.action, reason: evaluated.motif }, planning, contractStatus };
}
export function proofMatchesSegment(proof: PresenceProof, segment: PresenceSegment): boolean {
  return segment.id === proof.creneau_effectif_id && segment.mission_id === proof.mission_id
    && segment.type_creneau === 'EFFECTIF' && !segment.est_pause
    && Date.parse(proof.scanne_le) === Date.parse(proof.type_scan === 'OUVERTURE' ? segment.debut : segment.fin ?? '')
    && (segment.fin === null || Date.parse(segment.fin) >= Date.parse(segment.debut));
}
/** PostgREST rejects these requests before executing the RPC. Do not infer this from HTTP status alone.
 * https://docs.postgrest.org/en/stable/references/errors.html#postgrest-error-codes */
export function isPresencePreExecutionRefusal(code: unknown): boolean {
  return typeof code === 'string' && ['PGRST202', 'PGRST300', 'PGRST301', 'PGRST302', 'PGRST303'].includes(code);
}
/** Recognized SQL failures and explicit pre-execution refusals are definitive; transport failures remain ambiguous. */
export function rejectedScanMessage(error: unknown): string | null {
  const code = error && typeof error === 'object' ? (error as { code?: unknown }).code : null;
  if (code === 'PGRST202') return 'Le service de pointage est momentanément indisponible. Aucun pointage n’a été enregistré par cette demande.';
  if (isPresencePreExecutionRefusal(code)) return 'La connexion a été refusée avant l’enregistrement du pointage. Reconnectez-vous avant de réessayer.';
  if (code === 'P0002') return 'Ce code est invalide ou a déjà été renouvelé. Demandez le code actuellement affiché par l’établissement.';
  if (code === '42501') return 'Le pointage de cette mission n’est pas autorisé pour votre compte.';
  if (code === '23514') return 'Le serveur a refusé ce pointage : vérifiez le contrat, le créneau et l’état du dernier scan avant de continuer.';
  return null;
}

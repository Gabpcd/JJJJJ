import type { Mission, MissionReadContext } from '../../data/types';

export type MyMissionsTab = 'candidatures' | 'actives' | 'passees';
export type ContractChoice = 'SALARIE' | 'LIBERAL';
export interface MyMission {
  id: string; title: string; startsAt: string; endsAt: string; status: string;
  establishment: string; city: string | null; contract: string | null;
  applicationId: string | null; applicationStatus: string | null;
}
export interface MyMissionsPage { rows: MyMission[]; page: number; hasMore: boolean }
export interface ApplicationRecord { id: string; statut: string; type_contrat_choisi: string | null }
export interface AcceptanceEmailReceipt {
  recipient: 'soignant' | 'etablissement';
  state: 'sent' | 'skipped' | 'pending' | 'failed';
  reason?: string;
}
export interface ApplicationSnapshot {
  userId: string;
  mission: Mission;
  attribution: string | null;
  assignedTo: string | null;
  appliedContract: string | null;
  assignmentRevision?: string | null;
  application: ApplicationRecord | null;
  canApply: boolean;
  missingProfile: string[];
  documentsComplete: boolean;
  caregiver: { firstName: string; lastName: string; profession: string };
  acceptanceEmails?: AcceptanceEmailReceipt[];
  /** True only for persisted, complete slots; a legacy date fallback cannot authorize an action. */
  exactPersistedPlanning: boolean;
}
export interface ApplyInput { message: string; contractChoice?: ContractChoice }
export interface ContractOption { value: ContractChoice; label: string }
export type ApplyResult =
  | { kind: 'confirmed'; snapshot: ApplicationSnapshot; documentsToComplete: boolean }
  | { kind: 'choice'; snapshot: ApplicationSnapshot; options: ContractOption[] }
  | { kind: 'rejected'; snapshot: ApplicationSnapshot | null; message: string }
  | { kind: 'unconfirmed'; snapshot: ApplicationSnapshot | null; message: string };

export interface MissionWorkflowGateway {
  readonly mode: 'demo' | 'supabase';
  listMine(context: MissionReadContext, tab: MyMissionsTab, page?: number, signal?: AbortSignal): Promise<MyMissionsPage>;
  readApplication(context: MissionReadContext, missionId: string, signal?: AbortSignal): Promise<ApplicationSnapshot | null>;
  apply(context: MissionReadContext, snapshot: ApplicationSnapshot, input: ApplyInput, signal?: AbortSignal): Promise<ApplyResult>;
  retryAcceptanceEmails(context: MissionReadContext, missionId: string, signal?: AbortSignal): Promise<AcceptanceEmailReceipt[]>;
}

export const hasActiveAssignment = (snapshot: ApplicationSnapshot) => snapshot.assignedTo === snapshot.userId
  && ['ASSIGNEE', 'EN_COURS'].includes(snapshot.mission.statut);
export const isTerminalMission = (snapshot: ApplicationSnapshot) =>
  ['TERMINEE', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT', 'ABSENCE', 'LITIGE', 'EXPIREE'].includes(snapshot.mission.statut);
export const applicationDisplayStatus = (snapshot: ApplicationSnapshot) =>
  snapshot.mission.statut !== 'OUVERTE' ? snapshot.mission.statut : snapshot.application?.statut ?? snapshot.mission.statut;

export function alreadyApplied(snapshot: ApplicationSnapshot): boolean {
  return snapshot.assignedTo === snapshot.userId || Boolean(snapshot.application &&
    ['EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'ACCEPTEE', 'PROPOSEE'].includes(snapshot.application.statut));
}

export function applicationAction(snapshot: ApplicationSnapshot): 'POSTULER' | 'ACCEPTER' | null {
  if (alreadyApplied(snapshot) || snapshot.mission.statut !== 'OUVERTE' || snapshot.assignedTo
    || !snapshot.canApply || !snapshot.exactPersistedPlanning) return null;
  // Do not turn an unknown backend mode into immediate assignment.
  return snapshot.attribution === 'CANDIDATURE' ? 'POSTULER'
    : snapshot.attribution === 'PREMIER_ARRIVE' ? 'ACCEPTER' : null;
}

export function workflowContextKey(context: MissionReadContext): string {
  return JSON.stringify([context.userId, context.email,
    Object.entries(context.profile).sort(([a], [b]) => a.localeCompare(b))]);
}

export function statusLabel(status: string): string {
  const labels: Record<string, string> = {
    EN_ATTENTE: 'Candidature envoyée', EN_ATTENTE_VALIDATION_ETAB: 'En attente de l’établissement',
    ACCEPTEE: 'Candidature acceptée', REFUSEE: 'Candidature refusée', RETIREE: 'Candidature retirée',
    ANNULEE: 'Candidature annulée', PROPOSEE: 'Proposition de l’établissement', OUVERTE: 'Disponible',
    ASSIGNEE: 'Mission attribuée', EN_COURS: 'Mission en cours', TERMINEE: 'Mission terminée',
    ANNULEE_PAR_SOIGNANT: 'Annulée par le soignant', ANNULEE_PAR_ETABLISSEMENT: 'Annulée par l’établissement',
    ABSENCE: 'Absence signalée', LITIGE: 'Mission en litige', EXPIREE: 'Mission expirée',
  };
  return labels[status] ?? 'État à consulter dans Jolene';
}

import type { Mission } from '../data/types';

export const ESTABLISHMENT_PERMISSION_KEYS = [
  'gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement',
  'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture',
] as const;
export type EstablishmentPermissions = Record<typeof ESTABLISHMENT_PERMISSION_KEYS[number], boolean>;

/** Resolved by the authenticated account adapter, never inferred from userId. */
export interface EstablishmentContext {
  userId: string;
  email: string | null;
  etablissementId: string;
  permissions: EstablishmentPermissions;
  membershipRole?: string;
}

export interface EstablishmentProfile {
  id: string;
  nom: string;
  type: string | null;
  siret: string | null;
  finess: string | null;
  adresse_rue: string | null;
  adresse_ville: string | null;
  adresse_code_postal: string | null;
  email_contact: string | null;
  telephone_contact: string | null;
  statut_verification: string | null;
  contrat_service_signe: boolean | null;
  peut_publier_missions: boolean | null;
}

export interface EstablishmentMissionFilters { status?: string; search?: string; offset?: number; }
export interface EstablishmentMissionPage {
  missions: Mission[];
  /** Backend cursor before fixture filtering; never advertised as a global count. */
  nextOffset: number | null;
}
export interface EstablishmentReadGateway {
  readonly mode: 'demo' | 'supabase';
  getProfile(context: EstablishmentContext, signal?: AbortSignal): Promise<EstablishmentProfile | null>;
  listMissions(context: EstablishmentContext, filters?: EstablishmentMissionFilters, signal?: AbortSignal): Promise<EstablishmentMissionPage>;
  getMission(id: string, context: EstablishmentContext, signal?: AbortSignal): Promise<Mission | null>;
}

export const MISSION_STATUS_OPTIONS = [
  { value: '', label: 'Toutes' }, { value: 'OUVERTE', label: 'Ouvertes' },
  { value: 'ASSIGNEE', label: 'Assignées' }, { value: 'EN_COURS', label: 'En cours' },
  { value: 'TERMINEE', label: 'Terminées' }, { value: 'EXPIREE', label: 'Expirées' },
  { value: 'ANNULEE_PAR_ETABLISSEMENT', label: 'Annulées par l’établissement' },
  { value: 'ANNULEE_PAR_SOIGNANT', label: 'Annulées par le soignant' },
  { value: 'ABSENCE', label: 'Absences' }, { value: 'LITIGE', label: 'Litiges' },
] as const;

export function establishmentResourceKey(context: EstablishmentContext, resource: unknown, mode: string): string {
  return JSON.stringify([mode, context.userId, context.email, context.etablissementId, context.membershipRole,
    ESTABLISHMENT_PERMISSION_KEYS.map(key => context.permissions[key]), resource]);
}

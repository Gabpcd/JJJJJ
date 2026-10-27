export interface RoleResult {
  role: string;
  etablissement_id: string | null;
}

export interface SoignantProfile {
  id: string;
  profession: string;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number | null;
  tous_documents_valides: boolean;
  type_contrat: string | null;
  types_contrat_acceptes: string | null;
  type_exercice: string | null;
  taux_horaire_minimum: number | null;
}

export interface EtablissementSummary {
  id: string;
  nom: string;
  adresse_ville: string | null;
  adresse_code_postal: string | null;
  adresse_lat: number | null;
  adresse_lng: number | null;
  type: string | null;
  logo_url?: string | null;
}

export interface MissionSlot {
  id?: string;
  mission_id?: string;
  debut: string;
  fin: string | null;
  est_pause: boolean;
  type_creneau: string;
}

/** Amounts and the RIST cap are server values, never recomputed here. */
export interface MissionRecord {
  id: string;
  intitule: string;
  description: string | null;
  service: string | null;
  profession_requise: string;
  specialite_medicale_requise: string | null;
  accepte_non_specialises: boolean | null;
  debut_le: string;
  fin_le: string;
  duree_heures: number | null;
  nb_creneaux: number | null;
  taux_horaire_base: number | null;
  taux_rist_plafonne: number | null;
  rist_plafond_applique: boolean | null;
  total_brut: number | null;
  net_a_payer: number | null;
  est_urgente: boolean;
  niveau_urgence: number | null;
  statut: string;
  etablissement_id: string;
  type_contrat_recherche: string | null;
  boostee_le: string | null;
  mode_remuneration: string | null;
  retrocession_pct: number | null;
}

export interface Mission extends MissionRecord {
  etablissements: EtablissementSummary | null;
  distance_km: number | null;
  creneaux_planifies: MissionSlot[];
  planning_exact: boolean;
  erreur_planning: boolean;
}

export interface MissionReadContext {
  userId: string;
  email: string | null;
  profile: SoignantProfile;
}

export interface MissionFilters {
  ville?: string;
  rayonKm?: number;
  tauxMin?: number;
  profession?: string;
  urgentesOnly?: boolean;
  typeContrat?: 'TOUS' | 'CDD' | 'LIBERAL';
  horaire?: 'TOUS' | 'JOUR' | 'NUIT' | 'WEEKEND';
  etablissementId?: string;
}

export interface MissionGateway {
  readonly mode: 'demo' | 'supabase';
  getRole(signal?: AbortSignal): Promise<RoleResult>;
  getProfile(userId: string, signal?: AbortSignal): Promise<SoignantProfile | null>;
  listMissions(context: MissionReadContext, filters?: MissionFilters, signal?: AbortSignal): Promise<Mission[]>;
  getMission(id: string, context: MissionReadContext, signal?: AbortSignal): Promise<Mission | null>;
}

export type MobileAccessValidation = { allowed: true } | {
  allowed: false;
  code: 'SIGN_IN_REQUIRED' | 'EMAIL_UNCONFIRMED' | 'UNSUPPORTED_ROLE';
  message: string;
};

/** Navigation admission only; the authenticated backend remains authoritative. */
export function validateMobileAccess(
  user: { id: string; email_confirmed_at?: string | null } | null,
  role: string | null,
): MobileAccessValidation {
  if (!user) return { allowed: false, code: 'SIGN_IN_REQUIRED', message: 'Connectez-vous pour consulter les missions.' };
  if (!user.email_confirmed_at) return { allowed: false, code: 'EMAIL_UNCONFIRMED', message: 'Confirmez votre adresse email avant de continuer.' };
  if (role !== 'SOIGNANT') return { allowed: false, code: 'UNSUPPORTED_ROLE', message: 'Ce premier parcours natif est réservé aux comptes soignants déjà constitués.' };
  return { allowed: true };
}

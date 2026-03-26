/**
 * Typed RPC response interfaces for Supabase functions
 * that are not yet in the auto-generated types.ts.
 *
 * Usage:
 *   const { data } = await supabase.rpc('fn_get_my_role') as { data: RpcGetMyRole | null; error: any };
 *   // or use the typedRpc helper
 */

// ─── Auth / Role ────────────────────────────────────────
export interface RpcGetMyRole {
  role: string;
  etablissement_id: string | null;
}

export interface RpcAuditConnexion {
  success: boolean;
}

// ─── Soignant profile ───────────────────────────────────
export interface RpcModifierMonProfil {
  success: boolean;
  error?: string;
}

export interface RpcNoteMoyenne {
  moyenne: number | null;
  total: number;
}

export interface RpcBadgeStats {
  missionsTerminees: number;
  scoreFiabilite: number;
  heuresCumulees: number;
  annulations: number;
  missionsNuit: number;
  missionsWeekend: number;
  maxMissionsMemeEtab: number;
  retards: number;
  totalMissions: number;
}

// ─── Missions ───────────────────────────────────────────
export interface RpcSuccessOrError {
  success: boolean;
  error?: string;
}

export interface RpcValiderPresence extends RpcSuccessOrError {}
export interface RpcContesterPresence extends RpcSuccessOrError {}
export interface RpcValiderPresencesLot extends RpcSuccessOrError {
  nb_validees?: number;
}

export interface RpcPointerArrivee extends RpcSuccessOrError {
  presence_id?: string;
}
export interface RpcPointerDepart extends RpcSuccessOrError {}

export interface RpcPostulerMission extends RpcSuccessOrError {
  candidature_id?: string;
}

export interface RpcAnnulerMission extends RpcSuccessOrError {}

// ─── Litiges ────────────────────────────────────────────
export interface RpcOuvrirLitige extends RpcSuccessOrError {
  litige_id?: string;
}

export interface RpcProposerClotureLitige extends RpcSuccessOrError {
  en_attente_accord?: boolean;
}

// ─── Paiements / Facturation ────────────────────────────
export interface RpcDeclarerVirement extends RpcSuccessOrError {}
export interface RpcGenererFacture extends RpcSuccessOrError {
  facture_id?: string;
}
export interface RpcModePaiementMission {
  mode: string;
  stripe_account_id?: string | null;
  [key: string]: unknown;
}

// ─── GPS / Pool ─────────────────────────────────────────
export interface RpcConsentirGps extends RpcSuccessOrError {}
export interface RpcTogglePoolUrgence extends RpcSuccessOrError {}

// ─── Exclusions ─────────────────────────────────────────
export interface RpcExclureUtilisateur extends RpcSuccessOrError {}

// ─── Parrainage ─────────────────────────────────────────
export interface RpcAppliquerParrainage extends RpcSuccessOrError {}

// ─── RGPD ───────────────────────────────────────────────
export interface RpcRgpdExporter extends RpcSuccessOrError {
  url?: string;
}
export interface RpcSupprimerCompte extends RpcSuccessOrError {}

// ─── Urgence ────────────────────────────────────────────
export interface RpcSoignantsUrgence {
  soignant_id: string;
  id?: string;
  prenom: string;
  nom: string;
  profession: string;
  score_fiabilite: number;
  distance_km: number;
}

// ─── DPAE ───────────────────────────────────────────────
export interface RpcConfirmerDpae extends RpcSuccessOrError {}

// ─── Contrats ───────────────────────────────────────────
export interface RpcSignerContrat extends RpcSuccessOrError {}

// ─── Liberal ────────────────────────────────────────────
export interface RpcActiverLiberal extends RpcSuccessOrError {}

// ─── Reclamation ────────────────────────────────────────
export interface RpcSoumettreReclamation extends RpcSuccessOrError {
  reclamation_id?: string;
}

// ─── Admin ──────────────────────────────────────────────
export interface RpcTraiterReclamation extends RpcSuccessOrError {}
export interface RpcResoudreLitige extends RpcSuccessOrError {}
export interface RpcAdminIncoherencesIdentite {
  soignant_id: string;
  prenom: string;
  nom: string;
  prenom_ia: string | null;
  nom_ia: string | null;
  coherence: boolean;
}

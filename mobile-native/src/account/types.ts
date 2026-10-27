import type { MissionReadContext } from '../data/types';

export type NativeAccountType = 'SOIGNANT' | 'ETABLISSEMENT';
export interface NativeRegistrationIntent {
  type: NativeAccountType;
  profession: string;
  nom: string;
  cgu: boolean;
  cgv: boolean;
}
export interface NativeRegistrationDraft {
  user_id: string;
  type_compte: NativeAccountType;
  donnees: Record<string, unknown>;
  modifie_le: string;
}
export interface NativeEstablishmentPermissions {
  gerer_equipe: boolean; supprimer_compte: boolean; profil_etab: boolean;
  paiement: boolean; lecture_paiement: boolean; missions: boolean;
  candidatures: boolean; contrats: boolean; pointage: boolean; rh: boolean; lecture: boolean;
}
export interface NativeEstablishmentContext {
  kind: 'etablissement'; userId: string; email: string | null;
  etablissementId: string; membershipRole: string; permissions: NativeEstablishmentPermissions;
}
export interface NativeOnboardingContext {
  kind: 'onboarding'; userId: string; email: string | null;
  emailConfirmed: boolean;
  /** Only the server draft reserves an account family. An intention is not a role. */
  parcours: NativeRegistrationDraft | null;
  suggestedRegistration?: NativeRegistrationIntent | null;
}
export type NativeSoignantContext = MissionReadContext & { kind: 'soignant' };
export type NativeAccountContext = NativeSoignantContext | NativeEstablishmentContext | NativeOnboardingContext;

export interface NativeQuickRegistration extends NativeRegistrationIntent { email: string; password: string }
export type RegistrationResult = { status: 'confirmation'; email: string } | { status: 'created' };
export interface NativeRegistrationForm {
  prenom: string; nom: string; telephone: string; dateNaissance: string; profession: string;
  typesContrat: string[]; rpps: string; rayon: number;
  estEtudiant: boolean; scolariteFormation: string; scolariteAnnee: string;
  siret: string; finess: string; type: string; rue: string; ville: string; codePostal: string;
  departement: string; emailContact: string; telephoneContact: string; numeroLicence: string;
}
export interface NativeAccountGateway {
  readonly mode: 'demo' | 'staging';
  createAccount(input: NativeQuickRegistration): Promise<RegistrationResult>;
  startRegistration(userId: string, intent: NativeRegistrationIntent): Promise<void>;
  saveDraft(userId: string, values: NativeRegistrationForm): Promise<void>;
  completeRegistration(context: NativeOnboardingContext, values: NativeRegistrationForm): Promise<void>;
  getExerciseTypes(profession: string, signal?: AbortSignal): Promise<string[]>;
  getStudentProfessions(formation: string, year: number, signal?: AbortSignal): Promise<string[]>;
  confirmEmail(url: string): Promise<void>;
}

import type { SupabaseClient } from '@supabase/supabase-js';
import { validerProfilSoignant } from '../../../src/lib/valider-profil-soignant';
import { calculerCompletionProfil } from '../../../src/lib/profil-soignant';
import { throwIfAborted } from '../data/business';
import type { MissionReadContext } from '../data/types';

export type CaregiverProfile = ReturnType<typeof validerProfilSoignant>;
export { calculerCompletionProfil };
/** A validated identity may come from documents even when the profession has no RPPS. */
export const identityLocked = (profile: CaregiverProfile) => profile.rpps_verifie === true || profile.identite_verifiee === true;
export interface ProfileChanges {
  prenom: string; nom: string; telephone: string; dateNaissance: string;
  bio: string; anneesExperience: number; ville: string; rayon: number;
}

export function profileChanges(profile: CaregiverProfile): ProfileChanges {
  return { prenom: profile.prenom ?? '', nom: profile.nom ?? '', telephone: profile.telephone ?? '',
    dateNaissance: profile.date_naissance ?? '', bio: profile.bio ?? '',
    anneesExperience: profile.annees_experience ?? 0, ville: profile.ville_recherche ?? '',
    rayon: profile.rayon_deplacement_km ?? 30 };
}

export function profileArguments(changes: ProfileChanges, lockedIdentity: boolean): Record<string, unknown> {
  if (!Number.isInteger(changes.anneesExperience) || changes.anneesExperience < 0
    || !Number.isInteger(changes.rayon) || changes.rayon <= 0) throw new Error('Vérifiez les années d’expérience et le rayon de recherche.');
  if (!lockedIdentity && (!changes.prenom.trim() || !changes.nom.trim())) throw new Error('Le prénom et le nom ne peuvent pas être vides.');
  if (!lockedIdentity && (!/^\d{4}-\d{2}-\d{2}$/.test(changes.dateNaissance)
    || !Number.isFinite(Date.parse(changes.dateNaissance))
    || new Date(changes.dateNaissance).toISOString().slice(0, 10) !== changes.dateNaissance)) {
    throw new Error('Indiquez une date de naissance valide au format AAAA-MM-JJ.');
  }
  // RPC NULL means keep the old value; empty text explicitly clears optional fields.
  return {
    p_telephone: changes.telephone.trim(), p_bio: changes.bio.trim(),
    p_annees_experience: changes.anneesExperience, p_ville_recherche: changes.ville.trim(),
    p_rayon_deplacement_km: changes.rayon,
    ...(!lockedIdentity ? { p_prenom: changes.prenom.trim(), p_nom: changes.nom.trim(),
      p_date_naissance: changes.dateNaissance } : {}),
  };
}

export interface ProfileGateway {
  mode: 'demo' | 'supabase';
  read(context: MissionReadContext, signal?: AbortSignal): Promise<CaregiverProfile>;
  save(context: MissionReadContext, changes: ProfileChanges, signal?: AbortSignal): Promise<CaregiverProfile>;
}

export class SupabaseProfileGateway implements ProfileGateway {
  readonly mode = 'supabase' as const;
  constructor(private readonly client: SupabaseClient) {}
  private async token(context: MissionReadContext, signal?: AbortSignal) {
    throwIfAborted(signal);
    const { data, error } = await this.client.auth.getSession();
    throwIfAborted(signal);
    if (error || !data.session || data.session.user.id !== context.userId) throw new Error('Reconnectez-vous avant de continuer.');
    return data.session.access_token;
  }
  private async readWithToken(context: MissionReadContext, token: string, signal?: AbortSignal) {
    let query = this.client.rpc('fn_mon_profil_soignant_complet').setHeader('Authorization', `Bearer ${token}`);
    if (signal) query = query.abortSignal(signal);
    const { data, error } = await query;
    throwIfAborted(signal);
    if (error) throw error;
    return validerProfilSoignant(data, context.userId);
  }
  async read(context: MissionReadContext, signal?: AbortSignal) {
    return this.readWithToken(context, await this.token(context, signal), signal);
  }
  async save(context: MissionReadContext, changes: ProfileChanges, signal?: AbortSignal) {
    const token = await this.token(context, signal);
    const before = await this.readWithToken(context, token, signal);
    throwIfAborted(signal);
    let query = this.client.rpc('fn_modifier_mon_profil', profileArguments(changes, identityLocked(before)))
      .setHeader('Authorization', `Bearer ${token}`);
    if (signal) query = query.abortSignal(signal);
    const { data, error } = await query;
    throwIfAborted(signal);
    if (error) throw error;
    if (data && typeof data === 'object' && data.error) throw new Error(String(data.error));
    return this.readWithToken(context, token, signal);
  }
}

/** Demo edits are memory-only and never use a server client. */
export class DemoProfileGateway implements ProfileGateway {
  readonly mode = 'demo' as const;
  private profile: CaregiverProfile | null = null;
  async read(context: MissionReadContext, signal?: AbortSignal) {
    throwIfAborted(signal);
    if (context.userId !== 'demo-soignant') throw new Error('Profil de démonstration uniquement.');
    this.profile ??= validerProfilSoignant({ ...context.profile, prenom: 'Camille', nom: 'Démo', email: context.email,
      telephone: '', date_naissance: '1994-05-15', numero_rpps: null, rpps_verifie: false,
      bio: 'Profil fictif pour la simulation native.', annees_experience: 4, ville_recherche: 'Paris', specialites: [] }, context.userId);
    return { ...this.profile };
  }
  async save(context: MissionReadContext, changes: ProfileChanges, signal?: AbortSignal) {
    const before = await this.read(context, signal);
    profileArguments(changes, identityLocked(before));
    this.profile = { ...before, prenom: changes.prenom, nom: changes.nom, telephone: changes.telephone,
      date_naissance: changes.dateNaissance, bio: changes.bio, annees_experience: changes.anneesExperience,
      ville_recherche: changes.ville, rayon_deplacement_km: changes.rayon };
    return { ...this.profile };
  }
}

import type { SupabaseClient } from '@supabase/supabase-js';
import type { MissionGateway } from '../data/types';
import { throwIfAborted } from '../data/business';
import { UnsupportedNativeAccount, type AuthSession } from '../session/controller';
import type { NativeAccountContext, NativeEstablishmentPermissions, NativeRegistrationDraft, NativeRegistrationIntent } from './types';

const permissionKeys = ['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement', 'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'] as const;
export function registrationDraft(value: unknown, userId: string): NativeRegistrationDraft | null {
  if (value === null) return null;
  const row = value as Partial<NativeRegistrationDraft> | undefined;
  if (!row || row.user_id !== userId || !['SOIGNANT', 'ETABLISSEMENT'].includes(row.type_compte ?? '')
    || !row.donnees || typeof row.donnees !== 'object' || Array.isArray(row.donnees) || typeof row.modifie_le !== 'string') {
    throw new Error('Invalid registration draft');
  }
  return row as NativeRegistrationDraft;
}
export function registrationIntent(value: unknown): NativeRegistrationIntent | null {
  const v = value as Partial<NativeRegistrationIntent> | null;
  if (!v || !['SOIGNANT', 'ETABLISSEMENT'].includes(v.type ?? '') || v.cgu !== true
    || (v.type === 'ETABLISSEMENT' && v.cgv !== true)) return null;
  return { type: v.type!, profession: typeof v.profession === 'string' ? v.profession : '', nom: typeof v.nom === 'string' ? v.nom : '', cgu: true, cgv: v.cgv === true };
}

/** Every admission is re-read under the ordinary user's JWT. Metadata cannot grant permissions. */
export async function resolveNativeAccount(client: SupabaseClient, missions: MissionGateway, session: AuthSession, signal: AbortSignal): Promise<NativeAccountContext> {
  const { data, error } = await client.auth.getUser(session.access_token);
  throwIfAborted(signal);
  if (error || !data.user || data.user.id !== session.user.id) throw new Error('Invalid session');
  const user = data.user;
  const base = { userId: user.id, email: user.email ?? null };
  const authorization = `Bearer ${session.access_token}`;
  const { data: role, error: roleError } = await client.rpc('fn_get_my_role').setHeader('Authorization', authorization).abortSignal(signal);
  throwIfAborted(signal);
  if (roleError || !role || typeof role.role !== 'string' || (role.user_id && role.user_id !== user.id)) throw new Error('Invalid role');
  // Unconfirmed identities can only complete authentication, never enter a business space.
  if (!user.email_confirmed_at || role.role === 'INCONNU' || role.parcours_incomplet === true) {
    const draftResult = await client.from('parcours_inscription').select('user_id,type_compte,donnees,modifie_le')
      .eq('user_id', user.id).setHeader('Authorization', authorization).abortSignal(signal).maybeSingle();
    throwIfAborted(signal);
    if (draftResult.error) throw draftResult.error;
    return { ...base, kind: 'onboarding', emailConfirmed: !!user.email_confirmed_at,
      parcours: registrationDraft(draftResult.data, user.id), suggestedRegistration: registrationIntent(user.user_metadata?.inscription_progressive) };
  }
  if (role.role === 'SOIGNANT') {
    const profile = await missions.getProfile(user.id, signal);
    throwIfAborted(signal);
    if (!profile) throw new UnsupportedNativeAccount('Votre profil professionnel n’est pas encore disponible. Réessayez après l’avoir complété dans Jolene.');
    return { ...base, kind: 'soignant', profile };
  }
  if (role.role === 'ADMIN_ETABLISSEMENT' || role.role === 'ETABLISSEMENT') {
    // The permissions RPC resolves legacy owner scopes itself; no user.id fallback here.
    const requestedId = typeof role.etablissement_id === 'string' ? role.etablissement_id : null;
    const result = await client.rpc('fn_mes_permissions_etab', { p_etablissement_id: requestedId }).setHeader('Authorization', authorization).abortSignal(signal);
    throwIfAborted(signal);
    const permissions = result.data?.permissions;
    const scope = result.data?.etablissement_id;
    if (result.error || result.data?.success !== true || typeof scope !== 'string' || !scope
      || (requestedId && scope !== requestedId) || typeof result.data.role !== 'string' || !result.data.role
      || !permissions || permissionKeys.some(key => typeof permissions[key] !== 'boolean')) throw new Error('Invalid establishment permissions');
    return { ...base, kind: 'etablissement', etablissementId: scope, membershipRole: result.data.role,
      permissions: Object.fromEntries(permissionKeys.map(key => [key, permissions[key]])) as unknown as NativeEstablishmentPermissions };
  }
  throw new UnsupportedNativeAccount('Cet espace administrateur n’est pas disponible dans le parcours natif.');
}

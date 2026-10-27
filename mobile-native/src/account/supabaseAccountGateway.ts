import type { SupabaseClient } from '@supabase/supabase-js';
import { PROFESSIONS } from '../../../src/lib/constantes';
import { throwIfAborted } from '../data/business';
import type { NativeSessionController } from '../session/controller';
import type { NativeAccountGateway, NativeOnboardingContext, NativeQuickRegistration, NativeRegistrationForm, NativeRegistrationIntent, RegistrationResult } from './types';
import { registrationDraft } from './resolveContext';
import { NativeAccountError } from './errors';
import { registrationBody, restoreRegistrationForm } from './registration';
import { CONFIRMATION_CALLBACK, parseNativeAuthCallback } from './callbacks';

function validateIntent(input: NativeRegistrationIntent) {
  if (!['SOIGNANT', 'ETABLISSEMENT'].includes(input.type) || !input.cgu || (input.type === 'ETABLISSEMENT' && !input.cgv)) {
    throw new NativeAccountError('Choisissez votre espace et acceptez les conditions applicables.');
  }
  if (input.type === 'SOIGNANT' && !PROFESSIONS.some(p => p.valeur === input.profession)) throw new NativeAccountError('Choisissez votre profession.');
  if (input.type === 'ETABLISSEMENT' && !input.nom.trim()) throw new NativeAccountError('Indiquez le nom de votre établissement.');
}
export class SupabaseAccountGateway implements NativeAccountGateway {
  readonly mode = 'staging' as const;
  private confirmations = new Map<string, Promise<void>>();
  constructor(private readonly client: SupabaseClient, private readonly controller: NativeSessionController) {}

  private async currentSession(userId: string | null, assertActive: () => void) {
    assertActive();
    const { data, error } = await this.client.auth.getSession();
    assertActive();
    if (error || !data.session || (userId && data.session.user.id !== userId)) throw new NativeAccountError('Reconnectez-vous pour reprendre cette inscription.');
    const verified = await this.client.auth.getUser(data.session.access_token);
    assertActive();
    if (verified.error || verified.data.user?.id !== data.session.user.id) throw new NativeAccountError('Votre session doit être vérifiée. Reconnectez-vous.');
    return { session: data.session, user: verified.data.user };
  }
  private async begin(userId: string, intent: NativeRegistrationIntent, assertActive: () => void) {
    validateIntent(intent);
    const { session } = await this.currentSession(userId, assertActive);
    const { data, error } = await this.client.rpc('fn_demarrer_inscription', {
      p_type_compte: intent.type, p_profession: intent.profession || null, p_nom: intent.nom || null,
      p_cgu: intent.cgu, p_cgv: intent.cgv,
    }).setHeader('Authorization', `Bearer ${session.access_token}`);
    assertActive();
    if (error) {
      if (/ACCOUNT_ALREADY_REGISTERED|ACCOUNT_TYPE_MISMATCH|ACCOUNT_REGISTRATION_INCOMPLETE/.test(error.message ?? '')) {
        throw new NativeAccountError('Ce compte possède déjà un espace Jolene. Reconnectez-vous pour le retrouver.');
      }
      throw error;
    }
    if (registrationDraft(data, userId)?.type_compte !== intent.type) throw new Error('Invalid server account family');
  }
  createAccount(input: NativeQuickRegistration): Promise<RegistrationResult> {
    return this.controller.runAuthOperation(async assertActive => {
      validateIntent(input);
      const email = input.email.trim().toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || input.password.length < 8) throw new NativeAccountError('Renseignez un email valide et un mot de passe de 8 caractères minimum.');
      const { data: existing, error: existingError } = await this.client.auth.getSession();
      assertActive();
      if (existingError) throw existingError;
      const intent: NativeRegistrationIntent = { type: input.type, profession: input.profession, nom: input.nom, cgu: input.cgu, cgv: input.cgv };
      if (existing.session) {
        if (existing.session.user.email?.toLowerCase() !== email) throw new NativeAccountError('Déconnectez le compte actuel avant de créer un autre compte.');
        await this.begin(existing.session.user.id, intent, assertActive);
        return { status: 'created' };
      }
      const response = await this.client.auth.signUp({ email, password: input.password,
        options: { emailRedirectTo: CONFIRMATION_CALLBACK, data: { inscription_progressive: intent } } });
      assertActive();
      if ((response.error && /already.*registered|user.*registered/i.test(response.error.message))
        || (!response.error && !response.data.session && response.data.user?.identities?.length === 0)) {
        throw new NativeAccountError('Ce compte existe déjà. Connectez-vous pour reprendre votre inscription.', 'SIGN_IN_REQUIRED');
      }
      if (response.error) throw response.error;
      if (!response.data.user) throw new Error('Missing Auth identity');
      if (!response.data.session) return { status: 'confirmation', email };
      await this.begin(response.data.user.id, intent, assertActive);
      return { status: 'created' };
    });
  }
  startRegistration(userId: string, intent: NativeRegistrationIntent) {
    return this.controller.runAuthOperation(assertActive => this.begin(userId, intent, assertActive));
  }
  private async save(userId: string, values: NativeRegistrationForm, assertActive: () => void) {
    const { session } = await this.currentSession(userId, assertActive);
    // Exact allowed form fields only: no credentials, verification status or derived student rights.
    const { data, error } = await this.client.rpc('fn_enregistrer_parcours_inscription', { p_donnees: restoreRegistrationForm(values as unknown as Record<string, unknown>) })
      .setHeader('Authorization', `Bearer ${session.access_token}`);
    assertActive();
    if (error) throw error;
    if (!registrationDraft(data, userId)) throw new Error('Draft was not saved');
  }
  saveDraft(userId: string, values: NativeRegistrationForm) {
    return this.controller.runAuthOperation(assertActive => this.save(userId, values, assertActive));
  }
  completeRegistration(context: NativeOnboardingContext, values: NativeRegistrationForm) {
    return this.controller.runAuthOperation(async assertActive => {
      if (!context.parcours) throw new NativeAccountError('Choisissez d’abord votre espace pour commencer votre inscription.');
      const { user, session } = await this.currentSession(context.userId, assertActive);
      if (!user.email_confirmed_at) throw new NativeAccountError('Confirmez votre adresse email avant de terminer votre profil.');
      const body = registrationBody(context.parcours.type_compte, values, user.email ?? null);
      await this.save(context.userId, values, assertActive);
      const { data, error } = await this.client.functions.invoke(context.parcours.type_compte === 'SOIGNANT' ? 'register-soignant' : 'register-etablissement', {
        headers: { Authorization: `Bearer ${session.access_token}` }, body: { ...body, navigateur: 'Jolene React Native' },
      });
      assertActive();
      let result = data;
      if (!result && error?.context instanceof Response) {
        try { result = await error.context.json(); } catch { /* Report a normal service error below. */ }
      }
      assertActive();
      if (error || result?.ok !== true || result?.success !== true) {
        throw new NativeAccountError(typeof result?.message === 'string' ? result.message.slice(0, 700) : 'Votre profil n’a pas pu être finalisé. Votre brouillon est conservé ; réessayez.', typeof result?.code === 'string' ? result.code : undefined);
      }
      const createdId = context.parcours.type_compte === 'SOIGNANT' ? result.soignant_id : result.etablissement_id;
      if (createdId !== context.userId) throw new NativeAccountError('Le profil créé ne correspond pas à ce compte. Reconnectez-vous pour vérifier votre espace.');
      const refresh = await this.client.auth.refreshSession();
      assertActive();
      if (refresh.error) throw new NativeAccountError('Votre profil est enregistré. Reconnectez-vous pour ouvrir votre espace.');
    });
  }
  async getExerciseTypes(profession: string, signal?: AbortSignal) {
    let request = this.client.rpc('fn_types_exercice_autorises', { p_profession: profession });
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error || !Array.isArray(data) || data.some(v => typeof v !== 'string')) throw new Error('Exercise types unavailable');
    return data as string[];
  }
  async getStudentProfessions(formation: string, year: number, signal?: AbortSignal) {
    if (formation === 'MEDECINE_DES') return [];
    let request = this.client.rpc('fn_professions_autorisees_scolarite', { p_formation: formation, p_annee_validee: year });
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    throwIfAborted(signal);
    if (error || !Array.isArray(data)) throw new Error('Student eligibility unavailable');
    return data.map(row => typeof row === 'string' ? row : row?.fn_professions_autorisees_scolarite ?? Object.values(row ?? {})[0])
      .filter((v): v is string => v === 'AS');
  }
  confirmEmail(url: string): Promise<void> {
    const credentials = parseNativeAuthCallback(url, 'confirmation');
    // Avoid consuming a one-use link twice when a React effect mounts again.
    const key = credentials.kind === 'code' ? credentials.code : credentials.tokenHash;
    const existing = this.confirmations.get(key);
    if (existing) return existing;
    const request = this.controller.runAuthOperation(async assertActive => {
      const result = credentials.kind === 'code'
        ? await this.client.auth.exchangeCodeForSession(credentials.code)
        : await this.client.auth.verifyOtp({ token_hash: credentials.tokenHash, type: credentials.type });
      assertActive();
      if ('redirectType' in result.data && result.data.redirectType === 'recovery') {
        await this.client.auth.signOut({ scope: 'local' });
        throw new NativeAccountError('Ce lien correspond à une récupération de mot de passe, pas à une confirmation d’inscription.');
      }
      if (result.error || !result.data.session) throw new NativeAccountError('Le lien de confirmation est invalide ou expiré. Reconnectez-vous ou demandez un nouveau lien.');
    });
    this.confirmations.set(key, request);
    // Only a bounded in-memory deduplication map; never persist or log link secrets.
    if (this.confirmations.size > 4) this.confirmations.delete(this.confirmations.keys().next().value!);
    return request;
  }
}

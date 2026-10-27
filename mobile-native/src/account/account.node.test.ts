import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { MissionGateway } from '../data/types';
import type { NativeSessionController } from '../session/controller';
import { CONFIRMATION_CALLBACK, parseNativeAuthCallback } from './callbacks';
import { resolveNativeAccount } from './resolveContext';
import { registrationBody, restoreRegistrationForm, studentFormations } from './registration';
import { SupabaseAccountGateway } from './supabaseAccountGateway';
import { DEMO_ONBOARDING_CONTEXT } from './demoAccountGateway';
import { DemoAccountGateway } from './demoAccountGateway';
import { createNativeSessionController } from '../session/controller';

function request(data: unknown, error: unknown = null) {
  return Object.assign(Promise.resolve({ data, error }), {
    select() { return this; }, eq() { return this; }, abortSignal() { return this; }, maybeSingle() { return this; },
    setHeader(_name: string, _value: string) { return this; },
  });
}
const session = { user: { id: 'user-a' }, access_token: 'fictional-user-a-token' };
const user = { id: 'user-a', email: 'a@example.invalid', email_confirmed_at: '2026-10-01', user_metadata: {} };
const draft = { user_id: 'user-a', type_compte: 'SOIGNANT', donnees: { profession: 'MEDECIN' }, modifie_le: '2026-10-27' };
const permissions = Object.fromEntries(['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement', 'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture'].map(key => [key, key === 'lecture']));
function resolverFixture(role: Record<string, unknown>, registration: unknown = draft, authUser = user, perms: unknown = { success: true, etablissement_id: 'etab-a', role: 'LECTURE_SEULE', permissions }) {
  const calls: string[] = [];
  const client = {
    auth: { getUser: async () => ({ data: { user: authUser }, error: null }) },
    rpc(name: string) { calls.push(name); return request(name === 'fn_get_my_role' ? role : perms); },
    from(name: string) { calls.push(name); return request(registration); },
  } as unknown as SupabaseClient;
  const missions = { getProfile: async () => { calls.push('profile'); return { id: 'user-a', profession: 'MEDECIN' }; } } as unknown as MissionGateway;
  return { calls, resolve: () => resolveNativeAccount(client, missions, session, new AbortController().signal) };
}
test('unconfirmed identity cannot enter a business space even when the role RPC says soignant', async () => {
  const f = resolverFixture({ role: 'SOIGNANT', user_id: 'user-a' }, draft, { ...user, email_confirmed_at: '' });
  const context = await f.resolve();
  assert.equal(context.kind, 'onboarding');
  assert.equal(context.kind === 'onboarding' && context.emailConfirmed, false);
  assert.ok(!f.calls.includes('profile'));
});
test('incomplete registration stays distinct from a professional role and rejects another user draft', async () => {
  const f = resolverFixture({ role: 'INCONNU', user_id: 'user-a' });
  const context = await f.resolve();
  assert.equal(context.kind, 'onboarding');
  assert.equal(context.kind === 'onboarding' && context.parcours?.type_compte, 'SOIGNANT');
  await assert.rejects(resolverFixture({ role: 'INCONNU' }, { ...draft, user_id: 'user-b' }).resolve());
});
test('server incomplete flag cannot be bypassed by a nominal soignant role', async () => {
  assert.equal((await resolverFixture({ role: 'SOIGNANT', parcours_incomplet: true }).resolve()).kind, 'onboarding');
});
test('establishment scope and permissions come from the server, not auth.user.id', async () => {
  const context = await resolverFixture({ role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'etab-a' }).resolve();
  assert.equal(context.kind, 'etablissement');
  if (context.kind !== 'etablissement') throw new Error('Wrong kind');
  assert.equal(context.etablissementId, 'etab-a');
  assert.equal(context.membershipRole, 'LECTURE_SEULE');
  assert.equal(context.permissions.lecture, true);
  assert.equal(context.permissions.missions, false);
  await assert.rejects(resolverFixture({ role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'etab-a' }, draft, user,
    { success: true, etablissement_id: 'other', role: 'PROPRIETAIRE', permissions }).resolve());
  await assert.rejects(resolverFixture({ role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'etab-a' }, draft, user,
    { success: true, etablissement_id: 'etab-a', role: 'RH', permissions: { ...permissions, missions: 'true' } }).resolve());
});
test('confirmation links reject foreign hosts, recovery substitutions and ambiguous credentials', () => {
  assert.deepEqual(parseNativeAuthCallback(`${CONFIRMATION_CALLBACK}?code=fictional-code`, 'confirmation'), { kind: 'code', code: 'fictional-code' });
  for (const url of ['https://jolene.app/auth/confirm?code=x', 'jolene-native-pilot://auth/confirm.evil?code=x',
    `${CONFIRMATION_CALLBACK}?token_hash=x&type=recovery`, `${CONFIRMATION_CALLBACK}?code=x&token_hash=y`,
    `${CONFIRMATION_CALLBACK}#access_token=x&refresh_token=y`]) assert.throws(() => parseNativeAuthCallback(url, 'confirmation'));
});
test('medical internat preserves MEDECIN and its exact declaration without an AS equivalence', () => {
  const form = restoreRegistrationForm(DEMO_ONBOARDING_CONTEXT.parcours!.donnees);
  const body = registrationBody('SOIGNANT', form, 'student@example.invalid');
  assert.equal('profession' in body && body.profession, 'MEDECIN');
  assert.equal('etudiant_details' in body && body.etudiant_details, 'Médecine — 3e cycle (internat)');
  assert.deepEqual(studentFormations('MEDECIN').map(f => f.valeur), ['MEDECINE_DFGSM', 'MEDECINE_DFASM', 'MEDECINE_DES']);
  assert.ok(!studentFormations('AS').some(f => f.valeur === 'MEDECINE_DES'));
  assert.equal('rpps_verifie' in body, false);
  assert.equal('peut_candidater' in body, false);
});
test('draft restore excludes credentials and invalid cycles, while the profession determines RPPS requirements', () => {
  const form = restoreRegistrationForm({ ...DEMO_ONBOARDING_CONTEXT.parcours!.donnees, profession: 'AS', password: 'secret', scolariteFormation: 'MEDECINE_DES' });
  assert.equal('password' in form, false);
  assert.equal(form.scolariteFormation, '');
  assert.throws(() => registrationBody('SOIGNANT', { ...form, profession: 'MEDECIN', rpps: '' }, null));
  assert.doesNotThrow(() => registrationBody('SOIGNANT', { ...form, profession: 'AS', rpps: '' }, null));
});
test('demo medical completion preserves the declared profession and never verifies documents', async () => {
  const controller = createNativeSessionController({ mode: 'demo', context: DEMO_ONBOARDING_CONTEXT });
  controller.start(); controller.enterDemo();
  const gateway = new DemoAccountGateway(controller);
  await gateway.completeRegistration(DEMO_ONBOARDING_CONTEXT, restoreRegistrationForm(DEMO_ONBOARDING_CONTEXT.parcours!.donnees));
  const context = controller.getSnapshot().context;
  assert.equal(context?.kind, 'soignant');
  if (context?.kind !== 'soignant') throw new Error('Wrong kind');
  assert.equal(context.profile.profession, 'MEDECIN');
  assert.equal(context.profile.types_contrat_acceptes, '["SALARIE"]');
  assert.equal(context.profile.tous_documents_valides, false);
  assert.equal('rpps_verifie' in context.profile, false);
  controller.stop();
});
test('complete registration saves only a draft then invokes the authenticated endpoint with the internat declaration', async () => {
  const calls: { name: string; params: any; header?: string }[] = [];
  const client = {
    auth: {
      getSession: async () => ({ data: { session: { ...session, user } }, error: null }),
      getUser: async () => ({ data: { user }, error: null }),
      refreshSession: async () => { calls.push({ name: 'refresh', params: {} }); return { error: null }; },
    },
    rpc(name: string, params: unknown) {
      const call = { name, params, header: '' }; calls.push(call);
      return Object.assign(request(draft), { setHeader(_name: string, value: string) { call.header = value; return this; } });
    },
    functions: { invoke: async (name: string, params: unknown) => { calls.push({ name, params }); return { data: { ok: true, success: true, soignant_id: 'user-a' }, error: null }; } },
  } as unknown as SupabaseClient;
  const controller = { runAuthOperation: (action: (guard: () => void) => Promise<unknown>) => action(() => {}) } as unknown as NativeSessionController;
  const gateway = new SupabaseAccountGateway(client, controller);
  await gateway.completeRegistration({ kind: 'onboarding', userId: 'user-a', email: user.email, emailConfirmed: true, parcours: draft as any }, restoreRegistrationForm(DEMO_ONBOARDING_CONTEXT.parcours!.donnees));
  assert.deepEqual(calls.map(c => c.name), ['fn_enregistrer_parcours_inscription', 'register-soignant', 'refresh']);
  assert.equal(calls[0]!.header, `Bearer ${session.access_token}`);
  assert.equal('etudiant_details' in calls[0]!.params.p_donnees, false);
  assert.equal(calls[1]!.params.headers.Authorization, `Bearer ${session.access_token}`);
  assert.equal(calls[1]!.params.body.est_etudiant, true);
  assert.equal(calls[1]!.params.body.etudiant_details, 'Médecine — 3e cycle (internat)');
  assert.equal('rpps_verifie' in calls[1]!.params.body, false);
});

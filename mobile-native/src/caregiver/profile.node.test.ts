import test from 'node:test';
import assert from 'node:assert/strict';
import { DemoProfileGateway, identityLocked, profileArguments, profileChanges, SupabaseProfileGateway } from './profile';
import { DEMO_CONTEXT } from '../data/demoGateway';

test('verified identity fields cannot be submitted by the contact editor', async () => {
  const profile = await new DemoProfileGateway().read(DEMO_CONTEXT);
  const args = profileArguments({ ...profileChanges(profile), prenom: 'Remplacé', nom: 'Autre', dateNaissance: 'bad' }, true);
  assert.equal(args.p_prenom, undefined);
  assert.equal(args.p_nom, undefined);
  assert.equal(args.p_date_naissance, undefined);
  assert.equal(args.p_rpps_verifie, undefined);
});

test('invalid dates and non-finite experience never reach RPC', async () => {
  const changes = profileChanges(await new DemoProfileGateway().read(DEMO_CONTEXT));
  assert.throws(() => profileArguments({ ...changes, dateNaissance: '2025-02-31' }, false));
  assert.throws(() => profileArguments({ ...changes, anneesExperience: NaN }, false));
});

test('demo profile edits persist in their own gateway and reject another identity', async () => {
  const gateway = new DemoProfileGateway();
  const original = await gateway.read(DEMO_CONTEXT);
  await gateway.save(DEMO_CONTEXT, { ...profileChanges(original), bio: 'Nouvelle présentation fictive' });
  assert.equal((await gateway.read(DEMO_CONTEXT)).bio, 'Nouvelle présentation fictive');
  await assert.rejects(gateway.read({ ...DEMO_CONTEXT, userId: 'real-user' }));
  assert.equal((await new DemoProfileGateway().read(DEMO_CONTEXT)).bio, original.bio);
});

test('stale account cannot save a profile using another signed-in identity', async () => {
  let calls = 0;
  const client = {
    auth: { getSession: async () => ({ data: { session: { user: { id: 'other' }, access_token: 'synthetic' } }, error: null }) },
    rpc: () => { calls += 1; throw new Error('Must not be called'); },
  };
  const gateway = new SupabaseProfileGateway(client as never);
  const changes = profileChanges(await new DemoProfileGateway().read(DEMO_CONTEXT));
  await assert.rejects(gateway.save(DEMO_CONTEXT, changes));
  assert.equal(calls, 0);
});


test('saving cleared optional fields removes their old server values instead of reporting a silent no-op', async () => {
  let persisted = await new DemoProfileGateway().read(DEMO_CONTEXT);
  const client = {
    auth: { getSession: async () => ({ data: { session: { user: { id: DEMO_CONTEXT.userId }, access_token: 'synthetic' } }, error: null }) },
    rpc(name: string, args?: Record<string, unknown>) {
      // The deployed SQL uses COALESCE(parameter, stored_value).
      if (name === 'fn_modifier_mon_profil') persisted = { ...persisted,
        bio: (args?.p_bio ?? persisted.bio) as string,
        telephone: (args?.p_telephone ?? persisted.telephone) as string,
        ville_recherche: (args?.p_ville_recherche ?? persisted.ville_recherche) as string };
      return { setHeader() { return this; }, then(resolve: (value: unknown) => void) {
        resolve({ data: name === 'fn_mon_profil_soignant_complet' ? persisted : { success: true }, error: null });
      } };
    },
  };
  const result = await new SupabaseProfileGateway(client as never).save(DEMO_CONTEXT,
    { ...profileChanges(persisted), bio: '', ville: '', telephone: '' });
  assert.equal(result.bio, '');
  assert.equal(result.ville_recherche, '');
  assert.equal(result.telephone, '');
  const changes = profileChanges(persisted);
  assert.throws(() => profileArguments({ ...changes, nom: '' }, false));
  assert.throws(() => profileArguments({ ...changes, dateNaissance: '' }, false));
});


test('a document-verified identity without RPPS keeps name and birth date out of profile mutations', async () => {
  const profile = { ...await new DemoProfileGateway().read(DEMO_CONTEXT), profession: 'AS' as const, rpps_verifie: false, identite_verifiee: true };
  assert.equal(identityLocked(profile), true);
  const args = profileArguments({ ...profileChanges(profile), prenom: 'Changed', nom: 'Changed', dateNaissance: 'invalid' }, identityLocked(profile));
  assert.equal(args.p_prenom, undefined);
  assert.equal(args.p_nom, undefined);
  assert.equal(args.p_date_naissance, undefined);
});

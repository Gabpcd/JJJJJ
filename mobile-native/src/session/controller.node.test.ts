import assert from 'node:assert/strict';
import test from 'node:test';
import type { MissionReadContext } from '../data/types';
import { createNativeSessionController, UnsupportedNativeAccount, type AuthPort, type AuthSession } from './controller';

function context(id: string): MissionReadContext {
  return { userId: id, email: `${id}@example.invalid`, profile: {
    id, profession: 'INFIRMIER', adresse_lat: null, adresse_lng: null, rayon_deplacement_km: null,
    tous_documents_valides: false, type_contrat: null, types_contrat_acceptes: null, type_exercice: null, taux_horaire_minimum: null,
  } };
}
const session = (id: string): AuthSession => ({ user: { id }, access_token: 'fictional-session-value' });
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 5));
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
function fixture(resolveContext = async (value: AuthSession, _signal: AbortSignal) => context(value.user.id)) {
  let listener: ((value: AuthSession | null) => void) | null = null;
  let stored: AuthSession | null = null;
  let cleared = 0;
  const auth: AuthPort = {
    async getSession() { return stored; },
    subscribe(callback) { listener = callback; return () => { listener = null; }; },
    async signIn() { stored = session('first'); listener?.(stored); return stored; },
    async signOut() { stored = null; listener?.(null); },
    async clearStorage() { stored = null; cleared += 1; },
  };
  const controller = createNativeSessionController({ mode: 'staging', auth, resolveContext });
  return { controller, auth, emit: (value: AuthSession | null) => { stored = value; listener?.(value); }, cleared: () => cleared };
}

test('demo never needs email or password and logout clears its navigation identity', async () => {
  const controller = createNativeSessionController({ mode: 'demo', context: context('demo') });
  controller.start();
  await controller.signIn('unused', 'unused');
  assert.equal(controller.getSnapshot().status, 'signedOut');
  controller.enterDemo();
  const epoch = controller.getSnapshot().epoch;
  assert.equal(controller.getSnapshot().context?.userId, 'demo');
  await controller.signOut();
  assert.equal(controller.getSnapshot().context, null);
  assert.ok(controller.getSnapshot().epoch > epoch);
  controller.stop();
});

test('token refresh for the same user preserves navigation and list identity', async () => {
  const f = fixture(); f.controller.start(); await tick();
  await f.controller.signIn('a@example.invalid', 'fictional');
  const epoch = f.controller.getSnapshot().epoch;
  f.emit({ ...session('first'), access_token: 'fictional-refreshed-value' }); await tick();
  assert.equal(f.controller.getSnapshot().epoch, epoch);
  assert.equal(f.controller.getSnapshot().status, 'authenticated');
  f.controller.stop();
});

test('external sign-out clears visible context synchronously and cancels old role resolution', async () => {
  const late = deferred<MissionReadContext>();
  const f = fixture(() => late.promise); f.controller.start(); await tick();
  f.emit(session('first')); await tick();
  f.emit(null);
  assert.equal(f.controller.getSnapshot().context, null);
  late.resolve(context('first')); await tick();
  assert.equal(f.controller.getSnapshot().status, 'signedOut');
  f.controller.stop();
});

test('changing user hides the old context immediately and late profile cannot overwrite the new user', async () => {
  const first = deferred<MissionReadContext>();
  const f = fixture((value) => value.user.id === 'first' ? first.promise : Promise.resolve(context(value.user.id)));
  f.controller.start(); await tick(); f.emit(session('first')); await tick();
  f.emit(session('second')); await tick();
  first.resolve(context('first')); await tick();
  assert.equal(f.controller.getSnapshot().context?.userId, 'second');
  f.controller.stop();
});

test('late initial getSession never overrides a newer auth event', async () => {
  const initial = deferred<AuthSession | null>();
  const f = fixture(); f.auth.getSession = () => initial.promise;
  f.controller.start(); f.emit(session('new')); await tick();
  initial.resolve(session('old')); await tick();
  assert.equal(f.controller.getSnapshot().context?.userId, 'new');
  f.controller.stop();
});

test('getSession from a stopped subscription cannot restore an older identity after restart', async () => {
  const old = deferred<AuthSession | null>();
  const f = fixture(); let calls = 0;
  f.auth.getSession = () => ++calls === 1 ? old.promise : Promise.resolve(null);
  f.controller.start(); f.controller.stop(); f.controller.start(); await tick();
  old.resolve(session('old')); await tick();
  assert.equal(f.controller.getSnapshot().context, null);
  assert.equal(f.controller.getSnapshot().status, 'signedOut');
  f.controller.stop();
});

test('logout during a pending password request clears the token after that request resolves', async () => {
  const login = deferred<AuthSession>();
  const f = fixture(); f.auth.signIn = () => login.promise;
  f.controller.start(); await tick();
  const signingIn = f.controller.signIn('a@example.invalid', 'fictional');
  await tick();
  const signingOut = f.controller.signOut();
  login.resolve(session('late'));
  await Promise.all([signingIn, signingOut]);
  assert.equal(f.cleared(), 1);
  assert.equal(f.controller.getSnapshot().context, null);
  assert.equal(f.controller.getSnapshot().status, 'signedOut');
  f.controller.stop();
});

test('offline logout clears secure storage and allows reconnecting without a false cleanup error', async () => {
  const f = fixture(); f.auth.signOut = async () => { throw new Error('network offline'); };
  f.controller.start(); await tick(); await f.controller.signIn('a@example.invalid', 'fictional');
  await f.controller.signOut();
  assert.equal(f.cleared(), 1);
  assert.equal(f.controller.getSnapshot().context, null);
  assert.equal(f.controller.getSnapshot().status, 'signedOut');
  assert.equal(f.controller.getSnapshot().error, null);
  await f.controller.signIn('a@example.invalid', 'fictional');
  assert.equal(f.controller.getSnapshot().status, 'authenticated');
  assert.equal(f.controller.getSnapshot().context?.userId, 'first');
  f.controller.stop();
});

test('only a local secure cleanup failure requires retrying logout', async () => {
  const f = fixture();
  const clearStorage = f.auth.clearStorage;
  f.auth.clearStorage = async () => { throw new Error('keychain unavailable'); };
  f.controller.start(); await tick(); await f.controller.signIn('a@example.invalid', 'fictional');
  await f.controller.signOut();
  assert.equal(f.controller.getSnapshot().status, 'signedOut');
  assert.equal(f.controller.getSnapshot().context, null);
  assert.match(f.controller.getSnapshot().error!, /effacement sécurisé/);
  f.auth.clearStorage = clearStorage;
  await f.controller.signOut();
  assert.equal(f.cleared(), 1);
  assert.equal(f.controller.getSnapshot().error, null);
  f.controller.stop();
});

test('unsupported role fails closed with a useful message, network errors do not look like unsupported roles', async () => {
  for (const rejected of [new UnsupportedNativeAccount('Ce compte appartient à un établissement.'), new Error('network offline')]) {
    const f = fixture(async () => { throw rejected; });
    f.controller.start(); await tick(); await f.controller.signIn('a@example.invalid', 'fictional');
    assert.equal(f.controller.getSnapshot().context, null);
    assert.equal(f.controller.getSnapshot().status, rejected instanceof UnsupportedNativeAccount ? 'unsupported' : 'error');
    f.controller.stop();
  }
});

test('role revalidation on resume blocks revoked access without retaining previous data', async () => {
  let revoked = false;
  const f = fixture(async (value) => {
    if (revoked) throw new UnsupportedNativeAccount('Accès non disponible.');
    return context(value.user.id);
  });
  f.controller.start(); await tick(); await f.controller.signIn('a@example.invalid', 'fictional');
  revoked = true; await f.controller.revalidate();
  assert.equal(f.controller.getSnapshot().status, 'unsupported');
  assert.equal(f.controller.getSnapshot().context, null);
  f.controller.stop();
});

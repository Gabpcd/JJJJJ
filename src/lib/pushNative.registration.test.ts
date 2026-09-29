import { afterEach, beforeEach, expect, it, vi } from 'vitest';
const m = vi.hoisted(() => ({ permission: 'granted', listeners: new Map<string, Function>(), rpc: vi.fn(), session: vi.fn() }));
vi.mock('./platform', () => ({ isNative: () => true }));
vi.mock('@capacitor/core', () => ({ Capacitor: { getPlatform: () => 'ios' } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { auth: { getSession: m.session }, rpc: m.rpc } }));
vi.mock('@capacitor/push-notifications', () => ({ PushNotifications: {
  checkPermissions: async () => ({ receive: m.permission }), requestPermissions: async () => ({ receive: m.permission }),
  removeAllListeners: async () => m.listeners.clear(),
  addListener: async (name: string, callback: Function) => { m.listeners.set(name, callback); return { remove: async () => m.listeners.delete(name) }; },
  register: async () => { m.listeners.get('registration')?.({ value: 'fixture-apns-token' }); },
} }));
beforeEach(() => { vi.resetModules(); m.permission = 'granted'; m.rpc.mockReset().mockResolvedValue({ error: null }); m.session.mockResolvedValue({ data: { session: { user: { id: 'user' } } } }); localStorage.clear(); });
afterEach(() => vi.clearAllMocks());
it('does not report push enabled when server registration fails despite granted permission', async () => {
  m.rpc.mockResolvedValue({ error: new Error('Offline') });
  const push = await import('./pushNative');
  await expect(push.demanderPermissionNativePush('user')).rejects.toThrow('Impossible de confirmer');
  expect(push.enregistrementPushConfirme('user')).toBe(false);
  expect(localStorage.getItem('jolene.push.current-device-token.v1')).toBeNull();
  m.rpc.mockResolvedValue({ error: null });
  await expect(push.demanderPermissionNativePush('user')).resolves.toBe(true);
  expect(push.enregistrementPushConfirme('user')).toBe(true);
});
it('retries after permission is granted in system settings without showing another prompt', async () => {
  const push = await import('./pushNative'); m.permission = 'denied';
  await push.initNativePush('user'); expect(m.rpc).not.toHaveBeenCalled();
  m.permission = 'granted'; await push.initNativePush('user', { actualiser: true });
  expect(push.enregistrementPushConfirme('user')).toBe(true);
  expect(m.rpc).toHaveBeenCalledWith('fn_upsert_token_push', { p_token: 'fixture-apns-token', p_plateforme: 'IOS' });
});
it('does not register a token for a stale session', async () => {
  const push = await import('./pushNative'); m.session.mockResolvedValue({ data: { session: { user: { id: 'other-user' } } } });
  await push.initNativePush('user'); expect(m.rpc).not.toHaveBeenCalled(); expect(push.enregistrementPushConfirme('user')).toBe(false);
});

it('preserves action listeners on an ordinary resume with an already registered device', async () => {
  const push = await import('./pushNative');
  await push.initNativePush('user');
  const action = m.listeners.get('pushNotificationActionPerformed');
  expect(action).toBeTypeOf('function');
  await push.initNativePush('user', { actualiser: true });
  expect(m.listeners.get('pushNotificationActionPerformed')).toBe(action);
  expect(m.rpc).toHaveBeenCalledTimes(1);
  m.permission = 'denied';
  await push.initNativePush('user', { actualiser: true });
  expect(push.enregistrementPushConfirme('user')).toBe(false);
});

it('retries a failed later token rotation instead of keeping a stale confirmation', async () => {
  const push = await import('./pushNative');
  await push.initNativePush('user');
  m.rpc.mockResolvedValue({ error: new Error('Offline during rotation') });
  m.listeners.get('registration')?.({ value: 'rotated-fixture-token' });
  await vi.waitFor(() => expect(push.enregistrementPushConfirme('user')).toBe(false));
  m.rpc.mockResolvedValue({ error: null });
  await push.initNativePush('user', { actualiser: true });
  expect(push.enregistrementPushConfirme('user')).toBe(true);
});

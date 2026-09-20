import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { generateKeyPairSync, sign, webcrypto } from 'node:crypto';
import type { MobileUpdate } from './mobileUpdates';

const mocks = vi.hoisted(() => ({
  native: vi.fn(() => true), plugin: vi.fn(() => true), get: vi.fn(), info: vi.fn(),
  ready: vi.fn(), current: vi.fn(), next: vi.fn(), blocked: vi.fn(), downloaded: vi.fn(),
  download: vi.fn(), setNext: vi.fn(),
}));
vi.mock('@capacitor/core', () => ({
  Capacitor: { isNativePlatform: mocks.native, isPluginAvailable: mocks.plugin }, CapacitorHttp: { get: mocks.get },
}));
vi.mock('@capacitor/app', () => ({ App: { getInfo: mocks.info } }));
vi.mock('@capawesome/capacitor-live-update', () => ({ LiveUpdate: {
  ready: mocks.ready, getCurrentBundle: mocks.current, getNextBundle: mocks.next,
  getBlockedBundles: mocks.blocked, getDownloadedBundles: mocks.downloaded,
  downloadBundle: mocks.download, setNextBundle: mocks.setNext,
} }));
const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicKey = keys.publicKey.export({ type: 'spki', format: 'pem' }).toString();
vi.mock('../../config/mobile-update-public.pem?raw', () => ({ default: publicKey }));
const native = { id: 'app.jolene', version: '1.0.3', build: '20' };
const id = 'a'.repeat(40);
const update: MobileUpdate = {
  schema: 1, appId: native.id, nativeVersion: native.version, nativeBuild: native.build, id,
  url: `https://github.com/Gabpcd/JJJJJ/releases/download/mobile-ota-20/${id}.zip`,
  checksum: 'b'.repeat(64), signature: Buffer.alloc(256, 1).toString('base64'),
};
function envelope(value: unknown = update) {
  const payload = JSON.stringify(value);
  return { payload, signature: sign('sha256', Buffer.from(payload), keys.privateKey).toString('base64') };
}
beforeAll(() => {
  vi.stubGlobal('crypto', webcrypto);
  vi.stubGlobal('__APP_VERSION__', '12345678');
});
beforeEach(() => {
  vi.resetModules(); vi.clearAllMocks();
  mocks.native.mockReturnValue(true); mocks.plugin.mockReturnValue(true);
  mocks.info.mockResolvedValue(native); mocks.get.mockResolvedValue({ status: 200, data: envelope() });
  mocks.current.mockResolvedValue({ bundleId: null }); mocks.next.mockResolvedValue({ bundleId: null });
  mocks.blocked.mockResolvedValue({ bundleIds: [] }); mocks.downloaded.mockResolvedValue({ bundleIds: [] });
  mocks.download.mockResolvedValue(undefined);
});
describe('signed mobile updates', () => {
  it('accepts an authentic update for exactly the installed app and runtime', async () => {
    const { verifyMobileUpdate } = await import('./mobileUpdates');
    expect(await verifyMobileUpdate(envelope(), native, publicKey)).toEqual(update);
  });
  it('rejects a tampered envelope before trusting its compatibility fields', async () => {
    const { verifyMobileUpdate } = await import('./mobileUpdates');
    expect(await verifyMobileUpdate({ ...envelope(), payload: JSON.stringify({ ...update, nativeBuild: '21' }) }, native, publicKey)).toBeNull();
  });
  it.each([
    { nativeBuild: '19' }, { nativeVersion: '1.0.2' }, { appId: 'other.app' },
    { url: 'https://untrusted.example/update.zip' }, { checksum: 'wrong' }, { schema: 2 },
  ])('rejects signed but incompatible or invalid metadata: %j', async (change) => {
    const { verifyMobileUpdate } = await import('./mobileUpdates');
    expect(await verifyMobileUpdate(envelope({ ...update, ...change }), native, publicKey)).toBeNull();
  });
  it('marks startup healthy, downloads once and schedules only the next cold start', async () => {
    const { prepareMobileUpdate } = await import('./mobileUpdates');
    await prepareMobileUpdate(); await prepareMobileUpdate();
    expect(mocks.ready).toHaveBeenCalledOnce();
    expect(mocks.ready.mock.invocationCallOrder[0]).toBeLessThan(mocks.get.mock.invocationCallOrder[0]);
    expect(mocks.download).toHaveBeenCalledExactlyOnceWith({ bundleId: id, url: update.url, checksum: update.checksum, signature: update.signature });
    expect(mocks.setNext).toHaveBeenCalledExactlyOnceWith({ bundleId: id });
  });
  it('never installs a bundle that the native rollback has blocked', async () => {
    mocks.blocked.mockResolvedValue({ bundleIds: [id] });
    await (await import('./mobileUpdates')).prepareMobileUpdate();
    expect(mocks.download).not.toHaveBeenCalled(); expect(mocks.setNext).not.toHaveBeenCalled();
  });
  it('does not schedule an archive when native signature verification fails', async () => {
    mocks.download.mockRejectedValue(new Error('Signature rejected'));
    await expect((await import('./mobileUpdates')).prepareMobileUpdate()).rejects.toThrow('Signature rejected');
    expect(mocks.setNext).not.toHaveBeenCalled();
  });
  it('does no update work in the browser', async () => {
    mocks.native.mockReturnValue(false);
    await (await import('./mobileUpdates')).prepareMobileUpdate();
    expect(mocks.ready).not.toHaveBeenCalled(); expect(mocks.get).not.toHaveBeenCalled();
  });
  it('leaves the embedded app usable when no release exists', async () => {
    mocks.get.mockResolvedValue({ status: 404 });
    await (await import('./mobileUpdates')).prepareMobileUpdate();
    expect(mocks.ready).toHaveBeenCalledOnce(); expect(mocks.setNext).not.toHaveBeenCalled();
  });
});

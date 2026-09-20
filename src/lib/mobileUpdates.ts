import { App } from '@capacitor/app';
import { Capacitor, CapacitorHttp } from '@capacitor/core';
import { LiveUpdate } from '@capawesome/capacitor-live-update';
import publicKey from '../../config/mobile-update-public.pem?raw';

declare const __APP_VERSION__: string;
const RELEASES = 'https://github.com/Gabpcd/JJJJJ/releases/download/';

export interface MobileUpdate {
  schema: 1;
  appId: string;
  nativeVersion: string;
  nativeBuild: string;
  id: string;
  url: string;
  checksum: string;
  signature: string;
}

function base64Bytes(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

/** The signed envelope binds the native compatibility to the signed archive. */
export async function verifyMobileUpdate(
  envelope: unknown,
  native: { id: string; version: string; build: string },
  keyPem = publicKey,
): Promise<MobileUpdate | null> {
  if (!envelope || typeof envelope !== 'object') return null;
  const { payload, signature } = envelope as Record<string, unknown>;
  if (typeof payload !== 'string' || payload.length > 8192 || typeof signature !== 'string') return null;
  const key = await crypto.subtle.importKey(
    'spki', base64Bytes(keyPem.replace(/-----[^-]+-----|\s/g, '')),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
  );
  if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, base64Bytes(signature), new TextEncoder().encode(payload))) return null;
  const update = JSON.parse(payload) as MobileUpdate;
  if (update.schema !== 1 || update.appId !== native.id || update.appId !== 'app.jolene'
    || update.nativeVersion !== native.version || update.nativeBuild !== native.build
    || !/^[a-f0-9]{40}$/.test(update.id) || !/^[a-f0-9]{64}$/.test(update.checksum)
    || typeof update.signature !== 'string' || !/^[A-Za-z0-9+/]+=*$/.test(update.signature)
    || update.url !== `${RELEASES}mobile-ota-${native.build}/${update.id}.zip`) return null;
  return update;
}

let started = false;

/** Download in the background; activation is left to the next cold start. */
export async function prepareMobileUpdate(): Promise<void> {
  if (started || !Capacitor.isNativePlatform() || !Capacitor.isPluginAvailable('LiveUpdate')) return;
  started = true;
  await LiveUpdate.ready();
  const native = await App.getInfo();
  const response = await CapacitorHttp.get({
    url: `${RELEASES}mobile-ota-${native.build}/manifest.json`,
    connectTimeout: 5000, readTimeout: 10000,
    headers: { Accept: 'application/json', 'Cache-Control': 'no-cache' },
  });
  if (response.status !== 200) return;
  const update = await verifyMobileUpdate(typeof response.data === 'string' ? JSON.parse(response.data) : response.data, native);
  if (!update) return;
  const [current, next, blocked, downloaded] = await Promise.all([
    LiveUpdate.getCurrentBundle(), LiveUpdate.getNextBundle(),
    LiveUpdate.getBlockedBundles(), LiveUpdate.getDownloadedBundles(),
  ]);
  if (current.bundleId === update.id || next.bundleId === update.id || blocked.bundleIds.includes(update.id)
    || (!current.bundleId && update.id.startsWith(__APP_VERSION__))) return;
  if (!downloaded.bundleIds.includes(update.id)) {
    await LiveUpdate.downloadBundle({ bundleId: update.id, url: update.url, checksum: update.checksum, signature: update.signature });
  }
  await LiveUpdate.setNextBundle({ bundleId: update.id });
}

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { createSecureSessionStorage, type SecureKeyValueStore } from './secureSessionStorage';

const hash = async (value: string) => createHash('sha256').update(value).digest('hex');
function fixture() {
  const values = new Map<string, string>();
  let fail: ((key: string, value?: string) => boolean) | null = null;
  const raw: SecureKeyValueStore = {
    async getItem(key) { return values.get(key) ?? null; },
    async setItem(key, value) { if (fail?.(key, value)) throw new Error('storage unavailable'); values.set(key, value); },
    async removeItem(key) { if (fail?.(key)) throw new Error('storage unavailable'); values.delete(key); },
  };
  return { values, raw, storage: createSecureSessionStorage(raw, hash), setFailure: (value: typeof fail) => { fail = value; } };
}

test('long Unicode session survives a fresh adapter and each native item stays below 2048 bytes', async () => {
  const f = fixture();
  const value = JSON.stringify({ text: 'é🩺'.repeat(2500) });
  await f.storage.setItem('auth', value);
  assert.equal(await createSecureSessionStorage(f.raw, hash).getItem('auth'), value);
  for (const stored of f.values.values()) assert.ok(Buffer.byteLength(stored) < 2048);
});

test('partial token refresh does not replace the previously committed session', async () => {
  const f = fixture();
  await f.storage.setItem('auth', 'original session');
  f.setFailure((key) => key.endsWith('.b.1'));
  await assert.rejects(f.storage.setItem('auth', 'new session '.repeat(200)));
  assert.equal(await createSecureSessionStorage(f.raw, hash).getItem('auth'), 'original session');
});

test('failed atomic head commit keeps the old token intact', async () => {
  const f = fixture();
  await f.storage.setItem('auth', 'original session');
  f.setFailure((key) => key.endsWith('.head'));
  await assert.rejects(f.storage.setItem('auth', 'replacement session'));
  assert.equal(await f.storage.getItem('auth'), 'original session');
});

test('missing or altered chunk invalidates the whole session', async () => {
  for (const corrupt of ['missing', 'altered']) {
    const f = fixture();
    await f.storage.setItem('auth', 'stored session '.repeat(100));
    if (corrupt === 'missing') f.values.delete('jolene.native.auth.a.1');
    else f.values.set('jolene.native.auth.a.1', 'another value');
    assert.equal(await f.storage.getItem('auth'), null);
    assert.equal(await createSecureSessionStorage(f.raw, hash).getItem('auth'), null);
  }
});

test('malformed manifest fails closed without allocating unbounded chunks', async () => {
  const f = fixture();
  f.values.set('jolene.native.auth.head', JSON.stringify({ version: 1, slot: 'a', count: 1e9, digest: 'a'.repeat(64) }));
  assert.equal(await f.storage.getItem('auth'), null);
});

test('logout tombstone survives interrupted chunk cleanup and a fresh adapter', async () => {
  const f = fixture();
  await f.storage.setItem('auth', 'stored session');
  f.setFailure((key) => key.endsWith('.a.0'));
  await assert.rejects(f.storage.removeItem('auth'));
  assert.equal(await createSecureSessionStorage(f.raw, hash).getItem('auth'), null);
});

test('logout queued after a token write cannot be undone by that write', async () => {
  const f = fixture();
  const write = f.storage.setItem('auth', 'session '.repeat(300));
  const logout = f.storage.removeItem('auth');
  await Promise.all([write, logout]);
  assert.equal(await createSecureSessionStorage(f.raw, hash).getItem('auth'), null);
});

test('failed persisted logout is reported and in-memory access is denied', async () => {
  const f = fixture();
  await f.storage.setItem('auth', 'stored session');
  f.setFailure((key) => key.endsWith('.head'));
  await assert.rejects(f.storage.removeItem('auth'));
  assert.equal(await f.storage.getItem('auth'), null);
});

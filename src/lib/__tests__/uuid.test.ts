import { webcrypto } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { creerUuidV4 } from '../uuid';

const formatV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('UUID v4 sécurisé sur navigateurs récents et iOS ancien', () => {
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it('privilégie randomUUID natif en préservant son objet crypto', () => {
    const getRandomValues = vi.fn();
    const randomUUID = vi.fn(function (this: Crypto) {
      expect(this).toBe(globalThis.crypto);
      return webcrypto.randomUUID();
    });
    vi.stubGlobal('crypto', { randomUUID, getRandomValues });
    expect(creerUuidV4()).toMatch(formatV4);
    expect(randomUUID).toHaveBeenCalledTimes(1);
    expect(getRandomValues).not.toHaveBeenCalled();
  });

  it('sans randomUUID, garde les octets sécurisés et impose version 4 et variante RFC', () => {
    const getRandomValues = vi.fn((octets: Uint8Array) => octets.fill(0xff));
    const aleaNonSecurise = vi.spyOn(Math, 'random').mockImplementation(() => { throw new Error('Aléa non sécurisé interdit'); });
    vi.stubGlobal('crypto', { getRandomValues });
    expect(creerUuidV4()).toBe('ffffffff-ffff-4fff-bfff-ffffffffffff');
    expect(getRandomValues).toHaveBeenCalledTimes(1);
    expect(getRandomValues.mock.calls[0][0]).toHaveLength(16);
    expect(aleaNonSecurise).not.toHaveBeenCalled();
  });

  it('demande de nouveaux octets cryptographiques à chaque identifiant', () => {
    const getRandomValues = vi.fn((octets: Uint8Array) => webcrypto.getRandomValues(octets));
    vi.stubGlobal('crypto', { getRandomValues });
    const ids = Array.from({ length: 20 }, () => creerUuidV4());
    expect(new Set(ids).size).toBe(20);
    for (const id of ids) expect(id).toMatch(formatV4);
    expect(getRandomValues).toHaveBeenCalledTimes(20);
  });

  it('échoue si aucune source cryptographique n’est disponible, sans repli Math.random', () => {
    const aleaNonSecurise = vi.spyOn(Math, 'random');
    vi.stubGlobal('crypto', {});
    expect(() => creerUuidV4()).toThrow();
    expect(aleaNonSecurise).not.toHaveBeenCalled();
  });
});

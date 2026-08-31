import { describe, expect, it, vi } from 'vitest';
import { isChunkLoadError, recoverFromChunkLoadError } from './chunkRecovery';

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  };
}

describe('récupération des chunks après déploiement', () => {
  it.each([
    'Importing a module script failed.',
    'Failed to fetch dynamically imported module: /assets/PageAdmin-old.js',
    'Error loading dynamically imported module',
    'Loading chunk 42 failed',
  ])('reconnaît le message navigateur « %s »', (message) => {
    expect(isChunkLoadError(new TypeError(message))).toBe(true);
  });

  it('ne transforme pas une erreur applicative en reload', () => {
    expect(isChunkLoadError(new TypeError('Cannot read properties of undefined'))).toBe(false);
  });

  it('recharge une fois par release sans boucle', () => {
    const storage = memoryStorage();
    const reload = vi.fn();
    const error = new TypeError('Importing a module script failed.');

    expect(recoverFromChunkLoadError(error, {
      release: 'release-a', storage, reload, now: 1_000,
    })).toBe(true);
    expect(recoverFromChunkLoadError(error, {
      release: 'release-a', storage, reload, now: 2_000,
    })).toBe(false);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('autorise la récupération de la release suivante', () => {
    const storage = memoryStorage();
    const reload = vi.fn();
    const error = new TypeError('Importing a module script failed.');

    recoverFromChunkLoadError(error, {
      release: 'release-a', storage, reload, now: 1_000,
    });
    expect(recoverFromChunkLoadError(error, {
      release: 'release-b', storage, reload, now: 2_000,
    })).toBe(true);
    expect(reload).toHaveBeenCalledTimes(2);
  });

  it('annule le défaut Vite juste avant le reload', () => {
    const storage = memoryStorage();
    const beforeReload = vi.fn();
    const reload = vi.fn();

    recoverFromChunkLoadError(new Error('modulepreload failed'), {
      release: 'release-a', storage, beforeReload, reload, now: 1_000,
    });

    expect(beforeReload).toHaveBeenCalledOnce();
    expect(beforeReload.mock.invocationCallOrder[0]).toBeLessThan(
      reload.mock.invocationCallOrder[0],
    );
  });
});

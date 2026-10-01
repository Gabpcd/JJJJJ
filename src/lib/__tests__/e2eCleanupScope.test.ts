import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  CLEANUP_DEADLINE_MS, executerNettoyageBorne, fetchAvecBorneNettoyage,
} from '../../../e2e/helpers/cleanup-scope';

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });
const URL_FIXTURE = 'https://fixture.invalid/rest/v1/missions?id=eq.uuid-technique';

function transportBloque() {
  let active = 0;
  let maximum = 0;
  const transport = vi.fn((_input: unknown, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
    active += 1; maximum = Math.max(maximum, active);
    const stop = () => { active -= 1; reject(init?.signal?.reason); };
    if (init?.signal?.aborted) stop();
    else init?.signal?.addEventListener('abort', stop, { once: true });
  }));
  vi.stubGlobal('fetch', transport);
  return { transport, active: () => active, maximum: () => maximum };
}

describe('nettoyage E2E borné, sans réseau', () => {
  it('ne modifie aucun appel hors nettoyage et conserve le résultat normal', async () => {
    const response = new Response('[]');
    const transport = vi.fn().mockResolvedValue(response);
    vi.stubGlobal('fetch', transport);
    const init = { method: 'GET', headers: { authorization: 'fixture' } };
    expect(await fetchAvecBorneNettoyage(URL_FIXTURE, init)).toBe(response);
    expect(transport).toHaveBeenCalledWith(URL_FIXTURE, init);
    expect(await executerNettoyageBorne('normal', async () => {
      const received = await fetchAvecBorneNettoyage(URL_FIXTURE, init);
      return received.json();
    })).toEqual([]);
    expect(transport.mock.calls[1][1]).toMatchObject(init);
  });

  it('annule la requête suspendue avant le hook et refuse toute requête suivante', async () => {
    vi.useFakeTimers();
    const state = transportBloque();
    const cleanup = executerNettoyageBorne('afterEach', async () => {
      try { await fetchAvecBorneNettoyage(URL_FIXTURE, { method: 'DELETE' }); } catch { /* collecte du nettoyeur */ }
      await fetchAvecBorneNettoyage('https://fixture.invalid/auth/v1/admin/users/uuid-secret', { method: 'DELETE' });
    });
    const failure = expect(cleanup).rejects.toThrow(
      '[cleanup] afterEach: délai 25000 ms atteint ; dernière requête DELETE /rest/v1/missions',
    );
    await vi.advanceTimersByTimeAsync(CLEANUP_DEADLINE_MS);
    await failure;
    expect(state.active()).toBe(0);
    expect(state.transport).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
    // Reprise explicite seulement après résolution du premier nettoyage.
    state.transport.mockResolvedValueOnce(new Response('[]'));
    await executerNettoyageBorne('afterAll', () => fetchAvecBorneNettoyage(URL_FIXTURE));
    expect(state.maximum()).toBe(1);
  });

  it('garde le signal actif pendant la lecture du corps après les en-têtes', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('fetch', vi.fn((_input, init: RequestInit) => Promise.resolve({
      json: () => new Promise((_resolve, reject) => {
        init.signal?.addEventListener('abort', () => reject(init.signal?.reason), { once: true });
      }),
    })));
    const cleanup = executerNettoyageBorne('corps', async () => {
      const response = await fetchAvecBorneNettoyage(URL_FIXTURE);
      return response.json();
    });
    const failure = expect(cleanup).rejects.toThrow('dernière requête GET /rest/v1/missions');
    await vi.advanceTimersByTimeAsync(CLEANUP_DEADLINE_MS);
    await failure;
  });

  it('préserve le signal propre du RPC et son erreur sans attendre la borne', async () => {
    vi.useFakeTimers();
    const state = transportBloque();
    const controller = new AbortController();
    const reason = new Error('borne RPC existante');
    const cleanup = executerNettoyageBorne('rpc', () => fetchAvecBorneNettoyage(
      'https://fixture.invalid/rest/v1/rpc/fn_test_purge_mission', { signal: controller.signal },
    ));
    const failure = expect(cleanup).rejects.toBe(reason);
    controller.abort(reason);
    await failure;
    expect(state.active()).toBe(0); expect(vi.getTimerCount()).toBe(0);
  });

  it('ne transforme pas un refus SQL en succès ni en erreur de délai', async () => {
    vi.useFakeTimers();
    const sqlFailure = new Error('23514: fixture non technique');
    await expect(executerNettoyageBorne('sql', async () => { throw sqlFailure; })).rejects.toBe(sqlFailure);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('une sous-opération ne renouvelle pas les 25 secondes du nettoyage', async () => {
    vi.useFakeTimers(); transportBloque();
    const cleanup = executerNettoyageBorne('parent', async () => {
      await new Promise((resolve) => setTimeout(resolve, 20_000));
      return executerNettoyageBorne('enfant', () => fetchAvecBorneNettoyage(URL_FIXTURE));
    });
    const failure = expect(cleanup).rejects.toThrow('[cleanup] parent: délai 25000 ms');
    await vi.advanceTimersByTimeAsync(CLEANUP_DEADLINE_MS);
    await failure;
    expect(vi.getTimerCount()).toBe(0);
  });

  it('ne contamine pas une autre chaîne asynchrone hors nettoyage', async () => {
    vi.useFakeTimers();
    const state = transportBloque();
    const cleanup = executerNettoyageBorne('lent', () => fetchAvecBorneNettoyage(URL_FIXTURE));
    const failure = expect(cleanup).rejects.toThrow('délai 25000 ms');
    state.transport.mockResolvedValueOnce(new Response('ok'));
    const init = { method: 'GET' };
    await fetchAvecBorneNettoyage('https://fixture.invalid/rest/v1/autre', init);
    expect(state.transport.mock.calls[1][1]).toBe(init);
    await vi.advanceTimersByTimeAsync(CLEANUP_DEADLINE_MS); await failure;
  });
});

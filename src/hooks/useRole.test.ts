import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ROLE_RESOLUTION_TIMEOUT_MS, useRole } from './useRole';

const mocks = vi.hoisted(() => ({
  getSession: vi.fn(),
  rpc: vi.fn(),
  onAuthStateChange: vi.fn(),
  unsubscribe: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      getSession: mocks.getSession,
      onAuthStateChange: mocks.onAuthStateChange,
    },
    rpc: mocks.rpc,
  },
}));

function requeteRpc(response: unknown) {
  const promise = Promise.resolve(response);
  const builder: any = {
    abortSignal: vi.fn(() => builder),
    then: promise.then.bind(promise),
  };
  return builder;
}

function requeteRpcSuspendue() {
  const promise = new Promise<never>(() => {});
  const builder: any = {
    abortSignal: vi.fn(() => builder),
    then: promise.then.bind(promise),
  };
  return builder;
}

describe('useRole — résolution fail-closed', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getSession.mockResolvedValue({
      data: { session: { user: { id: 'utilisateur-id' } } },
      error: null,
    });
    mocks.onAuthStateChange.mockReturnValue({
      data: { subscription: { unsubscribe: mocks.unsubscribe } },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('expose uniquement un scope explicitement résolu par la RPC', async () => {
    const query = requeteRpc({
      data: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'etablissement-id' },
      error: null,
    });
    mocks.rpc.mockReturnValue(query);

    const { result } = renderHook(() => useRole());

    await waitFor(() => expect(result.current.resolved).toBe(true));
    expect(result.current).toMatchObject({
      role: 'ADMIN_ETABLISSEMENT',
      etablissement_id: 'etablissement-id',
      loading: false,
      error: null,
    });
    expect(query.abortSignal).toHaveBeenCalledWith(expect.any(AbortSignal));
  });

  it('expose l’erreur RPC sans considérer le rôle comme résolu', async () => {
    mocks.rpc.mockReturnValue(requeteRpc({
      data: null,
      error: { message: 'service indisponible' },
    }));

    const { result } = renderHook(() => useRole());

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.resolved).toBe(false);
    expect(result.current.etablissement_id).toBeNull();
    expect(result.current.role).toBe('INCONNU');
    expect(result.current.error?.message).toBe('service indisponible');
  });

  it('borne la RPC suspendue, l’annule et permet une relance', async () => {
    vi.useFakeTimers();
    const querySuspendue = requeteRpcSuspendue();
    const queryReussie = requeteRpc({
      data: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: 'etablissement-retry' },
      error: null,
    });
    mocks.rpc
      .mockReturnValueOnce(querySuspendue)
      .mockReturnValueOnce(queryReussie);

    const { result } = renderHook(() => useRole());

    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(ROLE_RESOLUTION_TIMEOUT_MS);
    });
    expect(result.current.loading).toBe(false);
    expect(result.current.resolved).toBe(false);
    expect(result.current.error?.message).toContain('expiré');
    expect(querySuspendue.abortSignal).toHaveBeenCalledTimes(1);
    expect(querySuspendue.abortSignal.mock.calls[0][0].aborted).toBe(true);

    await act(async () => {
      result.current.retry();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(result.current).toMatchObject({
      resolved: true,
      etablissement_id: 'etablissement-retry',
      error: null,
    });
  });
});

import { renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ADMIN_ACCESS } from '@/lib/adminAccess';
import { useAccesAdmin } from './useAccesAdmin';

const rpcState = vi.hoisted(() => ({
  result: { data: null as unknown, error: null as unknown },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: vi.fn(async () => rpcState.result),
  },
}));

describe('useAccesAdmin', () => {
  beforeEach(() => {
    rpcState.result = { data: null, error: null };
  });

  it('échoue fermé quand la vérification RPC échoue', async () => {
    rpcState.result = { data: null, error: { message: 'forbidden' } };

    const { result } = renderHook(() => useAccesAdmin());

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.accesTotal).toBe(false);
    expect(result.current.groupes).toEqual([]);
    expect(result.current.aAcces(ADMIN_ACCESS.DASHBOARD)).toBe(false);
  });

  it('n’ouvre les routes qu’après une réponse serveur explicite', async () => {
    rpcState.result = {
      data: { acces_total: true, groupes: [], actif: true, mode_lancement: true },
      error: null,
    };

    const { result } = renderHook(() => useAccesAdmin());

    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.accesTotal).toBe(true);
    expect(result.current.aAcces(ADMIN_ACCESS.FINANCES)).toBe(true);
  });
});

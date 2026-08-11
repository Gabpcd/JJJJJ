import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useTypesExerciceAutorises } from './useTypesExerciceAutorises';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
}));

describe('useTypesExerciceAutorises', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('distingue une indisponibilité du référentiel d’une interdiction métier', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: 'service indisponible' } });

    const { result } = renderHook(() => useTypesExerciceAutorises('IDE'));

    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current).toMatchObject({
      typesAutorises: null,
      uniqueType: null,
      indisponible: true,
    });
  });

  it('expose les types uniquement après une réponse valide', async () => {
    mocks.rpc.mockResolvedValue({ data: ['SALARIE', 'LIBERAL'], error: null });

    const { result } = renderHook(() => useTypesExerciceAutorises('IDE'));

    await waitFor(() => expect(result.current.typesAutorises).toEqual(['SALARIE', 'LIBERAL']));
    expect(result.current.indisponible).toBe(false);
    expect(result.current.uniqueType).toBeNull();
  });

  it('ignore une réponse tardive de l’ancienne profession', async () => {
    let resoudreIde: ((value: unknown) => void) | undefined;
    const ideSuspendu = new Promise(resolve => {
      resoudreIde = resolve;
    });
    mocks.rpc
      .mockReturnValueOnce(ideSuspendu)
      .mockResolvedValueOnce({ data: ['SALARIE'], error: null });

    const { result, rerender } = renderHook(
      ({ profession }) => useTypesExerciceAutorises(profession),
      { initialProps: { profession: 'IDE' } },
    );

    rerender({ profession: 'AS' });
    await waitFor(() => expect(result.current.uniqueType).toBe('SALARIE'));

    await act(async () => {
      resoudreIde?.({ data: ['LIBERAL'], error: null });
      await Promise.resolve();
    });

    expect(result.current.typesAutorises).toEqual(['SALARIE']);
    expect(result.current.uniqueType).toBe('SALARIE');
  });
});

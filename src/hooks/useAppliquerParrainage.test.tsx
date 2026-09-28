import { StrictMode } from 'react';
import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useAppliquerParrainage } from './useAppliquerParrainage';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), success: vi.fn(), warning: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('sonner', () => ({ toast: { success: mocks.success, warning: mocks.warning } }));
vi.mock('@/lib/logger', () => ({ logger: { error: vi.fn(), debug: vi.fn() } }));
const codeKey = 'jolene.parrainage_code';
const doneKey = 'jolene.parrainage_appliqué';

describe('attribution du parrainage après connexion', () => {
  beforeEach(() => {
    vi.clearAllMocks(); localStorage.clear(); sessionStorage.clear();
    sessionStorage.setItem(codeKey, 'ABC123');
    mocks.rpc.mockResolvedValue({ data: { success: true }, error: null });
  });

  it('conserve le code après panne puis le réessaie à la reconnexion', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: null, error: { message: 'network' } });
    const { rerender } = renderHook(({ id }) => useAppliquerParrainage(id), { initialProps: { id: 'retry-user' as string | null } });
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(1));
    await act(async () => { await Promise.resolve(); });
    expect(sessionStorage.getItem(codeKey)).toBe('ABC123');
    expect(localStorage.getItem(doneKey)).toBeNull();
    rerender({ id: null }); rerender({ id: 'retry-user' });
    await waitFor(() => expect(mocks.success).toHaveBeenCalledTimes(1));
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(sessionStorage.getItem(codeKey)).toBeNull();
  });

  it('un ancien marqueur global ne bloque pas un autre compte', async () => {
    localStorage.setItem(doneKey, '1');
    renderHook(() => useAppliquerParrainage('second-user'));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(1));
  });

  it('ne relance pas un code terminé sur le même compte mais traite un autre compte', async () => {
    const { rerender } = renderHook(({ id }) => useAppliquerParrainage(id), { initialProps: { id: 'first-user' as string | null } });
    await waitFor(() => expect(mocks.success).toHaveBeenCalledTimes(1));
    sessionStorage.setItem(codeKey, 'ABC123');
    rerender({ id: null }); rerender({ id: 'first-user' });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    rerender({ id: 'other-user' });
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(2));
  });

  it('ne consomme pas un code pour une réponse inconnue ou non authentifiée', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: {}, error: null })
      .mockResolvedValueOnce({ data: { error: 'Non authentifié' }, error: null });
    const { rerender } = renderHook(({ id }) => useAppliquerParrainage(id), { initialProps: { id: 'unknown-user' as string | null } });
    await act(async () => { await Promise.resolve(); });
    expect(sessionStorage.getItem(codeKey)).toBe('ABC123');
    rerender({ id: null }); rerender({ id: 'unknown-user' });
    await act(async () => { await Promise.resolve(); });
    expect(sessionStorage.getItem(codeKey)).toBe('ABC123');
    expect(mocks.success).not.toHaveBeenCalled();
  });

  it('traite un refus métier définitif sans succès et accepte un autre code ensuite', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: { error: 'Code de parrainage invalide' }, error: null });
    const { rerender } = renderHook(({ id }) => useAppliquerParrainage(id), { initialProps: { id: 'invalid-user' as string | null } });
    await waitFor(() => expect(sessionStorage.getItem(codeKey)).toBeNull());
    expect(mocks.success).not.toHaveBeenCalled();
    sessionStorage.setItem(codeKey, 'NEW456');
    rerender({ id: null }); rerender({ id: 'invalid-user' });
    await waitFor(() => expect(mocks.rpc).toHaveBeenLastCalledWith('fn_appliquer_parrainage', { p_code: 'NEW456' }));
  });

  it('ignore une réponse tardive après changement de compte et conserve le nouveau code', async () => {
    let finish!: (value: unknown) => void;
    mocks.rpc.mockReturnValueOnce(new Promise(resolve => { finish = resolve; }));
    const { rerender } = renderHook(({ id }) => useAppliquerParrainage(id), { initialProps: { id: 'old-user' as string | null } });
    rerender({ id: null }); sessionStorage.setItem(codeKey, 'NEW456');
    await act(async () => { finish({ data: { success: true }, error: null }); });
    expect(sessionStorage.getItem(codeKey)).toBe('NEW456');
    expect(mocks.success).not.toHaveBeenCalled();
  });

  it('ne double pas la requête sous StrictMode', async () => {
    renderHook(() => useAppliquerParrainage('strict-user'), { wrapper: StrictMode });
    await waitFor(() => expect(mocks.success).toHaveBeenCalledTimes(1));
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });

  it('reprend le code d’attribution après réouverture du navigateur', async () => {
    sessionStorage.clear();
    localStorage.setItem('jolene.attribution', JSON.stringify({ ref_code: 'REOPEN', captured_at: new Date().toISOString() }));
    renderHook(() => useAppliquerParrainage('reopen-user'));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_appliquer_parrainage', { p_code: 'REOPEN' }));
  });

  it.each(['2000-01-01T00:00:00.000Z', '2100-01-01T00:00:00.000Z', 'invalide'])('refuse une attribution expirée, future ou illisible : %s', async captured_at => {
    sessionStorage.clear(); localStorage.setItem('jolene.attribution', JSON.stringify({ ref_code: 'OLD', captured_at }));
    renderHook(() => useAppliquerParrainage('dated-user'));
    await act(async () => { await Promise.resolve(); });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
});

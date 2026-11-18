import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useFenetreContestationOuverte } from './useFenetreContestationOuverte';

// Fail-closed de la fenêtre lue au serveur (D12) : chargement, réponse non
// strictement `true`, réponse tardive d'une mission précédente → fermée ; les
// chemins d'échec sont remontés à Sentry (revue B8 de #1141, m1 et m2).

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), capturer: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/lib/sentry', () => ({ capturerErreurSentry: mocks.capturer }));

const VALIDEE = '2026-11-15T10:00:00Z';

type Reponse = { data: unknown; error: unknown };

function differee() {
  let resoudre!: (r: Reponse) => void;
  const promesse = new Promise<Reponse>((r) => { resoudre = r; });
  return { promesse, resoudre };
}

async function vider() {
  await act(async () => { await Promise.resolve(); await Promise.resolve(); });
}

describe('useFenetreContestationOuverte', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.capturer.mockReset();
  });

  it('reste fermée tant que la réponse du serveur n’est pas arrivée', async () => {
    mocks.rpc.mockReturnValue(new Promise(() => {}));
    const { result } = renderHook(() => useFenetreContestationOuverte('mission-1', VALIDEE));
    await vider();
    expect(mocks.rpc).toHaveBeenCalledWith('fn_fenetre_contestation_ouverte', {
      p_type_litige: 'DESACCORD_HEURES_POINTAGE',
      p_mission_id: 'mission-1',
    });
    expect(result.current).toBe(false);
  });

  it('ne s’ouvre que sur un `true` strict', async () => {
    mocks.rpc.mockResolvedValue({ data: true, error: null });
    const ouverte = renderHook(() => useFenetreContestationOuverte('mission-1', VALIDEE));
    await waitFor(() => expect(ouverte.result.current).toBe(true));
    expect(mocks.capturer).not.toHaveBeenCalled();

    for (const data of ['true', 1, null, {}]) {
      mocks.rpc.mockReset();
      mocks.capturer.mockReset();
      mocks.rpc.mockResolvedValue({ data, error: null });
      const { result } = renderHook(() => useFenetreContestationOuverte('mission-1', VALIDEE));
      await waitFor(() => expect(mocks.capturer).toHaveBeenCalledTimes(1));
      expect(result.current).toBe(false);
    }
  });

  it('fenêtre fermée (`false`) : fermée, sans alerte Sentry', async () => {
    mocks.rpc.mockResolvedValue({ data: false, error: null });
    const { result } = renderHook(() => useFenetreContestationOuverte('mission-1', VALIDEE));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalled());
    await vider();
    expect(result.current).toBe(false);
    expect(mocks.capturer).not.toHaveBeenCalled();
  });

  it('erreur ou rejet : fermée et remontée à Sentry', async () => {
    const erreur = { message: 'permission denied for function', code: '42501' };
    mocks.rpc.mockResolvedValue({ data: null, error: erreur });
    const r1 = renderHook(() => useFenetreContestationOuverte('mission-1', VALIDEE));
    await waitFor(() => expect(mocks.capturer).toHaveBeenCalledWith(
      erreur, 'useFenetreContestationOuverte', 'fenetre_contestation'));
    expect(r1.result.current).toBe(false);

    mocks.capturer.mockReset();
    const rejet = new Error('réseau');
    mocks.rpc.mockRejectedValue(rejet);
    const r2 = renderHook(() => useFenetreContestationOuverte('mission-2', VALIDEE));
    await waitFor(() => expect(mocks.capturer).toHaveBeenCalledWith(
      rejet, 'useFenetreContestationOuverte', 'fenetre_contestation'));
    expect(r2.result.current).toBe(false);
  });

  it('ignore la réponse tardive d’une mission précédente', async () => {
    const premiere = differee();
    mocks.rpc.mockReturnValueOnce(premiere.promesse).mockReturnValueOnce(new Promise(() => {}));
    const { result, rerender } = renderHook(
      ({ missionId }) => useFenetreContestationOuverte(missionId, VALIDEE),
      { initialProps: { missionId: 'mission-1' } },
    );
    rerender({ missionId: 'mission-2' });
    await act(async () => { premiere.resoudre({ data: true, error: null }); });
    await vider();
    expect(result.current).toBe(false);
  });

  it('se referme au changement de mission, avant la nouvelle réponse', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: true, error: null }).mockReturnValueOnce(new Promise(() => {}));
    const { result, rerender } = renderHook(
      ({ missionId }) => useFenetreContestationOuverte(missionId, VALIDEE),
      { initialProps: { missionId: 'mission-1' } },
    );
    await waitFor(() => expect(result.current).toBe(true));
    rerender({ missionId: 'mission-2' });
    await vider();
    expect(result.current).toBe(false);
  });

  it('présence non validée : aucun appel, fermée', async () => {
    const { result } = renderHook(() => useFenetreContestationOuverte('mission-1', null));
    await vider();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(result.current).toBe(false);
  });
});

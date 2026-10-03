import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SuiviRemboursementConnectDialog } from './SuiviRemboursementConnectDialog';
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), user: { id: 'owner' } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
const payload = (facture = 'fh', statut = 'REVIEW') => ({ facture_honoraire_id: facture, mission_id: 'mission', checkout_session_id_filtre: null,
  source: 'CONNECT_AVANT_TRANSFERT', visibilite_montants: 'HONORAIRES', paiement_statut: null, lecture_complete: true,
  operations: [{ id: 'op', checkout_session_id: 'cs_test_exacte', statut, montant_honoraires_centimes: 8000, montant_commission_centimes: null,
    montant_total_centimes: null, cree_le: '2026-10-01T12:00:00Z', mis_a_jour_le: null, succeeded_at: '2026-10-01T12:05:00Z', review_code: statut === 'REVIEW' ? 'REFUND_RETURNED_AFTER_SUCCESS' : null }],
});
const query = (reponse: unknown) => ({ abortSignal: () => Promise.resolve(reponse) });
const pendingPayload = () => {
  const suivi = payload('fh', 'PENDING');
  return { ...suivi, operations: suivi.operations.map(op => ({ ...op, succeeded_at: null })) };
};
function pendingQuery(rejectOnAbort = false) {
  let signal!: AbortSignal;
  let resolve!: (value: unknown) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return {
    resolve,
    reject,
    get signal() { return signal; },
    query: {
      abortSignal(received: AbortSignal) {
        signal = received;
        if (rejectOnAbort) signal.addEventListener('abort', () => reject(new DOMException('Lecture annulée', 'AbortError')), { once: true });
        return promise;
      },
    },
  };
}
function ReopenableDialog() {
  const [open, setOpen] = React.useState(true);
  return open
    ? <SuiviRemboursementConnectDialog factureId="fh" onClose={() => setOpen(false)} />
    : <button onClick={() => setOpen(true)}>Ouvrir le suivi</button>;
}
describe('Lecture du suivi Connect dans son interface', () => {
  beforeEach(() => { vi.resetAllMocks(); mocks.user = { id: 'owner' }; });
  afterEach(() => { cleanup(); vi.useRealTimers(); });
  it('réessaie une lecture refusée sans afficher de faux zéro, de succès ancien ou de commission masquée', async () => {
    mocks.rpc.mockReturnValueOnce(query({ data: null, error: { code: '42501' } })).mockReturnValue(query({ data: payload(), error: null }));
    render(<SuiviRemboursementConnectDialog factureId="fh" onClose={vi.fn()} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de vérifier le suivi');
    expect(screen.queryByText(/Aucun remboursement enregistré/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer le suivi' }));
    expect(await screen.findByRole('heading', { name: 'Vérification nécessaire' })).toBeInTheDocument();
    expect(screen.getByText('Honoraires concernés')).toBeInTheDocument();
    expect(screen.queryByText('Commission concernée')).not.toBeInTheDocument();
    expect(screen.queryByText('Montant du remboursement')).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });
  it('ignore une réponse tardive d’une autre facture', async () => {
    let terminer!: (value: unknown) => void;
    mocks.rpc.mockReturnValueOnce({ abortSignal: () => new Promise(resolve => { terminer = resolve; }) })
      .mockReturnValue(query({ data: payload('fh-b'), error: null }));
    const { rerender } = render(<SuiviRemboursementConnectDialog factureId="fh" onClose={vi.fn()} />);
    rerender(<SuiviRemboursementConnectDialog factureId="fh-b" onClose={vi.fn()} />);
    await screen.findByRole('heading', { name: 'Vérification nécessaire' });
    await act(async () => terminer({ data: payload('fh', 'SUCCEEDED'), error: null }));
    expect(screen.getByRole('heading', { name: 'Vérification nécessaire' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
  });
  it('retire les données de la session précédente dès le changement de compte', async () => {
    let terminer!: (value: unknown) => void;
    mocks.rpc.mockReturnValueOnce(query({ data: payload('fh', 'SUCCEEDED'), error: null }))
      .mockReturnValueOnce({ abortSignal: () => new Promise(resolve => { terminer = resolve; }) });
    const { rerender } = render(<SuiviRemboursementConnectDialog factureId="fh" onClose={vi.fn()} />);
    await screen.findByRole('heading', { name: 'Remboursement confirmé' });
    mocks.user = { id: 'autre-compte' };
    rerender(<SuiviRemboursementConnectDialog factureId="fh" onClose={vi.fn()} />);
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
    await act(async () => terminer({ data: null, error: { code: '42501' } }));
    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
    expect(screen.queryByText('Honoraires concernés')).not.toBeInTheDocument();
  });
  it.each(['Fermer le suivi', 'Fermer'])('annule la lecture via « %s » et ignore son rejet après la réouverture de la même facture', async (boutonFermer) => {
    const ancienne = pendingQuery();
    mocks.rpc.mockReturnValueOnce(ancienne.query).mockReturnValueOnce(query({ data: pendingPayload(), error: null }));
    render(<ReopenableDialog />);
    expect(screen.getByRole('status')).toHaveTextContent('Vérification du suivi');
    expect(ancienne.signal.aborted).toBe(false);

    fireEvent.click(screen.getByRole('button', { name: boutonFermer }));
    expect(ancienne.signal.aborted).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir le suivi' }));
    await screen.findByRole('heading', { name: 'Remboursement en cours' });
    await act(async () => ancienne.reject(new DOMException('Ancienne lecture annulée', 'AbortError')));

    expect(screen.getByRole('heading', { name: 'Remboursement en cours' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(screen.queryByText(/Aucun remboursement enregistré/)).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(mocks.rpc).toHaveBeenNthCalledWith(2, 'fn_suivi_remboursements_connect_facture', {
      p_facture_honoraire_id: 'fh', p_checkout_session_id: null,
    });
  });
  it('ne réaffiche pas un ancien succès quand une actualisation se termine après fermeture et réouverture', async () => {
    const actualisation = pendingQuery();
    mocks.rpc.mockReturnValueOnce(query({ data: payload('fh', 'SUCCEEDED'), error: null }))
      .mockReturnValueOnce(actualisation.query)
      .mockReturnValueOnce(query({ data: pendingPayload(), error: null }));
    render(<ReopenableDialog />);
    await screen.findByRole('heading', { name: 'Remboursement confirmé' });
    fireEvent.click(screen.getByRole('button', { name: 'Actualiser le suivi' }));
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('Vérification du suivi');
    fireEvent.click(screen.getByRole('button', { name: 'Fermer le suivi' }));
    expect(actualisation.signal.aborted).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir le suivi' }));
    await screen.findByRole('heading', { name: 'Remboursement en cours' });
    await act(async () => actualisation.resolve({ data: payload('fh', 'SUCCEEDED'), error: null }));

    expect(screen.getByRole('heading', { name: 'Remboursement en cours' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(3);
    for (const call of mocks.rpc.mock.calls) expect(call).toEqual([
      'fn_suivi_remboursements_connect_facture', { p_facture_honoraire_id: 'fh', p_checkout_session_id: null },
    ]);
  });
  it('interrompt une lecture après quinze secondes puis permet une nouvelle lecture sans faux succès ni relance automatique', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    const lente = pendingQuery(true);
    const nouvelle = pendingQuery(true);
    mocks.rpc.mockReturnValueOnce(lente.query).mockReturnValueOnce(nouvelle.query);
    render(<SuiviRemboursementConnectDialog factureId="fh" onClose={vi.fn()} />);

    await act(async () => { await vi.advanceTimersByTimeAsync(14_999); });
    expect(lente.signal.aborted).toBe(false);
    expect(screen.getByRole('status')).toHaveTextContent('Vérification du suivi');
    await act(async () => { await vi.advanceTimersByTimeAsync(1); });
    expect(lente.signal.aborted).toBe(true);
    expect(screen.getByRole('alert')).toHaveTextContent('Impossible de vérifier le suivi');
    expect(screen.queryByText(/Aucun remboursement enregistré/)).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Remboursement confirmé' })).not.toBeInTheDocument();
    await act(async () => { await vi.advanceTimersByTimeAsync(30_000); });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer le suivi' }));
    expect(nouvelle.signal).not.toBe(lente.signal);
    expect(nouvelle.signal.aborted).toBe(false);
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    await act(async () => nouvelle.resolve({ data: pendingPayload(), error: null }));
    expect(screen.getByRole('heading', { name: 'Remboursement en cours' })).toBeInTheDocument();
    await act(async () => { await vi.advanceTimersByTimeAsync(15_000); });
    expect(nouvelle.signal.aborted).toBe(false);
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });
});

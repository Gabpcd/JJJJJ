import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
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
describe('Lecture du suivi Connect dans son interface', () => {
  beforeEach(() => { vi.resetAllMocks(); mocks.user = { id: 'owner' }; });
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
});

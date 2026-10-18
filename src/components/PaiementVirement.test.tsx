import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PaiementVirement } from './PaiementVirement';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), notification: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'membre-fictif' } }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notification }) }));

const facture = {
  id: 'commission-fictive', numero_facture: 'COM-SIM-120', type_document: 'FACTURE', statut: 'EMISE',
  montant_ttc: 120, montant_avoirs_imputes: 40, montant_a_payer: 80, rapprochement_paiement_requis: false,
};
beforeEach(() => { vi.clearAllMocks(); mocks.rpc.mockResolvedValue({ data: { success: true }, error: null }); });

describe('Virement commission — seul le solde canonique peut être réglé', () => {
  it('affiche 80 euros à virer et déclare la référence sans imposer un montant client', async () => {
    const onUpdate = vi.fn();
    render(<PaiementVirement facture={Object.freeze({ ...facture })} onUpdate={onUpdate} />);
    fireEvent.click(screen.getByRole('button', { name: /^Virement$/ }));
    const montant = screen.getByText('Montant à virer :', { exact: true }).parentElement!;
    expect(montant).toHaveTextContent(/80,00\s*€/);
    expect(montant).not.toHaveTextContent(/120,00\s*€/);
    fireEvent.change(screen.getByLabelText('Référence de votre virement'), { target: { value: 'VIR-NET-80' } });
    fireEvent.click(screen.getByRole('button', { name: /J'ai effectué le virement/ }));
    await waitFor(() => expect(onUpdate).toHaveBeenCalledOnce());
    expect(mocks.rpc).toHaveBeenCalledExactlyOnceWith('fn_declarer_virement', { p_facture_id: facture.id, p_reference: 'VIR-NET-80' });
    expect(mocks.notification).toHaveBeenCalledWith(expect.objectContaining({ type: 'succes' }));
    expect(facture.montant_ttc).toBe(120);
    expect(facture.montant_a_payer).toBe(80);
  });

  it.each([
    ['PAYEE externe', { statut: 'PAYEE' }],
    ['soldée par avoir', { statut: 'PAYEE', mode_paiement: 'AVOIR', montant_avoirs_imputes: 120, montant_a_payer: 0 }],
    ['net nul', { montant_avoirs_imputes: 120, montant_a_payer: 0 }],
    ['rapprochement demandé', { rapprochement_paiement_requis: true }],
    ['net absent', { montant_a_payer: undefined }],
    ['avoirs absents', { montant_avoirs_imputes: undefined }],
    ['net incohérent', { montant_a_payer: 120 }],
    ['flag absent', { rapprochement_paiement_requis: undefined }],
  ] as const)('ne propose aucun virement quand %s', (_nom, projection) => {
    const vue = render(<PaiementVirement facture={{ ...facture, ...projection }} onUpdate={vi.fn()} />);
    expect(vue.container).toBeEmptyDOMElement();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.notification).not.toHaveBeenCalled();
  });

  it('retire un formulaire déjà ouvert quand le solde devient à rapprocher', () => {
    const onUpdate = vi.fn();
    const vue = render(<PaiementVirement facture={facture} onUpdate={onUpdate} />);
    fireEvent.click(screen.getByRole('button', { name: /^Virement$/ }));
    fireEvent.change(screen.getByLabelText('Référence de votre virement'), { target: { value: 'VIR-ANCIEN-SOLDE' } });
    vue.rerender(<PaiementVirement facture={{ ...facture, rapprochement_paiement_requis: true }} onUpdate={onUpdate} />);
    expect(screen.queryByRole('button', { name: /J'ai effectué le virement/ })).not.toBeInTheDocument();
    expect(screen.queryByLabelText('Référence de votre virement')).not.toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(onUpdate).not.toHaveBeenCalled();
  });
});

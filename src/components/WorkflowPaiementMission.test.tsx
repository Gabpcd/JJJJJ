import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { WorkflowPaiementMission } from './WorkflowPaiementMission';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  from: vi.fn(),
  rechargerPermissions: vi.fn(),
  permissionError: null as string | null,
}));

vi.mock('@/hooks/useEtabPermissions', () => ({
  useEtabPermissions: () => ({
    loading: false,
    permissions: { lecture_paiement: true, paiement: true },
    error: mocks.permissionError,
    recharger: mocks.rechargerPermissions,
  }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    from: mocks.from,
    storage: { from: vi.fn() },
  },
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({
    children,
    iconeGauche: _iconeGauche,
    iconeDroite: _iconeDroite,
    loading: _loading,
    ...props
  }: React.ButtonHTMLAttributes<HTMLButtonElement> & {
    iconeGauche?: React.ReactNode;
    iconeDroite?: React.ReactNode;
    loading?: boolean;
  }) => <button type="button" {...props}>{children}</button>,
}));

vi.mock('@/components/ui/checkbox', () => ({
  Checkbox: ({ checked, onCheckedChange, ...props }: {
    checked?: boolean;
    onCheckedChange?: (checked: boolean) => void;
  } & Omit<React.InputHTMLAttributes<HTMLInputElement>, 'checked' | 'onChange'>) => (
    <input
      type="checkbox"
      checked={checked}
      onChange={(event) => onCheckedChange?.(event.target.checked)}
      {...props}
    />
  ),
}));

vi.mock('sonner', () => ({
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}));

function queryResponse(data: unknown = [], error: unknown = null) {
  const response = Promise.resolve({ data, error });
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    in: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: vi.fn(() => builder),
    then: response.then.bind(response),
  };
  return builder;
}

const salaryPaymentInfo = {
  mode_recommande: 'VIREMENT_PAIE',
  montant_soignant: 346.85,
  montant_soignant_estime: true,
  commission_ttc: 42,
  total: 388.85,
  iban_last4: '1234',
  type_contrat_applique: 'SALARIE',
};

function renderWorkflow() {
  return render(
    <MemoryRouter>
      <WorkflowPaiementMission
        missionId="mission-salariee"
        soignantAssigneId="soignant-1"
        etablissementId="etablissement-1"
        onStartConnectPay={vi.fn()}
        soignantHasConnect={false}
      />
    </MemoryRouter>,
  );
}

describe('WorkflowPaiementMission — paiement salarié', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.permissionError = null;
    mocks.from.mockImplementation(() => queryResponse());
    mocks.rpc.mockImplementation((name: string) => {
      if (name === 'fn_mode_paiement_mission') {
        return Promise.resolve({ data: salaryPaymentInfo, error: null });
      }
      if (name === 'fn_declarer_paiement_soignant') {
        return Promise.resolve({ data: { success: true }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `RPC inattendue : ${name}` } });
    });
  });

  it('demande le net réel du bulletin et n’envoie jamais automatiquement l’estimation', async () => {
    renderWorkflow();

    expect(await screen.findByText('Virement de rémunération salariée')).toBeInTheDocument();
    expect(screen.getByText(/Estimation indicative avant PAS/i)).toHaveTextContent('346,85');

    const montantInput = screen.getByLabelText(/Montant net réellement versé/i);
    expect(montantInput).toHaveValue(null);
    fireEvent.change(montantInput, { target: { value: '312.47' } });
    fireEvent.change(screen.getByLabelText(/Référence de paiement/i), { target: { value: 'VIR-2026-001' } });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Déclarer le paiement effectué' }));

    await waitFor(() => {
      expect(mocks.rpc).toHaveBeenCalledWith(
        'fn_declarer_paiement_soignant',
        expect.objectContaining({ p_mission_id: 'mission-salariee', p_montant: 312.47 }),
      );
    });
    expect(mocks.rpc).not.toHaveBeenCalledWith(
      'fn_declarer_paiement_soignant',
      expect.objectContaining({ p_montant: 346.85 }),
    );
  });

  it('reste bloqué en cas d’erreur de chargement et permet une relance explicite', async () => {
    let attempts = 0;
    mocks.rpc.mockImplementation((name: string) => {
      if (name !== 'fn_mode_paiement_mission') {
        return Promise.resolve({ data: { success: true }, error: null });
      }
      attempts += 1;
      return attempts === 1
        ? Promise.resolve({ data: null, error: { message: 'réseau indisponible' } })
        : Promise.resolve({ data: salaryPaymentInfo, error: null });
    });

    renderWorkflow();

    expect(await screen.findByRole('alert')).toHaveTextContent('réseau indisponible');
    expect(screen.queryByLabelText(/Montant net réellement versé/i)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));

    expect(await screen.findByLabelText(/Montant net réellement versé/i)).toBeInTheDocument();
    expect(attempts).toBe(2);
  });
});

import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
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

function Location() { const location = useLocation(); return <output data-testid="location">{location.pathname}{location.search}</output>; }
function renderWorkflow(props: Partial<React.ComponentProps<typeof WorkflowPaiementMission>> = {}) {
  return render(
    <MemoryRouter>
      <WorkflowPaiementMission
        missionId="mission-salariee"
        soignantAssigneId="soignant-1"
        etablissementId="etablissement-1"
        {...props}
      />
      <Location />
    </MemoryRouter>,
  );
}

describe('WorkflowPaiementMission — paiement salarié', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.permissionError = null;
    mocks.from.mockImplementation(() => queryResponse());
    mocks.rpc.mockImplementation((name: string) => {
      if (name === 'fn_suivi_escrow_mission') return Promise.resolve({ data: [], error: null });
      if (name === 'fn_mode_paiement_mission') {
        return Promise.resolve({ data: salaryPaymentInfo, error: null });
      }
      if (name === 'fn_declarer_paiement_soignant' || name === 'fn_declarer_paiement_soignant_v2') {
        return Promise.resolve({ data: { success: true }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `RPC inattendue : ${name}` } });
    });
  });

  it('exige le total net du bulletin et refuse un paiement partiel', async () => {
    renderWorkflow();

    expect(await screen.findByText('Virement de rémunération salariée')).toBeInTheDocument();
    expect(screen.getByText(/Estimation indicative avant PAS/i)).toHaveTextContent('346,85');

    const montantDuInput = screen.getByLabelText(/Montant net total dû/i);
    const montantVerseInput = screen.getByLabelText(/Montant réellement versé/i);
    fireEvent.change(montantDuInput, { target: { value: '346.85' } });
    fireEvent.change(montantVerseInput, { target: { value: '312.47' } });
    fireEvent.change(screen.getByLabelText(/Référence de paiement/i), { target: { value: 'VIR-2026-001' } });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Déclarer le paiement effectué' }));

    expect(mocks.rpc).not.toHaveBeenCalledWith(
      'fn_declarer_paiement_soignant_v2',
      expect.anything(),
    );

    fireEvent.change(montantVerseInput, { target: { value: '346.85' } });
    fireEvent.click(screen.getByRole('button', { name: 'Déclarer le paiement effectué' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_declarer_paiement_soignant_v2',
      expect.objectContaining({
        p_mission_id: 'mission-salariee',
        p_montant_verse: 346.85,
        p_montant_total_du: 346.85,
      }),
    ));
  });

  it('reste bloqué en cas d’erreur de chargement et permet une relance explicite', async () => {
    let attempts = 0;
    mocks.rpc.mockImplementation((name: string) => {
      if (name === 'fn_suivi_escrow_mission') return Promise.resolve({ data: [], error: null });
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
    expect(screen.queryByLabelText(/Montant réellement versé/i)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));

    expect(await screen.findByLabelText(/Montant réellement versé/i)).toBeInTheDocument();
    expect(attempts).toBe(2);
  });
  it.each(['DEBITE', 'PAYE', 'REMBOURSE_EN_COURS', 'REMBOURSE'])('ne propose pas de second paiement quand un escrow %s existe', async statut => {
    mocks.rpc.mockImplementation((name: string) => Promise.resolve({ data: name === 'fn_suivi_escrow_mission' ? [{ statut, paye_le: null }] : { ...salaryPaymentInfo, mode_recommande: 'VIREMENT_NOTE_HONORAIRES', type_contrat_applique: 'LIBERAL' }, error: null }));
    renderWorkflow();
    expect(await screen.findByText('Paiement suivi par Jolene')).toBeVisible();
    expect(screen.queryByRole('button', { name: 'Déclarer le paiement effectué' })).not.toBeInTheDocument();
    expect(screen.queryByText(/Honoraires à verser/)).not.toBeInTheDocument();
  });

  it('ne propose pas de paiement si la recherche escrow échoue puis réessaie', async () => {
    let panne = true;
    mocks.rpc.mockImplementation((name: string) => Promise.resolve(name === 'fn_suivi_escrow_mission' ? { data: panne ? null : [], error: panne ? { message: 'Paiement géré indisponible' } : null } : { data: salaryPaymentInfo, error: null }));
    renderWorkflow();
    expect(await screen.findByRole('alert')).toHaveTextContent('Paiement géré indisponible');
    expect(screen.queryByRole('button', { name: 'Déclarer le paiement effectué' })).not.toBeInTheDocument();
    panne = false; fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText('Virement de rémunération salariée')).toBeVisible();
  });

  it.each(['VIREMENT_NOTE_HONORAIRES', 'STRIPE_CONNECT'])('oriente le libéral %s vers une facture, sans transmettre l’estimation', async mode => {
    mocks.rpc.mockImplementation((name: string) => Promise.resolve({ data: name === 'fn_suivi_escrow_mission' ? [] : {
      ...salaryPaymentInfo, type_contrat_applique: 'LIBERAL', mode_recommande: mode, montant_soignant: 160,
    }, error: null }));
    renderWorkflow({ typeContratApplique: 'LIBERAL' });
    fireEvent.click(await screen.findByRole('button', { name: 'Voir les factures de cette mission' }));
    expect(screen.getByTestId('location')).toHaveTextContent('/etablissement/facturation?tab=missions-a-payer&mission=mission-salariee');
    expect(screen.queryByRole('button', { name: /Déclarer|Payer via Stripe/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/160,00/)).not.toBeInTheDocument();
    expect(mocks.rpc.mock.calls.every(([name]) => !name.startsWith('fn_declarer'))).toBe(true);
  });

  it.each([null, {}, { ...salaryPaymentInfo, type_contrat_applique: null }, { ...salaryPaymentInfo, mode_recommande: 'INCONNU' }])('refuse un mode incomplet sans supposer salarié (%j)', async info => {
    mocks.rpc.mockImplementation((name: string) => Promise.resolve({ data: name === 'fn_suivi_escrow_mission' ? [] : info, error: null }));
    renderWorkflow();
    expect(await screen.findByRole('alert')).toHaveTextContent('Paiement indisponible');
    expect(screen.queryByRole('button', { name: /Déclarer|Payer via Stripe/ })).not.toBeInTheDocument();
  });

  it('conserve le paiement historique non lié sans le présenter comme une dette', async () => {
    mocks.from.mockImplementation((name: string) => queryResponse(name === 'paiements_soignant' ? [{ id: 'ancien', statut: 'DECLARE', montant_net: 60, facture_honoraire_id: null }] : []));
    mocks.rpc.mockImplementation((name: string) => Promise.resolve({ data: name === 'fn_suivi_escrow_mission' ? [] : { ...salaryPaymentInfo, type_contrat_applique: 'LIBERAL', mode_recommande: 'VIREMENT_NOTE_HONORAIRES' }, error: null }));
    renderWorkflow({ typeContratApplique: 'LIBERAL' });
    expect(await screen.findByText('Paiement déclaré — en attente du soignant')).toBeVisible();
    expect(screen.getByText(/Ce paiement antérieur n’est pas lié/)).toBeVisible();
    expect(screen.getByText(/Montant versé/)).toHaveTextContent('60,00');
    expect(screen.queryByRole('button', { name: /Déclarer le paiement|Payer via Stripe/ })).not.toBeInTheDocument();
  });

});

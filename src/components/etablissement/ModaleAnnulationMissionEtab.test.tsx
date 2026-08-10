import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ModaleAnnulationMissionEtab } from './ModaleAnnulationMissionEtab';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  from: vi.fn(),
  afficherNotification: vi.fn(),
  fermer: vi.fn(),
  annulee: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc, from: mocks.from },
}));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));
vi.mock('@/components/ui/DialogResponsive', () => ({
  DialogResponsive: ({ open, children }: React.PropsWithChildren<{ open: boolean }>) => open ? <div>{children}</div> : null,
  DialogResponsiveContent: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveHeader: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveTitle: ({ children }: React.PropsWithChildren) => <h2>{children}</h2>,
  DialogResponsiveBody: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveFooter: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
}));

function query(data: unknown) {
  const builder: any = {};
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.limit = vi.fn(() => Promise.resolve({ data, error: null }));
  builder.maybeSingle = vi.fn(() => Promise.resolve({ data, error: null }));
  return builder;
}

const mission = {
  id: 'mission-1',
  intitule: 'Mission IDE de nuit',
  statut: 'ASSIGNEE',
  debut_le: '2099-08-20T20:00:00Z',
  fin_le: '2099-08-21T08:00:00Z',
  duree_heures: 12,
  taux_horaire_base: 30,
  total_brut: 360,
  type_contrat_applique: 'LIBERAL',
};

describe('ModaleAnnulationMissionEtab — conséquences visibles et force majeure', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.from.mockImplementation((table: string) => table === 'presences'
      ? query([])
      : query({ id: 'contrat-1', statut: 'SIGNE_COMPLET', type_contrat: 'LIBERAL' }));
    mocks.rpc.mockImplementation((name: string) => {
      if (name === 'fn_calculer_indemnite_annulation_etab') {
        return Promise.resolve({
          data: { montant: 180, motif: 'clause_penale', base_calcul: '50 % × 360 €', type_contrat: 'LIBERAL' },
          error: null,
        });
      }
      if (name === 'fn_ouvrir_litige_rate_limited') {
        return Promise.resolve({ data: { success: true, litige_id: 'litige-1' }, error: null });
      }
      if (name === 'fn_annuler_mission_etab') {
        return Promise.resolve({ data: { success: true, indemnite_montant: 180 }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `RPC inattendue : ${name}` } });
    });
  });

  it('présente une somme due sans prétendre qu’un virement Stripe est déjà exécuté', async () => {
    render(
      <ModaleAnnulationMissionEtab
        ouvert
        onFermer={mocks.fermer}
        onAnnulee={mocks.annulee}
        mission={mission}
      />,
    );

    expect(await screen.findByText(/Cette somme est enregistrée comme due/i)).toBeInTheDocument();
    expect(screen.getByText(/ne déclare pas un virement tant qu'il n'est pas réellement exécuté/i)).toBeInTheDocument();
    expect(screen.queryByText(/prélevée automatiquement via.*Stripe/i)).not.toBeInTheDocument();
  });

  it('ouvre une revue de force majeure sans annuler ni déplacer d’argent', async () => {
    render(
      <ModaleAnnulationMissionEtab
        ouvert
        onFermer={mocks.fermer}
        onAnnulee={mocks.annulee}
        mission={mission}
      />,
    );

    await screen.findByText(/Cette somme est enregistrée comme due/i);
    fireEvent.change(screen.getByLabelText(/Motif de l'annulation/i), {
      target: { value: 'CAS_FORCE_MAJEURE' },
    });
    fireEvent.change(screen.getByLabelText(/Explication détaillée/i), {
      target: { value: 'Fermeture administrative imprévisible du service.' },
    });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Demander la revue' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_ouvrir_litige_rate_limited',
      expect.objectContaining({ p_mission_id: 'mission-1', p_type_litige: 'AUTRE' }),
    ));
    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_annuler_mission_etab', expect.anything());
    expect(mocks.annulee).not.toHaveBeenCalled();
  });
});

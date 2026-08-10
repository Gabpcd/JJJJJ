import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { BannerCandidaturesPoolUrgence } from './BannerCandidaturesPoolUrgence';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  from: vi.fn(),
  navigate: vi.fn(),
}));

vi.mock('react-router-dom', () => ({ useNavigate: () => mocks.navigate }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));
vi.mock('@/components/ui/DialogResponsive', () => ({
  DialogResponsive: ({ open, children }: React.PropsWithChildren<{ open: boolean }>) => open ? <div>{children}</div> : null,
  DialogResponsiveContent: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveHeader: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveTitle: ({ children }: React.PropsWithChildren) => <h3>{children}</h3>,
  DialogResponsiveBody: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  DialogResponsiveFooter: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
}));

function queryCandidatures() {
  const builder: any = {};
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.order = vi.fn(() => builder);
  builder.limit = vi.fn(() => Promise.resolve({
    data: [{
      id: 'candidature-1',
      cree_le: '2026-08-10T12:00:00Z',
      mission_id: 'mission-1',
      soignant_id: 'soignant-1',
      missions: { id: 'mission-1', intitule: 'Remplacement IDE nuit', debut_le: '2026-08-10T20:00:00Z' },
      soignants: { id: 'soignant-1', prenom: 'Marie', nom: 'Martin', profession: 'IDE', score_fiabilite: 97, total_missions_terminees: 8 },
    }],
    error: null,
  }));
  return builder;
}

describe('BannerCandidaturesPoolUrgence — décision établissement', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.from.mockReturnValue(queryCandidatures());
    mocks.rpc.mockResolvedValue({ data: { success: true }, error: null });
  });

  it('affiche l’acceptation et impose un motif explicite avant un refus', async () => {
    render(<BannerCandidaturesPoolUrgence etablissementId="etab-1" />);

    expect(await screen.findByText(/acceptation pool urgence en attente/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));
    const confirmer = screen.getByRole('button', { name: 'Confirmer le refus' });
    expect(confirmer).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText('Expliquez brièvement votre décision'), {
      target: { value: 'Profil déjà remplacé par un autre candidat' },
    });
    fireEvent.click(confirmer);

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_etab_valider_acceptation_urgence',
      {
        p_candidature_id: 'candidature-1',
        p_action: 'REFUSER',
        p_motif_refus: 'Profil déjà remplacé par un autre candidat',
      },
    ));
  });
});

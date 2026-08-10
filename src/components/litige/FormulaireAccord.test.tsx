import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { FormulaireAccord } from './FormulaireAccord';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  afficherNotification: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));
vi.mock('@/components/ModalConfirmation', () => ({
  ModalConfirmation: ({ ouvert, onConfirmer, labelConfirmer }: {
    ouvert: boolean;
    onConfirmer: () => void;
    labelConfirmer: string;
  }) => ouvert ? <button type="button" onClick={onConfirmer}>{labelConfirmer}</button> : null,
}));

describe('FormulaireAccord — corrections accessibles pendant un litige', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.rpc.mockResolvedValue({
      data: { success: true, statut: 'EN_ATTENTE_ACCORD_AUTRE_PARTIE' },
      error: null,
    });
  });

  it('permet une contre-proposition au lieu de bloquer l’utilisateur', () => {
    render(
      <FormulaireAccord
        litigeId="litige-1"
        roleUtilisateur="etablissement"
        propositionExistante={{
          type: 'MODIFICATION_MONTANT',
          modifications: { montant_total_corrige: 250 },
          justification: 'Montant proposé par le soignant',
          proposeur_role: 'soignant',
        }}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Refuser / Contre-proposer' }));
    expect(screen.getByText('Faire une contre-proposition')).toBeInTheDocument();
    expect(screen.getByText(/demandera un nouvel accord/i)).toBeInTheDocument();
  });

  it('convertit les horaires locaux en ISO explicite et envoie une proposition traçable', async () => {
    render(<FormulaireAccord litigeId="litige-1" roleUtilisateur="soignant" />);

    fireEvent.change(screen.getByLabelText('Type de modification'), {
      target: { value: 'MODIFICATION_HORAIRES' },
    });
    fireEvent.change(screen.getByLabelText('Arrivée corrigée'), {
      target: { value: '2026-08-20T08:30' },
    });
    fireEvent.change(screen.getByLabelText('Départ corrigé'), {
      target: { value: '2026-08-20T16:30' },
    });
    fireEvent.change(screen.getByLabelText('Justification écrite *'), {
      target: { value: 'Les deux parties ont vérifié le relevé de présence.' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer la proposition' }));
    fireEvent.click(screen.getAllByRole('button', { name: 'Envoyer la proposition' }).at(-1)!);

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_cloturer_litige_avec_payload',
      {
        p_litige_id: 'litige-1',
        p_payload: {
          type: 'MODIFICATION_HORAIRES',
          modifications: {
            pointage_arrivee_le: new Date('2026-08-20T08:30').toISOString(),
            pointage_depart_le: new Date('2026-08-20T16:30').toISOString(),
          },
          justification: 'Les deux parties ont vérifié le relevé de présence.',
        },
      },
    ));
  });
});

import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ClassementContent } from './ClassementSoignants';

const rpcMock = vi.hoisted(() => vi.fn());

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: rpcMock },
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: vi.fn() }),
}));

describe('ClassementSoignants', () => {
  // Depuis la migration 20261128120000 (B9), fn_top_soignants renvoie le prénom et l'initiale du nom, sans
  // identifiant ni nombre d'évaluations ; la page affiche les deux champs tels quels.
  it('affiche le prénom et l\'initiale du nom renvoyés par fn_top_soignants', async () => {
    rpcMock.mockResolvedValueOnce({
      data: [{
        prenom: 'Marie',
        nom: 'D.',
        profession: 'IDE',
        note_moyenne: 4.9,
        score_fiabilite: 98,
        total_missions_terminees: 24,
      }],
      error: null,
    });

    render(<ClassementContent />);

    expect(await screen.findByText('Marie D.')).toBeInTheDocument();
    expect(rpcMock).toHaveBeenCalledWith('fn_top_soignants', {
      p_profession: null,
      p_limit: 10,
    });
  });
});

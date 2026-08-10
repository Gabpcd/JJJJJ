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
  it('affiche le prénom et le nom renvoyés par fn_top_soignants', async () => {
    rpcMock.mockResolvedValueOnce({
      data: [{
        id: 'soignant-1',
        prenom: 'Marie',
        nom: 'Dupont',
        profession: 'IDE',
        note_moyenne: 4.9,
        nb_evaluations: 12,
        score_fiabilite: 98,
        total_missions_terminees: 24,
      }],
      error: null,
    });

    render(<ClassementContent />);

    expect(await screen.findByText('Marie Dupont')).toBeInTheDocument();
    expect(rpcMock).toHaveBeenCalledWith('fn_top_soignants', {
      p_profession: null,
      p_limit: 10,
    });
  });
});

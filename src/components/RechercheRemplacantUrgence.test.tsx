import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RechercheRemplacantUrgence } from './RechercheRemplacantUrgence';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
}));

describe('RechercheRemplacantUrgence — parcours établissement', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.rpc.mockImplementation((nom: string) => {
      if (nom === 'fn_soignants_urgence') {
        return Promise.resolve({
          data: [{
            soignant_id: 'soignant-1',
            id: 'soignant-1',
            prenom: 'Marie',
            nom: 'Martin',
            score_fiabilite: 92,
            distance_km: 4.2,
            urgence_rayon_km: 15,
            telephone: null,
          }],
          error: null,
        });
      }
      if (nom === 'fn_proposer_mission_soignant') {
        return Promise.resolve({ data: { success: true, candidature_id: 'cand-1' }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `RPC inattendue : ${nom}` } });
    });
  });

  it('cherche puis propose via la RPC atomique sans modifier directement une candidature', async () => {
    const onSuccess = vi.fn();
    render(
      <RechercheRemplacantUrgence
        missionId="mission-1"
        onPropose={vi.fn()}
        onError={vi.fn()}
        onSuccess={onSuccess}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: /Rechercher un remplaçant d'urgence/i }));
    expect(await screen.findByText('Marie Martin')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Proposer' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_proposer_mission_soignant',
      { p_mission_id: 'mission-1', p_soignant_id: 'soignant-1' },
    ));
    expect(onSuccess).toHaveBeenCalledWith('Mission proposée au soignant !');
  });
});

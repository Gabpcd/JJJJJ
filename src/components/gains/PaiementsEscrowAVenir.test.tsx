import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import PaiementsEscrowAVenir from './PaiementsEscrowAVenir';

const reponseEscrow = vi.hoisted(() => ({
  data: [{
    mission_id: 'mission-123',
    mission_intitule: 'Mission de nuit',
    etablissement_nom: 'Clinique test',
    honoraires_cents: 12_500,
    etat: 'LITIGE',
    date_affichee: null,
    mission_date: '2026-07-20T20:00:00+02:00',
    a_litige: true,
  }],
  error: null,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: vi.fn().mockResolvedValue(reponseEscrow),
  },
}));

describe('PaiementsEscrowAVenir', () => {
  it('ouvre un paiement en litige sur la route canonique du détail de mission', async () => {
    render(
      <MemoryRouter>
        <PaiementsEscrowAVenir />
      </MemoryRouter>,
    );

    const lien = await screen.findByRole('link');
    expect(lien).toHaveAttribute('href', '/soignant/missions/mission-123');
  });
});

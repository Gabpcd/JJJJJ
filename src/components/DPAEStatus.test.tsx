import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { BandeauRappelDPAE } from './BandeauRappelDPAE';
import { DPAEStatus } from './DPAEStatus';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  afficherNotification: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));

describe('DPAEStatus — parcours réellement exposé à l’établissement', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.rpc.mockImplementation((name: string) => {
      if (name === 'fn_generer_donnees_dpae') {
        return Promise.resolve({
          data: {
            success: true,
            etablissement: { siret: '12345678901234' },
            salarie: { nom: 'Martin', champs_a_completer_sur_net_entreprises: [] },
            embauche: { date_debut: '2026-08-20' },
            urssaf_url: 'https://www.net-entreprises.fr/declaration-prealable-embauche/',
          },
          error: null,
        });
      }
      if (name === 'fn_enregistrer_numero_dpae') {
        return Promise.resolve({ data: { success: true, dpae_numero: '2026ABC123' }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `RPC inattendue : ${name}` } });
    });
  });

  it('ne rend rien pour une mission libérale', () => {
    const { container } = render(<DPAEStatus contratId="contrat-1" typeContrat="LIBERAL" />);
    expect(container).toBeEmptyDOMElement();
  });

  it('prépare les données sans prétendre transmettre la DPAE puis conserve le numéro URSSAF', async () => {
    render(<DPAEStatus contratId="contrat-1" typeContrat="SALARIE" />);

    fireEvent.click(screen.getByRole('button', { name: 'Préparer les données DPAE' }));

    expect(await screen.findByRole('link', { name: /Transmettre sur Net-Entreprises/i }))
      .toHaveAttribute('href', 'https://www.net-entreprises.fr/declaration-prealable-embauche/');
    expect(screen.queryByText(/transmise automatiquement/i)).not.toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText('Ex : 2026XXXXXXXX'), {
      target: { value: '2026ABC123' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer le numéro DPAE' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_enregistrer_numero_dpae',
      { p_contrat_id: 'contrat-1', p_dpae_numero: '2026ABC123' },
    ));
    expect(await screen.findByText('DPAE déclarée')).toBeInTheDocument();
  });

  it('affiche aussi le rappel pour la valeur canonique SALARIE', () => {
    render(<BandeauRappelDPAE typeContrat="SALARIE" dpaeEffectuee={false} />);
    expect(screen.getByText(/Rappel légal/i)).toBeInTheDocument();
    expect(screen.getByText(/traçabilité interne/i)).toBeInTheDocument();
  });
});

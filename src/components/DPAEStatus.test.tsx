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

// CDDU et VACATION sont des contrats salariés : DPAE obligatoire (C. trav.
// art. L.1221-10 ; CDD d'usage = CDD, art. L.1242-2 3° et D.1242-1).
// Le remplacement libéral (relation B2B) n'en a pas. Décision du 08/11/2026.
// Midi heure locale : le 24 septembre quel que soit le fuseau d'exécution.
const MIDI_LOCAL_24_SEPTEMBRE = new Date(2026, 8, 24, 12, 0, 0).toISOString();

describe('DPAE selon le type de contrat', () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it.each(['CDD', 'SALARIE', 'CDDU', 'VACATION'])('DPAEStatus propose la préparation DPAE pour un contrat %s', type => {
    render(<DPAEStatus contratId="contrat-1" typeContrat={type} />);
    expect(screen.getByText('DPAE obligatoire — Mission salariée')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Préparer les données DPAE' })).toBeInTheDocument();
  });

  it.each(['CDDU', 'VACATION'])('DPAEStatus affiche « DPAE déclarée » pour un contrat %s déjà déclaré', type => {
    render(<DPAEStatus contratId="contrat-1" typeContrat={type} dpaeNumero="2026ABC123" />);
    expect(screen.getByText('DPAE déclarée')).toBeInTheDocument();
    expect(screen.getByText('2026ABC123')).toBeInTheDocument();
  });

  it.each(['REMPLACEMENT_LIBERAL', 'LIBERAL', null, undefined])('DPAEStatus ne rend rien pour %s', type => {
    const { container } = render(<DPAEStatus contratId="contrat-1" typeContrat={type} />);
    expect(container).toBeEmptyDOMElement();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it.each(['CDD', 'SALARIE', 'CDDU', 'VACATION'])('BandeauRappelDPAE rappelle la DPAE pour un contrat %s', type => {
    render(<BandeauRappelDPAE typeContrat={type} dpaeEffectuee={false} />);
    expect(screen.getByText(/^⚠️ Rappel légal : effectuez la Déclaration Préalable à l'Embauche \(DPAE\)/)).toBeInTheDocument();
    expect(screen.getByText('La DPAE est obligatoire pour ce contrat salarié. Pour une mission libérale directe, elle n\'est pas requise.')).toBeInTheDocument();
  });

  it.each(['CDDU', 'VACATION'])('BandeauRappelDPAE confirme la DPAE effectuée pour un contrat %s', type => {
    render(<BandeauRappelDPAE typeContrat={type} dpaeEffectuee dpaeEffectueeLe={MIDI_LOCAL_24_SEPTEMBRE} />);
    expect(screen.getByText('✅ DPAE déclarée comme effectuée par l\'établissement le 24 septembre 2026')).toBeInTheDocument();
  });

  it.each(['REMPLACEMENT_LIBERAL', 'LIBERAL', undefined])('BandeauRappelDPAE ne rend rien pour %s', type => {
    const { container } = render(<BandeauRappelDPAE typeContrat={type} dpaeEffectuee={false} />);
    expect(container).toBeEmptyDOMElement();
  });
});

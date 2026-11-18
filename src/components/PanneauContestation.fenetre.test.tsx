import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PanneauContestation } from './PanneauContestation';

// D12 (DECISIONS_LOT2, Q9) : la fenêtre de contestation est lue au serveur
// (fn_fenetre_contestation_ouverte), fail-closed ; les textes « 72h pour
// répondre » et « l'admin plateforme tranchera » ne sont plus affichés.

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  maybeSingle: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder: Record<string, unknown> = {};
  for (const methode of ['select', 'eq', 'order', 'limit']) builder[methode] = () => builder;
  builder.maybeSingle = mocks.maybeSingle;
  return { supabase: { from: vi.fn(() => builder), rpc: mocks.rpc } };
});
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'utilisateur-1' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: 'SOIGNANT' }) }));
vi.mock('@/lib/sentry', () => ({ capturerErreurSentry: vi.fn() }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

const IL_Y_A_DIX_JOURS = new Date(Date.now() - 10 * 24 * 3600 * 1000).toISOString();

function rendre(presenceValideeLe: string | null = IL_Y_A_DIX_JOURS) {
  return render(
    <PanneauContestation
      presenceId="presence-1"
      missionId="mission-1"
      etablissementId="etab-1"
      soignantId="soignant-1"
      presenceValideeLe={presenceValideeLe}
      role="SOIGNANT"
    />,
  );
}

function reponseFenetre(reponse: { data: unknown; error: unknown } | Error) {
  mocks.rpc.mockImplementation((nom: string) => {
    if (nom !== 'fn_fenetre_contestation_ouverte') return Promise.resolve({ data: null, error: null });
    return reponse instanceof Error ? Promise.reject(reponse) : Promise.resolve(reponse);
  });
}

async function attendreFenetre() {
  await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_fenetre_contestation_ouverte', {
    p_type_litige: 'DESACCORD_HEURES_POINTAGE',
    p_mission_id: 'mission-1',
  }));
  await act(async () => { await Promise.resolve(); });
}

function litige(statut: string, reponse: string | null = null) {
  return {
    id: 'litige-1', mission_id: 'mission-1', presence_id: 'presence-1', soignant_id: 'soignant-1',
    etablissement_id: 'etab-1', motif: 'Heures validées inexactes.', reponse, resolution: null, statut,
    initie_par: 'SOIGNANT', cree_le: '2026-11-10T10:00:00Z', resolu_le: null, resolu_par: null,
    accord_soignant: null, accord_etablissement: null, accord_soignant_le: null, accord_etablissement_le: null,
  };
}

describe('PanneauContestation — fenêtre lue au serveur (D12)', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.maybeSingle.mockReset();
    mocks.maybeSingle.mockResolvedValue({ data: null, error: null });
  });

  it('fenêtre ouverte selon le serveur : bouton présent, quelle que soit l’ancienneté de la validation', async () => {
    reponseFenetre({ data: true, error: null });
    rendre();
    const bouton = await screen.findByRole('button', { name: /Contester cette présence/ });
    fireEvent.click(bouton);
    expect(screen.getByText('Vous avez 72 h après la validation pour contester.')).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(/admin plateforme tranchera|72\s?h pour répondre/i);
  });

  it('fenêtre fermée selon le serveur : aucun bouton', async () => {
    reponseFenetre({ data: false, error: null });
    rendre(new Date().toISOString());
    await attendreFenetre();
    expect(screen.queryByRole('button', { name: /Contester cette présence/ })).toBeNull();
  });

  it('erreur du serveur : aucun bouton (fail-closed)', async () => {
    reponseFenetre({ data: null, error: { message: 'permission denied' } });
    rendre(new Date().toISOString());
    await attendreFenetre();
    expect(screen.queryByRole('button', { name: /Contester cette présence/ })).toBeNull();
  });

  it('appel rejeté : aucun bouton (fail-closed)', async () => {
    reponseFenetre(new Error('réseau'));
    rendre(new Date().toISOString());
    await attendreFenetre();
    expect(screen.queryByRole('button', { name: /Contester cette présence/ })).toBeNull();
  });

  it('présence non validée : ni appel de fenêtre ni bouton', async () => {
    reponseFenetre({ data: true, error: null });
    rendre(null);
    await waitFor(() => expect(mocks.maybeSingle).toHaveBeenCalled());
    await act(async () => { await Promise.resolve(); });
    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_fenetre_contestation_ouverte', expect.anything());
    expect(screen.queryByRole('button', { name: /Contester cette présence/ })).toBeNull();
  });

  it('litige ouvert puis en discussion : aucun texte de délai ni d’arbitrage annoncé', async () => {
    reponseFenetre({ data: false, error: null });
    mocks.maybeSingle.mockResolvedValue({ data: litige('OUVERT'), error: null });
    const { unmount } = rendre();
    expect(await screen.findByText(/En attente de la réponse/)).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(/72\s?h pour répondre|admin plateforme tranchera/i);
    unmount();

    mocks.maybeSingle.mockResolvedValue({ data: litige('EN_DISCUSSION', 'Réponse de l’établissement.'), error: null });
    rendre();
    expect(await screen.findByText('Discussion en cours.')).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(/tranchera|sous 72\s?h|72\s?h pour répondre/i);
  });
});

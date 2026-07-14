import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import RacineApp from './RacineApp';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  authState: {
    session: { user: { id: 'utilisateur-actif' } } as any,
    loading: false,
  },
}));

vi.mock('@/lib/platform', () => ({ isNative: () => true }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => mocks.authState }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/lib/logger', () => ({
  logger: { debug: vi.fn(), error: vi.fn(), warn: vi.fn() },
}));
vi.mock('@/components/ChargementPage', () => ({
  ChargementPage: () => <div role="status">Résolution en cours</div>,
}));
vi.mock('@/pages/PageAccueil', () => ({ default: () => <div>Accueil public</div> }));
vi.mock('@/pages/PageConnexion', () => ({ default: () => <div>Écran de connexion</div> }));

function renderRacine() {
  return render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route path="/" element={<RacineApp />} />
        <Route path="/soignant/tableau-de-bord" element={<div>Tableau de bord soignant</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('RacineApp — résolution sûre du rôle natif', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.authState.session = { user: { id: 'utilisateur-actif' } } as any;
    mocks.authState.loading = false;
  });

  it('préserve la session dans un état d’erreur réessayable au lieu d’afficher la connexion', async () => {
    mocks.rpc
      .mockResolvedValueOnce({ data: null, error: { message: 'network unavailable' } })
      .mockResolvedValueOnce({ data: { role: 'SOIGNANT' }, error: null });

    renderRacine();

    expect(await screen.findByRole('alert')).toHaveTextContent('Votre session est toujours active');
    expect(screen.queryByText('Écran de connexion')).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));

    expect(await screen.findByText('Tableau de bord soignant')).toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });

  it('distingue une réponse serveur réussie sans rôle d’une erreur transitoire', async () => {
    mocks.rpc.mockResolvedValue({ data: { role: null }, error: null });

    renderRacine();

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Écran de connexion')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
});

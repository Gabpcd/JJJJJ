import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import PageConnexion from './PageConnexion';

const mocks = vi.hoisted(() => ({
  connexion: vi.fn(),
  afficherNotification: vi.fn(),
  rpc: vi.fn(),
  signOut: vi.fn(),
  resetPasswordForEmail: vi.fn(),
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ connexion: mocks.connexion, loading: false }),
}));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    auth: {
      signOut: mocks.signOut,
      getSession: vi.fn().mockResolvedValue({ data: { session: null } }),
      refreshSession: vi.fn(),
      resetPasswordForEmail: mocks.resetPasswordForEmail,
    },
  },
}));
vi.mock('@/lib/platform', () => ({ isNative: () => false }));
vi.mock('@/lib/biometric', () => ({
  isBiometricAvailable: vi.fn().mockResolvedValue(false),
  isBiometricEnabled: () => false,
  authenticateWithBiometric: vi.fn(),
  enableBiometric: vi.fn(),
  getBiometricLabel: () => 'Face ID',
}));
vi.mock('@/lib/haptics', () => ({ hapticNotification: vi.fn() }));
vi.mock('@/lib/logger', () => ({
  logger: { debug: vi.fn(), error: vi.fn(), warn: vi.fn() },
}));
vi.mock('@/components/AuthLayout', () => ({
  AuthLayout: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock('@/components/FooterLegal', () => ({ FooterLegal: () => null }));
vi.mock('@/components/BoutonProSanteConnect', () => ({ BoutonProSanteConnect: () => null }));
vi.mock('@/components/CaptchaTurnstile', () => ({
  CaptchaTurnstile: () => null,
  TURNSTILE_REQUIRED: false,
}));

function renderConnexion() {
  return render(
    <MemoryRouter initialEntries={['/connexion']}>
      <Routes>
        <Route path="/connexion" element={<PageConnexion />} />
        <Route path="/inscription/soignant" element={<div>Inscription soignant</div>} />
        <Route path="/soignant/tableau-de-bord" element={<div>Tableau de bord soignant</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

async function soumettreConnexion() {
  fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'marie@jolene.app' } });
  fireEvent.change(screen.getByLabelText('Mot de passe'), { target: { value: 'secret-valide' } });
  fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
  await waitFor(() => expect(mocks.connexion).toHaveBeenCalledTimes(1));
}

describe('PageConnexion — résolution sûre du rôle', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.connexion.mockResolvedValue(undefined);
    mocks.signOut.mockResolvedValue({ error: null });
    mocks.resetPasswordForEmail.mockResolvedValue({ error: null });
  });

  it('conserve la session et ne redirige pas vers l’inscription si la RPC de rôle échoue', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: 'service unavailable' } });

    renderConnexion();
    await soumettreConnexion();

    await waitFor(() => {
      expect(mocks.afficherNotification).toHaveBeenCalledWith(expect.objectContaining({
        type: 'erreur',
        message: expect.stringContaining('Votre session est active'),
      }));
    });
    expect(mocks.signOut).not.toHaveBeenCalled();
    expect(screen.queryByText('Inscription soignant')).not.toBeInTheDocument();
    expect(mocks.afficherNotification).not.toHaveBeenCalledWith(expect.objectContaining({
      message: expect.stringContaining('inscription n’est pas complète'),
    }));
  });

  it('réserve la déconnexion au cas où la RPC réussit réellement sans rôle', async () => {
    mocks.rpc.mockResolvedValue({ data: { role: null }, error: null });

    renderConnexion();
    await soumettreConnexion();

    expect(await screen.findByText('Inscription soignant')).toBeInTheDocument();
    expect(mocks.signOut).toHaveBeenCalledTimes(1);
    expect(mocks.afficherNotification).toHaveBeenCalledWith(expect.objectContaining({
      type: 'erreur',
      message: expect.stringContaining('inscription n\'est pas complète'),
    }));
  });

  it('n’annonce un envoi qu’après la vraie demande et normalise l’adresse', async () => {
    renderConnexion();
    fireEvent.change(screen.getByLabelText('Email'), {
      target: { value: '  Gabrielle.PCD@Outlook.COM  ' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Mot de passe oublié ?' }));

    expect(screen.queryByText(/le lien vient d’être envoyé/i)).not.toBeInTheDocument();
    expect(mocks.resetPasswordForEmail).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Envoyer le lien' }));

    await waitFor(() => {
      expect(mocks.resetPasswordForEmail).toHaveBeenCalledWith(
        'gabrielle.pcd@outlook.com',
        { redirectTo: expect.stringMatching(/\/reset-password$/) },
      );
    });
    expect(await screen.findByText(/le lien vient d’être envoyé/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Renvoyer dans 60 s/i })).toBeDisabled();
  });
});

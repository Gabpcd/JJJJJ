import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import PageResetPassword from './PageResetPassword';

const mocks = vi.hoisted(() => ({
  afficherNotification: vi.fn(),
  unsubscribe: vi.fn(),
  setSession: vi.fn(),
  exchangeCodeForSession: vi.fn(),
  verifyOtp: vi.fn(),
  updateUser: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));
vi.mock('@/components/FooterLegal', () => ({ FooterLegal: () => null }));
vi.mock('@/lib/logger', () => ({ logger: { warn: vi.fn() } }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      onAuthStateChange: vi.fn(() => ({
        data: { subscription: { unsubscribe: mocks.unsubscribe } },
      })),
      setSession: mocks.setSession,
      exchangeCodeForSession: mocks.exchangeCodeForSession,
      verifyOtp: mocks.verifyOtp,
      updateUser: mocks.updateUser,
      signOut: mocks.signOut,
    },
  },
}));

function renderPage() {
  return render(
    <MemoryRouter initialEntries={['/reset-password']}>
      <PageResetPassword />
    </MemoryRouter>,
  );
}

describe('PageResetPassword — preuve de récupération obligatoire', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.history.replaceState(null, '', '/reset-password');
    mocks.setSession.mockResolvedValue({ error: null });
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: { redirectType: 'recovery' },
      error: null,
    });
    mocks.verifyOtp.mockResolvedValue({ error: null });
    mocks.updateUser.mockResolvedValue({ error: null });
    mocks.signOut.mockResolvedValue({ error: null });
  });

  afterEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('refuse une visite directe même si une session ordinaire existe ailleurs', async () => {
    renderPage();

    expect(await screen.findByText('Lien invalide ou expiré')).toBeInTheDocument();
    expect(mocks.updateUser).not.toHaveBeenCalled();
  });

  it('accepte un token recovery, change le mot de passe puis ferme la session', async () => {
    window.history.replaceState(null, '', '/reset-password?token_hash=preuve&type=recovery');
    renderPage();

    await waitFor(() => {
      expect(mocks.verifyOtp).toHaveBeenCalledWith({
        token_hash: 'preuve',
        type: 'recovery',
      });
    });

    fireEvent.change(screen.getByLabelText('Nouveau mot de passe *'), {
      target: { value: 'NouveauSecret2026!' },
    });
    fireEvent.change(screen.getByLabelText('Confirmer le mot de passe *'), {
      target: { value: 'NouveauSecret2026!' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Modifier mon mot de passe' }));

    await waitFor(() => {
      expect(mocks.updateUser).toHaveBeenCalledWith({ password: 'NouveauSecret2026!' });
      expect(mocks.signOut).toHaveBeenCalledTimes(1);
    });
    expect(await screen.findByText('Mot de passe modifié')).toBeInTheDocument();
  });

  it('refuse un token expiré sans proposer le formulaire', async () => {
    mocks.verifyOtp.mockResolvedValue({ error: { message: 'expired' } });
    window.history.replaceState(null, '', '/reset-password?token_hash=expire&type=recovery');
    renderPage();

    expect(await screen.findByText('Lien invalide ou expiré')).toBeInTheDocument();
    expect(screen.queryByLabelText('Nouveau mot de passe *')).not.toBeInTheDocument();
    expect(mocks.updateUser).not.toHaveBeenCalled();
  });

  it('refuse un code PKCE qui ne provient pas d’un email recovery', async () => {
    mocks.exchangeCodeForSession.mockResolvedValue({
      data: { redirectType: 'signup' },
      error: null,
    });
    window.history.replaceState(null, '', '/reset-password?code=oauth');
    renderPage();

    expect(await screen.findByText('Lien invalide ou expiré')).toBeInTheDocument();
    expect(screen.queryByLabelText('Nouveau mot de passe *')).not.toBeInTheDocument();
  });

  it('n’annonce pas de succès si la session recovery ne peut pas être fermée', async () => {
    mocks.signOut.mockResolvedValue({ error: { message: 'network' } });
    window.history.replaceState(null, '', '/reset-password?token_hash=preuve&type=recovery');
    renderPage();

    await screen.findByLabelText('Nouveau mot de passe *');
    fireEvent.change(screen.getByLabelText('Nouveau mot de passe *'), {
      target: { value: 'NouveauSecret2026!' },
    });
    fireEvent.change(screen.getByLabelText('Confirmer le mot de passe *'), {
      target: { value: 'NouveauSecret2026!' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Modifier mon mot de passe' }));

    await waitFor(() => expect(mocks.signOut).toHaveBeenCalledTimes(1));
    expect(screen.queryByText('Mot de passe modifié')).not.toBeInTheDocument();
    expect(mocks.afficherNotification).toHaveBeenCalledWith(expect.objectContaining({
      type: 'erreur',
    }));
  });
});

import React from 'react';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AccepterInvitationEtab from './AccepterInvitationEtab';

const mocks = vi.hoisted(() => ({
  token: 'invitation-premiere',
  auth: {
    user: { id: 'nouvel-invite', email: 'invite@example.test' } as { id: string; email: string } | null,
    loading: false,
  },
  navigate: vi.fn(),
  rpc: vi.fn(),
  afficherNotification: vi.fn(),
  reinitialiserCacheRole: vi.fn(),
}));

vi.mock('react-router-dom', () => ({
  useNavigate: () => mocks.navigate,
  useParams: () => ({ token: mocks.token }),
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => mocks.auth }));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/hooks/useRole', () => ({ reinitialiserCacheRole: mocks.reinitialiserCacheRole }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <main>{children}</main>,
}));

type Reponse = { data: { success: boolean; error_code?: string } | null; error: Error | null };

function demandeDifferee() {
  let resolve!: (reponse: Reponse) => void;
  let reject!: (erreur: Error) => void;
  const promise = new Promise<Reponse>((resoudre, rejeter) => {
    resolve = resoudre;
    reject = rejeter;
  });
  return { promise, resolve, reject };
}

const succes: Reponse = { data: { success: true }, error: null };
const accepter = () => screen.getByRole('button', { name: "Accepter l'invitation" });

describe('Invitation équipe — transition de rôle et demandes obsolètes', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    sessionStorage.clear();
    mocks.token = 'invitation-premiere';
    mocks.auth = { user: { id: 'nouvel-invite', email: 'invite@example.test' }, loading: false };
    mocks.rpc.mockResolvedValue(succes);
  });

  afterEach(() => {
    cleanup();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('invalide le rôle avant de naviguer après une acceptation explicite réussie', async () => {
    const demande = demandeDifferee();
    mocks.rpc.mockReturnValue(demande.promise);
    render(<AccepterInvitationEtab />);
    expect(mocks.rpc).not.toHaveBeenCalled();

    fireEvent.click(accepter());
    expect(mocks.rpc).toHaveBeenCalledWith('fn_accepter_invitation_membre', { p_token: 'invitation-premiere' });
    expect(mocks.reinitialiserCacheRole).not.toHaveBeenCalled();
    await act(async () => demande.resolve(succes));
    expect(screen.getByText("Bienvenue dans l'équipe !")).toBeInTheDocument();
    expect(mocks.navigate).not.toHaveBeenCalled();

    await act(async () => vi.advanceTimersByTimeAsync(1500));
    expect(mocks.reinitialiserCacheRole).toHaveBeenCalledTimes(1);
    expect(mocks.navigate).toHaveBeenCalledExactlyOnceWith('/etablissement/tableau-de-bord');
    expect(mocks.reinitialiserCacheRole.mock.invocationCallOrder[0]).toBeLessThan(mocks.navigate.mock.invocationCallOrder[0]);
  });

  it('ne soumet qu’une demande lors de deux clics consécutifs', async () => {
    const demande = demandeDifferee();
    mocks.rpc.mockReturnValue(demande.promise);
    render(<AccepterInvitationEtab />);
    const bouton = accepter();
    act(() => {
      fireEvent.click(bouton);
      fireEvent.click(bouton);
    });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    expect(bouton).toBeDisabled();
    await act(async () => demande.resolve(succes));
  });

  it.each(['succes', 'rejet'] as const)('ignore une réponse %s reçue après le départ de la page', async (issue) => {
    const demande = demandeDifferee();
    mocks.rpc.mockReturnValue(demande.promise);
    const vue = render(<AccepterInvitationEtab />);
    fireEvent.click(accepter());
    vue.unmount();
    await act(async () => {
      if (issue === 'succes') demande.resolve(succes);
      else demande.reject(new Error('Service Unavailable'));
    });
    await act(async () => vi.advanceTimersByTimeAsync(20_000));
    expect(mocks.afficherNotification).not.toHaveBeenCalled();
    expect(mocks.reinitialiserCacheRole).not.toHaveBeenCalled();
    expect(mocks.navigate).not.toHaveBeenCalled();
  });

  it.each(['jeton', 'compte'] as const)('ignore l’ancienne demande après un changement de %s, sans déverrouiller la suivante', async (changement) => {
    const ancienne = demandeDifferee();
    const nouvelle = demandeDifferee();
    mocks.rpc.mockReturnValueOnce(ancienne.promise).mockReturnValueOnce(nouvelle.promise);
    const vue = render(<AccepterInvitationEtab />);
    fireEvent.click(accepter());
    if (changement === 'jeton') mocks.token = 'invitation-seconde';
    else mocks.auth = { user: { id: 'autre-invite', email: 'autre@example.test' }, loading: false };
    vue.rerender(<AccepterInvitationEtab />);
    expect(accepter()).toBeEnabled();
    fireEvent.click(accepter());

    await act(async () => ancienne.resolve(succes));
    expect(accepter()).toBeDisabled();
    expect(screen.queryByText("Bienvenue dans l'équipe !")).not.toBeInTheDocument();
    expect(mocks.afficherNotification).not.toHaveBeenCalled();
    await act(async () => vi.advanceTimersByTimeAsync(1500));
    expect(mocks.navigate).not.toHaveBeenCalled();

    await act(async () => nouvelle.resolve(succes));
    await act(async () => vi.advanceTimersByTimeAsync(1500));
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(mocks.afficherNotification).toHaveBeenCalledTimes(1);
    expect(mocks.reinitialiserCacheRole).toHaveBeenCalledTimes(1);
    expect(mocks.navigate).toHaveBeenCalledExactlyOnceWith('/etablissement/tableau-de-bord');
  });

  it('annule une redirection déjà programmée lorsque la page est quittée', async () => {
    const vue = render(<AccepterInvitationEtab />);
    await act(async () => fireEvent.click(accepter()));
    expect(screen.getByText("Bienvenue dans l'équipe !")).toBeInTheDocument();
    vue.unmount();
    await act(async () => vi.advanceTimersByTimeAsync(1500));
    expect(mocks.navigate).not.toHaveBeenCalled();
    expect(mocks.reinitialiserCacheRole).not.toHaveBeenCalled();
  });

  it('attend la fin de l’authentification avant de proposer l’acceptation', () => {
    mocks.auth.loading = true;
    const vue = render(<AccepterInvitationEtab />);
    expect(screen.queryByRole('button', { name: "Accepter l'invitation" })).not.toBeInTheDocument();
    expect(mocks.navigate).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
    mocks.auth.loading = false;
    vue.rerender(<AccepterInvitationEtab />);
    expect(accepter()).toBeEnabled();
  });

  it('attend l’authentification avant de sauvegarder le lien et demander la connexion', () => {
    mocks.auth = { user: null, loading: true };
    const vue = render(<AccepterInvitationEtab />);
    expect(mocks.navigate).not.toHaveBeenCalled();
    expect(sessionStorage.getItem('post_login_redirect')).toBeNull();
    mocks.auth.loading = false;
    vue.rerender(<AccepterInvitationEtab />);
    expect(sessionStorage.getItem('post_login_redirect')).toBe('/etab/invitation/invitation-premiere');
    expect(mocks.navigate).toHaveBeenCalledExactlyOnceWith('/connexion?return=%2Fetab%2Finvitation%2Finvitation-premiere');
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
});

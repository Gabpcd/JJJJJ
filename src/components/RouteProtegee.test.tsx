import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteProtegee } from './RouteProtegee';

const mocks = vi.hoisted(() => ({
  retry: vi.fn(),
  deconnexion: vi.fn(),
  roleState: {
    role: 'SOIGNANT',
    loading: false,
    resolved: true,
    error: null as Error | null,
  },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({
    user: { id: 'utilisateur' },
    session: { user: { id: 'utilisateur', email_confirmed_at: '2026-07-01T00:00:00Z' } },
    loading: false,
    deconnexion: mocks.deconnexion,
  }),
}));

vi.mock('@/hooks/useRole', () => ({
  useRole: () => ({ ...mocks.roleState, retry: mocks.retry }),
}));

vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement</p> }));

function rendre() {
  return render(
    <MemoryRouter>
      <RouteProtegee rolesAutorises={['SOIGNANT']}>
        <p>Espace soignant</p>
      </RouteProtegee>
    </MemoryRouter>,
  );
}

describe('RouteProtegee — reprise de session native', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(mocks.roleState, {
      role: 'SOIGNANT',
      loading: false,
      resolved: true,
      error: null,
    });
  });

  it('ouvre l’espace avec un rôle résolu', () => {
    rendre();
    expect(screen.getByText('Espace soignant')).toBeInTheDocument();
  });

  it('conserve la session et permet de relancer une revalidation en erreur', () => {
    Object.assign(mocks.roleState, { role: 'INCONNU', resolved: false, error: new Error('réseau') });
    rendre();

    expect(screen.getByRole('alert')).toHaveTextContent('Votre session est toujours active');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.retry).toHaveBeenCalledTimes(1);
  });

  it('ne boucle pas vers la racine lorsque le serveur révoque le rôle', () => {
    Object.assign(mocks.roleState, { role: 'INCONNU', resolved: true, error: null });
    rendre();

    expect(screen.getByRole('alert')).toHaveTextContent('Accès à cet espace non autorisé');
    fireEvent.click(screen.getByRole('button', { name: 'Se reconnecter' }));
    expect(mocks.deconnexion).toHaveBeenCalledTimes(1);
  });
});

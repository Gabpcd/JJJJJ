import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteProtegee } from './RouteProtegee';

const mocks = vi.hoisted(() => ({
  connecte: true,
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
    user: mocks.connecte ? { id: 'utilisateur' } : null,
    session: mocks.connecte ? { user: { id: 'utilisateur', email_confirmed_at: '2026-07-01T00:00:00Z' } } : null,
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
      <Routes><Route path="/inscription/reprendre" element={<p>Reprise inscription</p>} /><Route path="/" element={<RouteProtegee rolesAutorises={['SOIGNANT']}>
        <p>Espace soignant</p>
      </RouteProtegee>} /></Routes>
    </MemoryRouter>,
  );
}

describe('RouteProtegee — reprise de session native', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.connecte = true;
    Object.assign(mocks.roleState, {
      role: 'SOIGNANT',
      loading: false,
      resolved: true,
      error: null,
    });
  });

  it('conserve seulement une fiche mission canonique après expiration de session', () => {
    mocks.connecte = false;
    const mission = '/etablissement/missions/71000000-0000-4000-8000-000000000003';
    function Destination() { const l = useLocation(); return <output>{l.pathname + l.search}</output>; }
    render(<MemoryRouter initialEntries={[mission]}><Routes>
      <Route path="/connexion" element={<Destination />} />
      <Route path="/etablissement/missions/:id" element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT']}><p>Mission</p></RouteProtegee>} />
    </Routes></MemoryRouter>);
    expect(screen.getByRole('status')).toHaveTextContent('/connexion?return=' + encodeURIComponent(mission));
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

    expect(screen.getByText('Reprise inscription')).toBeInTheDocument();
    expect(screen.queryByText('Espace soignant')).not.toBeInTheDocument();
    expect(mocks.deconnexion).not.toHaveBeenCalled();
  });
});

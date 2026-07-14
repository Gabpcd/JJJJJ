import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { ADMIN_ACCESS } from '@/lib/adminAccess';
import { RouteAdminProtegee } from './RouteAdminProtegee';

const accessState = vi.hoisted(() => ({
  loading: false,
  allowed: false,
}));

vi.mock('@/components/RouteProtegee', () => ({
  RouteProtegee: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ChargementPage', () => ({
  ChargementPage: () => <div role="status">Vérification des accès</div>,
}));

vi.mock('@/hooks/useAccesAdmin', () => ({
  useAccesAdmin: () => ({
    accesTotal: accessState.allowed,
    groupes: [],
    loading: accessState.loading,
    aAcces: () => accessState.allowed,
  }),
}));

function renderGuard() {
  return render(
    <MemoryRouter initialEntries={['/admin/facturation']}>
      <Routes>
        <Route
          path="/admin/facturation"
          element={(
            <RouteAdminProtegee accesRequis={ADMIN_ACCESS.FINANCES}>
              <div>Données financières sensibles</div>
            </RouteAdminProtegee>
          )}
        />
        <Route path="/acces-admin-indisponible" element={<div>Accès bloqué</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('RouteAdminProtegee', () => {
  it('reste fermée pendant la vérification serveur', () => {
    accessState.loading = true;
    accessState.allowed = false;

    renderGuard();

    expect(screen.getByRole('status')).toHaveTextContent('Vérification des accès');
    expect(screen.queryByText('Données financières sensibles')).not.toBeInTheDocument();
  });

  it('redirige vers une route publique sûre quand le périmètre est refusé', () => {
    accessState.loading = false;
    accessState.allowed = false;

    renderGuard();

    expect(screen.getByText('Accès bloqué')).toBeInTheDocument();
    expect(screen.queryByText('Données financières sensibles')).not.toBeInTheDocument();
  });

  it('rend la page uniquement après autorisation explicite', () => {
    accessState.loading = false;
    accessState.allowed = true;

    renderGuard();

    expect(screen.getByText('Données financières sensibles')).toBeInTheDocument();
  });
});

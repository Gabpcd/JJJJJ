import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import MissionsSoignant from './MissionsSoignant';

const authUser = { id: 'soignant-test' };

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/BandeauProfilIncomplet', () => ({
  BandeauProfilIncomplet: () => null,
}));

vi.mock('@/components/SkeletonCard', () => ({
  SkeletonList: () => <div>Chargement</div>,
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: authUser }),
}));

vi.mock('@/hooks/usePullToRefresh', () => ({
  usePullToRefresh: () => ({ pullDistance: 0, refreshing: false }),
}));

vi.mock('@/integrations/supabase/client', () => {
  const pending = new Promise<never>(() => undefined);
  const createBuilder = () => {
    const builder: Record<string, unknown> = {};
    for (const method of ['select', 'eq', 'in', 'gt', 'gte', 'lt', 'lte', 'order', 'or', 'range']) {
      builder[method] = () => builder;
    }
    builder.maybeSingle = () => pending;
    builder.then = pending.then.bind(pending);
    return builder;
  };

  return { supabase: { from: () => createBuilder() } };
});

describe('MissionsSoignant — onglets accessibles', () => {
  it('annonce explicitement le chargement des candidatures', () => {
    render(
      <MemoryRouter initialEntries={['/soignant/missions?tab=candidatures']}>
        <MissionsSoignant />
      </MemoryRouter>,
    );

    expect(screen.getByRole('status')).toHaveTextContent('En attente de réponse');
  });

  it('expose la sélection et permet la navigation avec les flèches', () => {
    render(
      <MemoryRouter>
        <MissionsSoignant />
      </MemoryRouter>,
    );

    const tablist = screen.getByRole('tablist', { name: 'Catégories de missions' });
    const candidatures = screen.getByRole('tab', { name: 'Candidatures' });
    const aVenir = screen.getByRole('tab', { name: 'À venir' });
    const passees = screen.getByRole('tab', { name: 'Passées' });

    expect(tablist).toContainElement(aVenir);
    expect(aVenir).toHaveAttribute('aria-selected', 'true');
    expect(candidatures).toHaveAttribute('tabindex', '-1');

    aVenir.focus();
    fireEvent.keyDown(aVenir, { key: 'ArrowRight' });

    expect(passees).toHaveFocus();
    expect(passees).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('tabpanel')).toHaveAttribute('aria-labelledby', 'missions-tab-historique');
  });
});

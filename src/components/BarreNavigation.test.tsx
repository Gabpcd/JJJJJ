import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { BarreNavigation } from './BarreNavigation';

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: null, deconnexion: vi.fn() }),
}));

vi.mock('@/hooks/useMessagesNonLus', () => ({
  useMessagesNonLus: () => ({ count: 0 }),
}));

vi.mock('@/hooks/useNouvellesMissionsExplorer', () => ({
  useNouvellesMissionsExplorer: () => 0,
}));

vi.mock('@/components/PanneauNotifications', () => ({ BadgeNotification: () => null }));
vi.mock('@/components/AvatarUpload', () => ({ AvatarDisplay: () => null }));
vi.mock('@/components/ThemeToggle', () => ({ ThemeToggle: () => null }));

describe('BarreNavigation — groupes de navigation', () => {
  it('annonce et relie l’état ouvert du groupe au sous-menu', () => {
    render(
      <MemoryRouter initialEntries={['/etablissement/tableau-de-bord']}>
        <BarreNavigation role="ADMIN_ETABLISSEMENT" />
      </MemoryRouter>,
    );

    const declencheur = screen.getByRole('button', { name: 'Soignants' });
    expect(declencheur).toHaveAttribute('aria-expanded', 'false');

    fireEvent.click(declencheur);

    const contentId = declencheur.getAttribute('aria-controls');
    expect(declencheur).toHaveAttribute('aria-expanded', 'true');
    expect(contentId).toBeTruthy();
    expect(document.getElementById(contentId!)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Annuaire' })).toBeInTheDocument();
  });
});

import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { REGLES_INSTALLATION_LIBERAL } from '@/lib/regles-installation-liberal';
import { BarreNavigation } from './BarreNavigation';

const mocks = vi.hoisted(() => ({
  user: null as { id: string } | null,
  profil: null as Record<string, unknown> | null,
}));

const professionsLiberales = Object.entries(REGLES_INSTALLATION_LIBERAL)
  .filter(([, regle]) => regle.categorie !== 'NON_ELIGIBLE')
  .map(([profession]) => profession);

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user, deconnexion: vi.fn() }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => {
      const builder = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: () => Promise.resolve({ data: mocks.profil, error: null }),
        single: () => Promise.resolve({ data: mocks.profil, error: null }),
      };
      return builder;
    },
  },
}));

vi.mock('@/hooks/useEtabPermissions', () => ({
  useEtabPermissions: () => ({ permissions: { lecture_paiement: false, paiement: false } }),
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
  beforeEach(() => {
    mocks.user = null;
    mocks.profil = null;
  });

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

  it.each(professionsLiberales)(
    'affiche le parcours dans la navigation pour la profession éligible %s',
    async (profession) => {
      mocks.user = { id: 'soignant-ide' };
      mocks.profil = {
        prenom: 'Marie',
        nom: 'Lefèvre',
        profession,
        statut_liberal: null,
        type_exercice: 'SALARIE',
        heures_cumulees: 1200,
        avatar_url: null,
      };

      render(
        <MemoryRouter initialEntries={['/soignant/tableau-de-bord']}>
          <BarreNavigation role="SOIGNANT" />
        </MemoryRouter>,
      );

      expect(await screen.findByRole('button', { name: 'Passer en libéral' })).toBeInTheDocument();
    },
  );
});

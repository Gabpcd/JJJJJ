import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { invaliderProfilNavigation } from '@/lib/invaliderProfilNavigation';
import type { ReactElement } from 'react';
import { act, fireEvent, render as renderRTL, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { REGLES_INSTALLATION_LIBERAL } from '@/lib/regles-installation-liberal';
import { BarreNavigation } from './BarreNavigation';

let queryClient: QueryClient;
const render = (ui: ReactElement) => renderRTL(<QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>);

const mocks = vi.hoisted(() => ({
  user: null as { id: string } | null,
  profil: null as Record<string, unknown> | null,
  etablissementId: null as string | null,
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

vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => ({ etablissementId: mocks.etablissementId }) }));

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
    queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    mocks.user = null;
    mocks.profil = null;
    mocks.etablissementId = null;
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

it('actualise les liens après une modification de profil, sans remonter la navigation', async () => {
  queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  mocks.user = { id: 'soignant-ide' };
  mocks.profil = { profession: 'IDE', statut_liberal: null, type_exercice: 'SALARIE', prenom: 'Marie', nom: 'Test' };
  render(<MemoryRouter initialEntries={['/soignant/tableau-de-bord']}><BarreNavigation role="SOIGNANT" /></MemoryRouter>);
  const navigation = screen.getByRole('navigation', { name: 'Sidebar' });
  expect(await screen.findByRole('button', { name: 'Passer en libéral' })).toBeInTheDocument();
  mocks.profil = { ...mocks.profil, statut_liberal: 'ACTIF', type_exercice: 'LIBERAL' };
  await act(async () => invaliderProfilNavigation(queryClient, mocks.user!.id));
  fireEvent.click(await screen.findByRole('button', { name: 'Finances' }));
  expect(await screen.findByRole('button', { name: 'Stripe Connect' })).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Passer en libéral' })).not.toBeInTheDocument();
  expect(screen.getByRole('navigation', { name: 'Sidebar' })).toBe(navigation);
  mocks.profil = { ...mocks.profil, statut_liberal: null, type_exercice: 'SALARIE' };
  await act(async () => invaliderProfilNavigation(queryClient, mocks.user!.id));
  expect(await screen.findByRole('button', { name: 'Passer en libéral' })).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Stripe Connect' })).not.toBeInTheDocument();
});

it('charge le nom du véritable établissement pour un membre dont user.id diffère', async () => {
  queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  mocks.user = { id: 'membre-rh' };
  mocks.etablissementId = 'etablissement-partage';
  mocks.profil = { nom: 'Résidence des Fleurs', logo_url: null };
  render(<MemoryRouter initialEntries={['/etablissement/tableau-de-bord']}><BarreNavigation role="ADMIN_ETABLISSEMENT" /></MemoryRouter>);
  expect(await screen.findByText('Résidence des Fleurs')).toBeInTheDocument();
  expect(queryClient.getQueryData(['navigation-profil', 'membre-rh', 'ADMIN_ETABLISSEMENT', 'etablissement-partage'])).toMatchObject({ prenom: 'Résidence des Fleurs' });
});

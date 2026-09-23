import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import RechercheMissions from './RechercheMissions';

const mocks = vi.hoisted(() => ({ charger: vi.fn(), recharger: vi.fn() }));
vi.mock('@/hooks/useExplorationMissions', () => ({ useExplorationMissions: mocks.charger }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'compte-a', email: 'a@example.invalid' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ resolved: true, parcours: { donnees: { profession: 'IDE' } } }) }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => {} }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));
vi.mock('@/hooks/useNouvellesMissionsExplorer', () => ({ marquerExplorerVisite: () => {} }));
vi.mock('@/hooks/usePullToRefresh', () => ({ usePullToRefresh: () => ({ pullDistance: 0, refreshing: false }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/FiltresSauvegardes', () => ({ FiltresSauvegardes: () => null }));
vi.mock('@/components/swipe/QuizPreferencesSwipe', () => ({ QuizPreferencesSwipe: () => null, CLE_QUIZ_PREFS: 'quiz' }));
vi.mock('@/components/swipe/VueSwipeMissions', () => ({ VueSwipeMissions: () => null }));
vi.mock('@/components/CarteMissionSoignant', () => ({ CarteMissionSoignant: ({ mission, onClick }: any) => <button onClick={onClick}>{mission.intitule}</button> }));
vi.mock('@/components/BandeauDocumentsManquants', () => ({ BandeauDocumentsManquants: () => null }));
vi.mock('@/components/BandeauProfilIncomplet', () => ({ BandeauProfilIncomplet: () => null }));

const offre = {
  id: 'mission-a', intitule: 'Renfort infirmier', type_contrat_recherche: 'SALARIE',
  etablissements: { adresse_ville: 'Paris' },
};

function afficher(client = new QueryClient()) {
  const arbre = <QueryClientProvider client={client}><MemoryRouter><RechercheMissions /></MemoryRouter></QueryClientProvider>;
  return { ...render(arbre), client };
}

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear(); sessionStorage.clear();
  localStorage.setItem('jolene_missions_view_pref:compte-a', 'liste');
  mocks.charger.mockReturnValue({
    soignant: null, missions: [offre], loading: false, actualisation: false,
    erreurChargement: false, rcpExpiree: false, rcpExpireLe: null, recharger: mocks.recharger,
  });
});
afterEach(cleanup);

describe('Explorer : retour et erreurs affichés', () => {
  it('garde la liste visible sous l’alerte si le rafraîchissement échoue', () => {
    mocks.charger.mockReturnValue({ ...mocks.charger(), erreurChargement: true });
    afficher();
    expect(screen.getByRole('alert')).toHaveTextContent('Les derniers résultats restent affichés');
    expect(screen.getByRole('button', { name: 'Renfort infirmier' })).toBeVisible();
    expect(screen.queryByText('Aucune mission trouvée')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.recharger).toHaveBeenCalledTimes(1);
  });

  it('affiche une erreur sans faux état vide quand aucun résultat n’a pu être récupéré', () => {
    mocks.charger.mockReturnValue({ ...mocks.charger(), missions: [], erreurChargement: true });
    afficher();
    expect(screen.getByRole('alert')).toHaveTextContent('Les missions n’ont pas pu être chargées');
    expect(screen.queryByText('Aucune mission trouvée')).not.toBeInTheDocument();
  });

  it('applique le contrat de filtres préparés puis le conserve après un démontage', async () => {
    sessionStorage.setItem('jolene.filtres_a_appliquer', JSON.stringify({
      audience: 'SOIGNANT_RECHERCHE_MISSIONS', filtres: { villeRecherche: 'Paris', profession: 'IDE', tauxMin: 29 },
    }));
    const premier = afficher();
    await waitFor(() => expect(mocks.charger).toHaveBeenLastCalledWith(expect.objectContaining({ profession: 'IDE', tauxMin: 29 })));
    expect(sessionStorage.getItem('jolene.filtres_a_appliquer')).toBeNull();
    premier.unmount();
    afficher(premier.client);
    expect(mocks.charger).toHaveBeenLastCalledWith(expect.objectContaining({ profession: 'IDE', tauxMin: 29 }));
    expect(screen.getByText('📍 Paris')).toBeInTheDocument();
  });
});

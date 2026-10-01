import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import DashboardEtablissement from './DashboardEtablissement';

const mocks = vi.hoisted(() => ({
  publication: undefined as boolean | null | undefined,
  bloqueLe: null as string | null,
  query: vi.fn(),
  lireScope: vi.fn(),
  scope: {
    user: { id: 'recette' }, etablissementId: 'recette' as string | null,
    parcours: { type_compte: 'ETABLISSEMENT' } as { type_compte: string } | null,
    loading: false, resolved: true, error: null as Error | null, retry: vi.fn(),
  },
}));
vi.mock('@tanstack/react-query', () => ({
  useQuery: (options: { enabled: boolean }) => {
    mocks.query(options);
    return { isLoading: false, data: options.enabled ? {
      etab: { nom: 'Établissement de recette', peut_publier_missions: mocks.publication, bloque_auto_le: mocks.bloqueLe },
      aDejaPublie: false,
    } : undefined };
  },
  useQueryClient: () => ({ resetQueries: vi.fn() }),
}));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => mocks.lireScope() }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: { children: React.ReactNode }) => <main>{children}</main> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.lireScope.mockReset().mockImplementation(() => mocks.scope);
  mocks.publication = undefined;
  mocks.bloqueLe = null;
  Object.assign(mocks.scope, { etablissementId: 'recette', parcours: { type_compte: 'ETABLISSEMENT' }, loading: false, resolved: true, error: null });
});

describe('Accueil d’un compte établissement sans dossier', () => {
  it.each([
    ['Préparer une mission', '/etablissement/missions/creer'],
    ['Compléter mon établissement', '/inscription/completer'],
  ])('propose %s sans inventer de données métier', (action, destination) => {
    mocks.scope.etablissementId = null;
    render(<MemoryRouter><Routes>
      <Route path="/" element={<DashboardEtablissement />} />
      <Route path={destination} element={<h1>Destination attendue</h1>} />
    </Routes></MemoryRouter>);
    expect(screen.getByRole('heading', { name: 'Préparez votre première mission' })).toBeInTheDocument();
    expect(screen.getByText('À compléter avant publication')).toBeInTheDocument();
    expect(screen.queryByText('Paiements à jour')).not.toBeInTheDocument();
    expect(screen.queryByText('Soignants ce mois')).not.toBeInTheDocument();
    expect(screen.queryByText('Vérification en cours')).not.toBeInTheDocument();
    expect(screen.queryByText('Validé', { exact: true })).not.toBeInTheDocument();
    expect(mocks.query).toHaveBeenCalledWith(expect.objectContaining({ enabled: false }));
    fireEvent.click(screen.getByRole('button', { name: action }));
    expect(screen.getByRole('heading', { name: 'Destination attendue' })).toBeInTheDocument();
  });

  it('attend le scope au lieu de présenter une première mission ou des finances', () => {
    Object.assign(mocks.scope, { etablissementId: null, loading: true, resolved: false });
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.queryByTestId('dashboard-etablissement-ready')).not.toBeInTheDocument();
    expect(screen.queryByText('Paiements à jour')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Préparer une mission' })).not.toBeInTheDocument();
  });

  it('affiche une erreur de résolution avec reprise sans la confondre avec un dossier absent', () => {
    Object.assign(mocks.scope, { etablissementId: null, error: new Error('indisponible') });
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByRole('alert')).toHaveTextContent('Impossible de vérifier votre établissement');
    expect(screen.queryByText('Paiements à jour')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Préparer une mission' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.scope.retry).toHaveBeenCalledOnce();
  });

  it('ne traite pas un rattachement manquant sans parcours comme une nouvelle inscription', () => {
    Object.assign(mocks.scope, { etablissementId: null, parcours: null });
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByRole('heading', { name: 'Établissement non rattaché' })).toBeInTheDocument();
    expect(screen.queryByText('Paiements à jour')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Préparer une mission' })).not.toBeInTheDocument();
  });

  it('conserve la reprise du périmètre de la page même si une seconde lecture verrait un cache différent', () => {
    Object.assign(mocks.scope, { etablissementId: null, parcours: null });
    const autreRetry = vi.fn();
    mocks.lireScope.mockReturnValueOnce(mocks.scope).mockReturnValue({
      ...mocks.scope, etablissementId: 'cache-resolu-ailleurs', retry: autreRetry,
    });
    const vue = render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByRole('alert')).toHaveTextContent('Établissement non rattaché');
    expect(mocks.query).toHaveBeenCalledWith(expect.objectContaining({ enabled: false }));
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.scope.retry).toHaveBeenCalledOnce();
    expect(autreRetry).not.toHaveBeenCalled();
    expect(screen.queryByTestId('dashboard-etablissement-ready')).not.toBeInTheDocument();

    vue.rerender(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByTestId('dashboard-etablissement-ready')).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Établissement non rattaché' })).not.toBeInTheDocument();
    expect(mocks.query).toHaveBeenLastCalledWith(expect.objectContaining({ enabled: true }));
  });
});

describe('Cohérence de la vérification sur la première mission', () => {
  it.each([false, null, undefined])('ne confirme pas la vérification quand peut_publier_missions vaut %s', (publication) => {
    mocks.publication = publication;
    mocks.bloqueLe = null;
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByText('Votre compte est en cours de vérification')).toBeInTheDocument();
    expect(screen.getByText('Vérification en cours')).toBeInTheDocument();
    expect(screen.queryByText('Validé', { exact: true })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Publier une mission' })).toBeEnabled();
  });

  it('confirme la vérification seulement lorsque la publication est autorisée explicitement', () => {
    mocks.publication = true;
    mocks.bloqueLe = null;
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByText('Validé', { exact: true })).toBeInTheDocument();
    expect(screen.queryByText('Votre compte est en cours de vérification')).not.toBeInTheDocument();
    expect(screen.queryByText('Vérification en cours')).not.toBeInTheDocument();
  });
});

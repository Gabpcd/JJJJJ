import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MissionsPubliquesSEO } from './MissionsPubliquesSEO';
import { RechercheMissionsPublique } from '@/pages/PageAccueil';
import { DELAI_RECHERCHE_PUBLIQUE_MS } from '@/hooks/useMissionsPubliques';

const m = vi.hoisted(() => ({ rpc: vi.fn(), navigate: vi.fn(), responses: [] as any[] }));
vi.mock('@/integrations/supabase/public-client', () => ({ publicSupabase: { rpc: m.rpc } }));
vi.mock('@/lib/handleError', () => ({ handleErrorSilent: vi.fn() }));
vi.mock('@/components/SelectProfession', () => ({ SelectProfession: ({ value, onChange, triggerId }: any) => (
  <select id={triggerId} value={value} onChange={e => onChange(e.target.value)}><option value="">Toutes</option><option value="IDE">IDE</option></select>
) }));
vi.mock('react-router-dom', async () => ({ ...await vi.importActual('react-router-dom'), useNavigate: () => m.navigate }));
const mission = (id = 'mission-paris', intitule = 'Mission infirmière Paris') => ({
  id, intitule, ville: 'Paris', code_postal: '75011', profession_requise: 'IDE',
  debut_le: '2026-09-29T07:00:00Z', fin_le: '2026-09-29T15:00:00Z',
  taux_horaire_base: 30, total_count: 1, type_contrat_recherche: 'SALARIE',
});
const reponse = (rows: unknown = []) => ({ data: rows, error: null });
function ouvrir(surface: 'accueil' | 'seo') {
  return render(<MemoryRouter>{surface === 'accueil'
    ? <RechercheMissionsPublique navigate={m.navigate} />
    : <MissionsPubliquesSEO profession="IDE" ville="Paris" campagne="seo-paris" />}</MemoryRouter>);
}

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  vi.stubGlobal('IntersectionObserver', class { observe() {} unobserve() {} disconnect() {} });
  m.responses = [];
  m.rpc.mockImplementation(() => {
    const promise = Promise.resolve(m.responses.shift() ?? reponse());
    return Object.assign(promise, { abortSignal: () => promise });
  });
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

for (const surface of ['accueil', 'seo'] as const) {
  describe(`Recherche publique ${surface}`, () => {
    it('distingue un résultat vide réussi d’une panne et restaure les missions au réessai', async () => {
      m.responses = [{ data: null, error: { message: 'Service unavailable', status: 503 } }, reponse([mission()])];
      ouvrir(surface);
      expect(await screen.findByRole('alert')).toHaveTextContent('Recherche indisponible');
      expect(screen.queryByText(/Pas de mission pour le moment|Aucune mission ne correspond/)).not.toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
      expect(await screen.findByText('Mission infirmière Paris')).toBeInTheDocument();
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });

    it('affiche l’état vide seulement pour une réponse réussie sans mission', async () => {
      ouvrir(surface);
      expect(await screen.findByText(/Pas de mission pour le moment|Aucune mission ne correspond/)).toBeInTheDocument();
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });

    it('affiche une erreur pour un élément de résultat invalide sans casser l’écran', async () => {
      m.responses = [reponse([null])];
      ouvrir(surface);
      expect(await screen.findByRole('alert')).toHaveTextContent('Recherche indisponible');
      expect(screen.queryByText(/Pas de mission pour le moment|Aucune mission ne correspond/)).not.toBeInTheDocument();
    });

    it('traite un rejet réseau et une réponse mal formée comme erreurs, pas comme zéro offre', async () => {
      m.responses = [Promise.reject(new TypeError('Failed to fetch')), reponse({ unexpected: [] })];
      ouvrir(surface);
      expect(await screen.findByRole('alert')).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
      await waitFor(() => expect(m.rpc).toHaveBeenCalledTimes(2));
      expect(await screen.findByRole('alert')).toHaveTextContent('Recherche indisponible');
      expect(screen.queryByText(/Pas de mission pour le moment|Aucune mission ne correspond/)).not.toBeInTheDocument();
    });
  });
}

it('ignore la réponse périmée d’une première recherche plus lente', async () => {
  let terminer!: (response: unknown) => void;
  m.responses = [new Promise(resolve => { terminer = resolve; }), reponse([mission('lyon', 'Mission Lyon')])];
  const view = render(<MemoryRouter><MissionsPubliquesSEO ville="Paris" campagne="villes" /></MemoryRouter>);
  view.rerender(<MemoryRouter><MissionsPubliquesSEO ville="Lyon" campagne="villes" /></MemoryRouter>);
  expect(await screen.findByText('Mission Lyon')).toBeInTheDocument();
  await act(async () => terminer(reponse([mission()])));
  expect(screen.getByText('Mission Lyon')).toBeInTheDocument();
  expect(screen.queryByText('Mission infirmière Paris')).not.toBeInTheDocument();
});

it('conserve les anciens résultats en les signalant quand la requête suivante est annulée', async () => {
  m.responses = [reponse([mission()]), { data: null, error: { name: 'AbortError', message: 'aborted' } }];
  const view = render(<MemoryRouter><MissionsPubliquesSEO ville="Paris" campagne="villes" /></MemoryRouter>);
  expect(await screen.findByText('Mission infirmière Paris')).toBeInTheDocument();
  view.rerender(<MemoryRouter><MissionsPubliquesSEO ville="Lyon" campagne="villes" /></MemoryRouter>);
  expect(await screen.findByRole('alert')).toBeInTheDocument();
  expect(screen.getByText('Mission infirmière Paris')).toBeInTheDocument();
  expect(screen.getByText('Résultats de la recherche précédente.')).toBeInTheDocument();
  expect(screen.queryByText(/Aucune mission ne correspond/)).not.toBeInTheDocument();
});

it('met fin au chargement après le délai réseau et propose un réessai', async () => {
  vi.useFakeTimers();
  m.responses = [new Promise(() => {})];
  ouvrir('seo');
  expect(screen.getByRole('status')).toHaveTextContent('Recherche des missions');
  await act(async () => { vi.advanceTimersByTime(DELAI_RECHERCHE_PUBLIQUE_MS + 1); });
  expect(screen.getByRole('alert')).toHaveTextContent('Recherche indisponible');
  expect(screen.queryByRole('status')).not.toBeInTheDocument();
});

it('transmet métier, ville et campagne SEO à l’inscription, sans créer d’alerte', async () => {
  ouvrir('seo');
  await screen.findByText(/Aucune mission ne correspond/);
  fireEvent.click(screen.getByRole('button', { name: /Voir toutes les missions et postuler/ }));
  const url = new URL(m.navigate.mock.calls[0][0], 'https://jolene.app');
  expect(Object.fromEntries(url.searchParams)).toEqual({ profession: 'IDE', ville: 'Paris', utm_source: 'seo', utm_medium: 'landing', utm_campaign: 'seo-paris' });
  expect(JSON.parse(sessionStorage.getItem('jolene.filtres_a_appliquer')!)).toEqual({ audience: 'SOIGNANT_RECHERCHE_MISSIONS', filtres: { profession: 'IDE', villeRecherche: 'Paris' } });
  expect(m.rpc).toHaveBeenCalledTimes(1);
  expect(m.rpc).toHaveBeenCalledWith('fn_missions_publiques_recherche', { p_profession: 'IDE', p_ville: 'Paris' });
});

it('conserve la dernière saisie de l’accueil au clic vers l’inscription', async () => {
  ouvrir('accueil');
  await screen.findByText(/Pas de mission pour le moment/);
  fireEvent.change(screen.getByLabelText('Profession à rechercher'), { target: { value: 'IDE' } });
  fireEvent.change(screen.getByLabelText('Ville ou code postal'), { target: { value: 'Saint-Étienne' } });
  fireEvent.click(screen.getByRole('button', { name: 'Créer mon compte et retrouver ma recherche →' }));
  const url = new URL(m.navigate.mock.calls[0][0], 'https://jolene.app');
  expect(url.searchParams.get('profession')).toBe('IDE');
  expect(url.searchParams.get('ville')).toBe('Saint-Étienne');
  expect(JSON.parse(sessionStorage.getItem('jolene.filtres_a_appliquer')!).filtres.villeRecherche).toBe('Saint-Étienne');
});

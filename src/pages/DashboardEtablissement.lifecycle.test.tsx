import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Link, MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import DashboardEtablissement from './DashboardEtablissement';

type Resultat = { data: unknown; error: { message: string } | null };
type LectureStats = { signal?: AbortSignal; terminer: (resultat: Resultat) => void };
const mocks = vi.hoisted(() => ({
  compte: 'etab-a',
  rpc: vi.fn(),
  from: vi.fn(),
  error: vi.fn(),
  warn: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc, from: mocks.from } }));
vi.mock('@/lib/logger', () => ({ logger: { error: mocks.error, warn: mocks.warn, info: vi.fn(), debug: vi.fn() } }));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => ({
  user: { id: mocks.compte }, etablissementId: mocks.compte, parcours: null,
  loading: false, resolved: true, error: null, retry: vi.fn(),
}) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: { children: React.ReactNode }) => (
  <main><Link to="/ailleurs">Quitter le tableau de bord</Link>{children}</main>
) }));
vi.mock('@/components/SkeletonCard', () => ({ SkeletonDashboard: () => <p>Chargement du tableau de bord</p> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

let lectures: LectureStats[];
function requete(resultat: Resultat, suspendre = false) {
  let signal: AbortSignal | undefined;
  const builder: Record<string, any> = {};
  for (const nom of ['select', 'eq', 'order', 'limit', 'in', 'gte', 'lte', 'not']) {
    builder[nom] = () => builder;
  }
  builder.abortSignal = (valeur: AbortSignal) => { signal = valeur; return builder; };
  builder.then = (succes: (valeur: Resultat) => unknown, erreur: (raison: unknown) => unknown) => {
    const reponse = suspendre ? new Promise<Resultat>((resolve) => {
      const terminer = (valeur: Resultat) => { signal?.removeEventListener('abort', annuler); resolve(valeur); };
      // Supabase restitue aussi les échecs fetch sous forme de données, sans throw.
      const annuler = () => terminer({ data: null, error: { message: 'TypeError: Load failed' } });
      lectures.push({ signal, terminer });
      if (signal?.aborted) annuler();
      else signal?.addEventListener('abort', annuler, { once: true });
    }) : Promise.resolve(resultat);
    return reponse.then(succes, erreur);
  };
  return builder;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.compte = 'etab-a';
  lectures = [];
  mocks.from.mockImplementation(() => requete({ data: [], error: null }));
  mocks.rpc.mockImplementation((nom: string) => requete({
    data: nom === 'fn_mon_etablissement_complet'
      ? { nom: mocks.compte, peut_publier_missions: true }
      : [],
    error: null,
  }, nom === 'fn_stats_dashboard_etablissement'));
});

function afficher() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  const arbre = () => <QueryClientProvider client={client}><MemoryRouter>
    <Routes>
      <Route path="/" element={<DashboardEtablissement />} />
      <Route path="/ailleurs" element={<Link to="/">Revenir au tableau de bord</Link>} />
    </Routes>
  </MemoryRouter></QueryClientProvider>;
  const vue = render(arbre());
  return { client, ...vue, actualiser: () => vue.rerender(arbre()) };
}

async function terminerStats(index: number) {
  await act(async () => lectures[index].terminer({ data: { missions_ouvertes: 2 }, error: null }));
  await screen.findByTestId('dashboard-etablissement-ready');
}

describe('Lectures du dashboard établissement pendant une navigation', () => {
  it('annule au démontage, ne publie pas de résultat partiel et recharge au retour', async () => {
    const { client } = afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    fireEvent.click(screen.getByRole('link', { name: 'Quitter le tableau de bord' }));
    await waitFor(() => expect(lectures[0].signal?.aborted).toBe(true));
    expect(mocks.error).not.toHaveBeenCalled();
    expect(mocks.warn).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_ecrire_audit_safe', expect.anything());
    expect(client.getQueryData(['dashboard-etablissement', 'etab-a', 'etab-a'])).toBeUndefined();

    fireEvent.click(screen.getByRole('link', { name: 'Revenir au tableau de bord' }));
    await waitFor(() => expect(lectures).toHaveLength(2));
    expect(lectures[1].signal?.aborted).toBe(false);
    await terminerStats(1);
    expect(screen.queryByText(/Certaines données n'ont pas pu être chargées/)).not.toBeInTheDocument();
  });

  it('conserve la vraie panne réseau et son message tant que la vue reste active', async () => {
    afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    await act(async () => lectures[0].terminer({ data: null, error: { message: 'TypeError: Load failed' } }));
    expect(await screen.findByText(/Certaines données n'ont pas pu être chargées/)).toBeVisible();
    expect(lectures[0].signal?.aborted).toBe(false);
    expect(mocks.error).toHaveBeenCalledWith('[DashboardEtab] Erreur stats RPC', { message: 'TypeError: Load failed' });
  });

  it('reprend la lecture annulée quand le document revient du bfcache', async () => {
    afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    await act(async () => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })));
    expect(lectures[0].signal?.aborted).toBe(true);
    expect(mocks.error).not.toHaveBeenCalled();
    await act(async () => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    await waitFor(() => expect(lectures).toHaveLength(2));
    await terminerStats(1);
    expect(screen.queryByText('Chargement du tableau de bord')).not.toBeInTheDocument();
    expect(mocks.error).not.toHaveBeenCalled();
  });

  it('annule la lecture de l’ancien compte sans interrompre celle du nouveau', async () => {
    const vue = afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    mocks.compte = 'etab-b';
    vue.actualiser();
    await waitFor(() => expect(lectures).toHaveLength(2));
    expect(lectures[0].signal?.aborted).toBe(true);
    expect(lectures[1].signal?.aborted).toBe(false);
    await terminerStats(1);
    expect(vue.client.getQueryData(['dashboard-etablissement', 'etab-a', 'etab-a'])).toBeUndefined();
    expect(vue.client.getQueryData(['dashboard-etablissement', 'etab-b', 'etab-b'])).toMatchObject({
      etab: { nom: 'etab-b' }, erreurPartielle: false,
    });
    expect(mocks.error).not.toHaveBeenCalled();
  });
});

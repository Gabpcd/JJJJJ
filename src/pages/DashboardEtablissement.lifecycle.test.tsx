import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Link, MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
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
const annulationNative = Object.getOwnPropertyDescriptor(AbortSignal.prototype, 'throwIfAborted');
beforeAll(() => {
  // Exercer aussi la cible iOS 15.0, où cette API moderne est absente.
  Object.defineProperty(AbortSignal.prototype, 'throwIfAborted', { configurable: true, value: undefined });
});
afterAll(() => {
  if (annulationNative) Object.defineProperty(AbortSignal.prototype, 'throwIfAborted', annulationNative);
  else Reflect.deleteProperty(AbortSignal.prototype, 'throwIfAborted');
});

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
  mocks.rpc.mockImplementation((nom: string) => {
    const reponses: Record<string, unknown> = {
      fn_mon_etablissement_complet: { nom: mocks.compte, peut_publier_missions: true },
      fn_mes_soignants_etablissement: [],
      fn_stats_dashboard_etablissement: null,
      fn_ecrire_audit_safe: null,
      fn_mon_score_etab: { score_qualite: null, niveau: null, composantes: {
        notation_pct: null, nb_notations: 0, paiement_pct: null, nb_factures: 0, nb_litiges_perdus: 0,
      } },
      fn_bfa_info: { eligible: false },
      fn_stats_etab_complements: { soignants_mois_precedent: 0, cout_brut_ce_mois: 0, heures_ce_mois: 0,
        missions_pourvues_ce_mois: 0, missions_publiees_ce_mois: 0 },
    };
    if (!(nom in reponses)) throw new Error(`RPC non prévue dans cette simulation : ${nom}`);
    return requete({ data: reponses[nom], error: null }, nom === 'fn_stats_dashboard_etablissement');
  });
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
  it('charge sans AbortSignal.throwIfAborted comme sur iOS 15.0', async () => {
    const { client } = afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    expect(lectures[0].signal?.throwIfAborted).toBeUndefined();
    await terminerStats(0);
    expect(client.getQueryData(['dashboard-etablissement', 'etab-a', 'etab-a'])).toMatchObject({
      etab: { nom: 'etab-a' }, erreurPartielle: false,
    });
    expect(mocks.error).not.toHaveBeenCalled();
  });

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

  it('reprend après un départ refusé sans afficher un dashboard vide entre-temps', async () => {
    afficher();
    await waitFor(() => expect(lectures).toHaveLength(1));
    const refuser = (event: Event) => event.preventDefault();
    window.addEventListener('beforeunload', refuser);
    try {
      const depart = new Event('beforeunload', { cancelable: true });
      await act(async () => { window.dispatchEvent(depart); });
      expect(depart.defaultPrevented).toBe(true);
      expect(lectures[0].signal?.aborted).toBe(true);
      expect(screen.queryByTestId('dashboard-etablissement-ready')).not.toBeInTheDocument();
      expect(screen.getByText('Chargement du tableau de bord')).toBeVisible();
      expect(mocks.error).not.toHaveBeenCalled();
      fireEvent.focus(window);
      await waitFor(() => expect(lectures).toHaveLength(2));
      await terminerStats(1);
      expect(mocks.error).not.toHaveBeenCalled();
    } finally { window.removeEventListener('beforeunload', refuser); }
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

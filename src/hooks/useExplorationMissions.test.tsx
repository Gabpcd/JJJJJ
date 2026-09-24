import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { chargerMissionsExploration, useExplorationMissions } from './useExplorationMissions';

const mocks = vi.hoisted(() => ({
  from: vi.fn(), profils: vi.fn(), missions: vi.fn(), creneaux: vi.fn(), etablissements: vi.fn(), publiques: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));
vi.mock('@/lib/mission-creneaux-pagines', () => ({ chargerCreneauxMissionsPagines: mocks.creneaux }));
vi.mock('@/lib/etablissements', () => ({ enrichirEtablissements: mocks.etablissements }));
vi.mock('@/lib/donnees-test', () => ({ filtrerMissionsPlaywright: (missions: unknown[]) => missions }));
vi.mock('@/lib/profession-hierarchy', () => ({ getMissionsCompatiblesFilter: () => null }));
vi.mock('@/components/planning/planning-candidat', () => ({ associerCreneauxAuxMissions: (missions: unknown[]) => missions }));
vi.mock('@/lib/explorationInscription', () => ({
  chargerMissionsInscription: mocks.publiques,
  missionCorrespondProfessionInscription: (requise: string, selection: string, compte: string) => requise === (selection || compte),
}));

const profil = { profession: 'IDE', type_exercice: 'SALARIE', rayon_deplacement_km: 50 } as any;
const offre = { id: 'mission-a', etablissement_id: 'etab-a', intitule: 'Mission disponible' };
const options = {
  userId: 'compte-a', email: 'a@example.invalid', parcours: null,
  roleResolved: true, enabled: true, preferencesInitialisees: true, profession: '', tauxMin: 0,
  urgentesOnly: false, etablissementId: null,
};

function builder(reponse: () => Promise<unknown>) {
  const query: any = {};
  for (const method of ['select', 'eq', 'gte', 'is', 'order', 'limit', 'or', 'abortSignal', 'maybeSingle']) {
    query[method] = vi.fn(() => query);
  }
  query.then = (resolve: (data: unknown) => unknown, reject: (error: unknown) => unknown) => reponse().then(resolve, reject);
  return query;
}

const clients: QueryClient[] = [];
function contexte() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  clients.push(client);
  return { client, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> };
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.profils.mockResolvedValue({ data: profil, error: null });
  mocks.missions.mockResolvedValue({ data: [offre], error: null });
  mocks.from.mockImplementation((table: string) => builder(table === 'soignants' ? mocks.profils : mocks.missions));
  mocks.creneaux.mockResolvedValue([]);
  mocks.etablissements.mockImplementation(async (missions: unknown[]) => missions);
  mocks.publiques.mockResolvedValue([{ ...offre, profession_requise: 'AS' }]);
});
afterEach(() => { cleanup(); clients.splice(0).forEach(client => client.clear()); });

describe('chargement et cache Explorer', () => {
  it('réutilise les résultats immédiatement au retour sans refaire les lectures fraîches', async () => {
    const { wrapper } = contexte();
    const premier = renderHook(() => useExplorationMissions(options), { wrapper });
    await waitFor(() => expect(premier.result.current.missions).toEqual([offre]));
    expect(mocks.profils).toHaveBeenCalledTimes(1);
    expect(mocks.missions).toHaveBeenCalledTimes(1);
    premier.unmount();
    const retour = renderHook(() => useExplorationMissions(options), { wrapper });
    expect(retour.result.current.loading).toBe(false);
    expect(retour.result.current.missions).toEqual([offre]);
    expect(mocks.profils).toHaveBeenCalledTimes(1);
    expect(mocks.missions).toHaveBeenCalledTimes(1);
  });

  it('ne transmet pas les résultats d’un compte au compte suivant', async () => {
    const { wrapper } = contexte();
    const session = renderHook((props) => useExplorationMissions(props), { wrapper, initialProps: options });
    await waitFor(() => expect(session.result.current.missions).toEqual([offre]));
    mocks.profils.mockImplementation(() => new Promise(() => {}));
    session.rerender({ ...options, userId: 'compte-b' });
    expect(session.result.current.missions).toEqual([]);
    expect(session.result.current.loading).toBe(true);
  });

  it('conserve les résultats et expose une erreur quand leur actualisation échoue', async () => {
    const { wrapper } = contexte();
    const hook = renderHook(() => useExplorationMissions(options), { wrapper });
    await waitFor(() => expect(hook.result.current.missions).toEqual([offre]));
    mocks.missions.mockResolvedValue({ data: null, error: new Error('Indisponible') });
    await act(async () => { await hook.result.current.recharger(); });
    await waitFor(() => expect(hook.result.current.erreurChargement).toBe(true));
    expect(hook.result.current.missions).toEqual([offre]);
    expect(hook.result.current.loading).toBe(false);
  });

  it('attend réellement la fin du rafraîchissement au lieu d’un délai décoratif', async () => {
    const { wrapper } = contexte();
    const hook = renderHook(() => useExplorationMissions(options), { wrapper });
    await waitFor(() => expect(hook.result.current.missions).toEqual([offre]));
    let terminer!: (value: unknown) => void;
    mocks.missions.mockImplementation(() => new Promise(resolve => { terminer = resolve; }));
    let termine = false;
    let rafraichissement!: Promise<unknown>;
    act(() => { rafraichissement = hook.result.current.recharger().then(() => { termine = true; }); });
    await waitFor(() => expect(hook.result.current.actualisation).toBe(true));
    expect(termine).toBe(false);
    await act(async () => { terminer({ data: [], error: null }); await rafraichissement; });
    await waitFor(() => expect(hook.result.current.missions).toEqual([]));
    expect(termine).toBe(true);
  });

  it('attend le rôle puis utilise uniquement le parcours de découverte pour un compte incomplet', async () => {
    const { wrapper } = contexte();
    const initial = { ...options, roleResolved: false, parcours: undefined as any };
    const hook = renderHook((props) => useExplorationMissions(props), { wrapper, initialProps: initial });
    expect(mocks.from).not.toHaveBeenCalled();
    hook.rerender({ ...initial, roleResolved: true, parcours: { donnees: { profession: 'AS' } } });
    await waitFor(() => expect(hook.result.current.missions).toHaveLength(1));
    expect(mocks.publiques).toHaveBeenCalledTimes(1);
    expect(mocks.from).not.toHaveBeenCalled();
  });

  it('charge créneaux et établissements en parallèle après la liste', async () => {
    let terminer!: (creneaux: unknown[]) => void;
    mocks.creneaux.mockImplementation(() => new Promise(resolve => { terminer = resolve; }));
    const chargement = chargerMissionsExploration(options, profil, new AbortController().signal);
    await waitFor(() => expect(mocks.etablissements).toHaveBeenCalledWith([offre]));
    expect(mocks.creneaux).toHaveBeenCalledTimes(1);
    terminer([]);
    await expect(chargement).resolves.toEqual([offre]);
  });

  it('oublie une RCP supprimée puis reflète son remplacement après invalidation', async () => {
    const { wrapper, client } = contexte();
    mocks.profils.mockResolvedValue({ data: { ...profil, type_exercice: 'LIBERAL' }, error: null });
    const ancienne = { statut_verification: 'VALIDE', valide_jusqua: '2099-12-31', supprime_le: null as string | null };
    let documents = [ancienne];
    const lecturesRcp: any[] = [];
    mocks.from.mockImplementation((table: string) => {
      if (table !== 'documents_soignants') return builder(table === 'soignants' ? mocks.profils : mocks.missions);
      const query = builder(async () => {
        const exclutSupprimes = query.is.mock.calls.some(([champ, valeur]: unknown[]) => champ === 'supprime_le' && valeur === null);
        return { data: documents.filter(doc => !exclutSupprimes || doc.supprime_le === null).slice(0, 1), error: null };
      });
      lecturesRcp.push(query);
      return query;
    });
    const hook = renderHook(() => useExplorationMissions(options), { wrapper });
    await waitFor(() => expect(client.getQueryState(['explorer-rcp', options.userId])?.status).toBe('success'));
    expect(hook.result.current.rcpExpiree).toBe(false);
    ancienne.supprime_le = new Date().toISOString();
    await act(async () => { await client.invalidateQueries({ queryKey: ['explorer-rcp', options.userId] }); });
    await waitFor(() => expect(hook.result.current.rcpExpiree).toBe(true));
    documents = [{ ...ancienne, supprime_le: null }, ancienne];
    await act(async () => { await client.invalidateQueries({ queryKey: ['explorer-rcp', options.userId] }); });
    await waitFor(() => expect(hook.result.current.rcpExpiree).toBe(false));
    expect(lecturesRcp).toHaveLength(3);
    lecturesRcp.forEach(query => expect(query.is).toHaveBeenCalledWith('supprime_le', null));
  });
});

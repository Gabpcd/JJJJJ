import React from 'react';
import { readFileSync } from 'node:fs';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import FacturationEtablissement from './FacturationEtablissement';

const mocks = vi.hoisted(() => ({
  scope: {
    user: { id: 'membre-utilisateur-id' },
    etablissementId: 'membre-utilisateur-id' as string | null,
    loading: true,
    resolved: false,
    error: null as Error | null,
    retry: vi.fn(),
  },
  rpc: vi.fn(),
  from: vi.fn(),
  filtres: [] as Array<{ table: string; colonne: string; valeur: unknown }>,
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => mocks.scope }));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: vi.fn() }),
}));
vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock('@/components/SkeletonCard', () => ({ SkeletonDashboard: () => <div>Chargement</div> }));
vi.mock('@/components/FadeInView', () => ({
  FadeInView: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock('@/lib/stripe', () => ({ stripePromise: null }));
vi.mock('@stripe/react-stripe-js', () => ({
  EmbeddedCheckoutProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  EmbeddedCheckout: () => null,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    from: mocks.from,
    auth: { getSession: vi.fn() },
    functions: { invoke: vi.fn() },
  },
}));

function requeteEnAttente(table: string) {
  const attente = new Promise<never>(() => {});
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn((colonne: string, valeur: unknown) => {
      mocks.filtres.push({ table, colonne, valeur });
      return builder;
    }),
    in: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: vi.fn(() => builder),
    then: attente.then.bind(attente),
  };
  return builder;
}

function requeteResolue(table: string, data: unknown, error: unknown = null) {
  const response = Promise.resolve({ data, error });
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn((colonne: string, valeur: unknown) => {
      mocks.filtres.push({ table, colonne, valeur });
      return builder;
    }),
    in: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: vi.fn(() => builder),
    then: response.then.bind(response),
  };
  return builder;
}

const obligationsVides = {
  total_du: 0,
  total_soignants_du: 0,
  total_commissions_du: 0,
  nb_missions_non_payees: 0,
  nb_factures_impayees: 0,
  nb_factures_commission_historique: 0,
  missions_non_payees: [],
  paiements_soignants_en_attente: [],
  paiements_soignants_confirmes: [],
  factures_impayees: [],
  factures_commission_historique: [],
  missions_non_facturees: [],
};

function activerScope() {
  mocks.scope.loading = false;
  mocks.scope.resolved = true;
  mocks.scope.error = null;
  mocks.scope.etablissementId = 'etablissement-partage-id';
}

function configurerChargement(options?: {
  rpcError?: string;
  payloadError?: string;
  obligations?: Record<string, unknown>;
  etablissement?: Record<string, unknown>;
  missions?: unknown[];
  transfers?: unknown[];
  prelevements?: unknown[];
}) {
  mocks.rpc.mockImplementation((fn: string) => {
    if (fn === 'fn_mon_etablissement_complet') {
      return Promise.resolve({ data: options?.etablissement ?? { id: 'etablissement-partage-id' }, error: null });
    }
    if (fn === 'fn_obligations_financieres') {
      const data = options?.payloadError ? { error: options.payloadError } : (options?.obligations ?? obligationsVides);
      return Promise.resolve({ data, error: null });
    }
    if (fn === 'fn_paiements_etablissement') {
      return Promise.resolve({ data: { total_paye: 0 }, error: null });
    }
    if (fn === 'fn_mes_factures') {
      return Promise.resolve({
        data: options?.rpcError ? null : [],
        error: options?.rpcError ? { message: options.rpcError } : null,
      });
    }
    return Promise.resolve({ data: null, error: { message: `RPC inattendue: ${fn}` } });
  });
  mocks.from.mockImplementation((table: string) => {
    if (table === 'missions') return requeteResolue(table, options?.missions ?? []);
    if (table === 'stripe_transfers') return requeteResolue(table, options?.transfers ?? []);
    if (table === 'paiements_mission') return requeteResolue(table, options?.prelevements ?? []);
    return requeteResolue(table, null, { message: `Table inattendue: ${table}` });
  });
}

describe('FacturationEtablissement — périmètre des membres', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.filtres.length = 0;
    mocks.scope.user = { id: 'membre-utilisateur-id' };
    mocks.scope.etablissementId = 'membre-utilisateur-id';
    mocks.scope.loading = true;
    mocks.scope.resolved = false;
    mocks.scope.error = null;
    mocks.rpc.mockImplementation(() => new Promise<never>(() => {}));
    mocks.from.mockImplementation((table: string) => requeteEnAttente(table));
  });

  it('attend le scope puis filtre historique, transferts et prélèvements avec l’établissement partagé', async () => {
    const vue = render(
      <MemoryRouter>
        <FacturationEtablissement />
      </MemoryRouter>,
    );

    expect(mocks.from).not.toHaveBeenCalled();

    mocks.scope.loading = false;
    mocks.scope.resolved = true;
    mocks.scope.etablissementId = 'etablissement-partage-id';
    vue.rerender(
      <MemoryRouter>
        <FacturationEtablissement />
      </MemoryRouter>,
    );

    await waitFor(() => expect(mocks.from).toHaveBeenCalledTimes(3));

    const filtresEtablissement = mocks.filtres.filter(({ colonne }) => colonne === 'etablissement_id');
    expect(filtresEtablissement).toEqual([
      { table: 'missions', colonne: 'etablissement_id', valeur: 'etablissement-partage-id' },
      { table: 'stripe_transfers', colonne: 'etablissement_id', valeur: 'etablissement-partage-id' },
      { table: 'paiements_mission', colonne: 'etablissement_id', valeur: 'etablissement-partage-id' },
    ]);
    expect(filtresEtablissement).not.toContainEqual(expect.objectContaining({ valeur: 'membre-utilisateur-id' }));
  });

  it('affiche l’erreur de scope et relance sa résolution sans requête financière', async () => {
    mocks.scope.loading = false;
    mocks.scope.resolved = false;
    mocks.scope.error = new Error('RPC rôle indisponible');
    mocks.scope.etablissementId = null;

    render(
      <MemoryRouter>
        <FacturationEtablissement />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de vérifier votre établissement');
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.from).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.scope.retry).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['une erreur transport', { rpcError: 'permission refusée' }],
    ['une erreur métier dans le payload', { payloadError: 'établissement introuvable' }],
  ])('refuse tout rendu financier partiel après %s', async (_label, options) => {
    activerScope();
    configurerChargement(options);

    render(
      <MemoryRouter>
        <FacturationEtablissement />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger les données de facturation');
    expect(screen.queryByText('Paiements soignants, commissions Jolene et exports comptables')).not.toBeInTheDocument();
  });

  it('rend les destinations financières comme de vrais liens clavier', async () => {
    activerScope();
    configurerChargement({
      etablissement: {
        id: 'etablissement-partage-id',
        mode_paiement_commission: 'SEPA_DEBIT',
      },
      obligations: {
        ...obligationsVides,
        total_du: 100,
        paiements_soignants_confirmes: [{
          paiement_id: 'paiement-confirme',
          mission_id: 'mission-confirmee-id',
          mission_intitule: 'Mission confirmée',
          soignant_nom: 'Marie Lefèvre',
          montant_net: 100,
          reference_virement: 'VIR-2026',
          confirme_par_soignant_le: '2026-07-14T10:00:00Z',
        }],
      },
      missions: [{
        id: 'mission-a-facturer-id',
        intitule: 'Mission à facturer',
        fin_le: '2026-07-14T10:00:00Z',
        montant_commission_ht: 15,
        montant_commission_ttc: 18,
      }],
      prelevements: [{
        id: 'prelevement-id',
        mission_id: 'mission-prelevement-id',
        montant_ttc: 18,
        statut: 'PRELEVE',
        capture_le: '2026-07-14T10:00:00Z',
        missions: { intitule: 'Mission prélevée' },
      }],
    });

    render(
      <MemoryRouter>
        <FacturationEtablissement />
      </MemoryRouter>,
    );

    const missionsAFacturer = await screen.findAllByRole('link', { name: 'Mission à facturer' });
    const missionsPrelevees = await screen.findAllByRole('link', { name: 'Mission prélevée' });
    const missionsConfirmees = await screen.findAllByRole('link', { name: 'Mission confirmée' });
    expect(missionsAFacturer.every((link) => link.getAttribute('href') === '/etablissement/missions/mission-a-facturer-id')).toBe(true);
    expect(missionsPrelevees.every((link) => link.getAttribute('href') === '/etablissement/missions/mission-prelevement-id')).toBe(true);
    expect(missionsConfirmees.every((link) => link.getAttribute('href') === '/etablissement/missions/mission-confirmee-id')).toBe(true);

    const source = readFileSync('src/pages/FacturationEtablissement.tsx', 'utf8');
    expect(source.match(/<(?:div|tr)\b(?:(?!>).)*\bonClick=/gs)).toBeNull();
  });
});

import React from 'react';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AdminImpayees from './AdminImpayees';
import AdminFinances from './AdminFinances';
import AdminDashboard from './AdminDashboard';

const mocks = vi.hoisted(() => ({
  from: vi.fn(), rpc: vi.fn(), invoke: vi.fn(), insert: vi.fn(),
  success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn(),
  selects: [] as Array<{ table: string; columns: string }>,
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  from: mocks.from, rpc: mocks.rpc, functions: { invoke: mocks.invoke },
} }));
vi.mock('sonner', () => ({ toast: { success: mocks.success, error: mocks.error, info: mocks.info, warning: mocks.warning } }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: React.PropsWithChildren) => <main>{children}</main> }));
vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));
vi.mock('@/components/admin/ChargementAdmin', () => ({ ChargementAdmin: () => <p>Chargement</p> }));
vi.mock('@/components/admin/FinancialOperationsMonitor', () => ({ FinancialOperationsMonitor: () => null }));
vi.mock('@/components/admin/BandeauAlertesAntiTricheAdmin', () => ({ BandeauAlertesAntiTricheAdmin: () => null }));
vi.mock('@/lib/telechargement', () => ({ telechargerOuPartager: vi.fn() }));
vi.mock('@/components/ui/chart', () => ({ ChartContainer: () => null, ChartTooltip: () => null, ChartTooltipContent: () => null }));
vi.mock('recharts', () => ({
  BarChart: () => null, Bar: () => null, XAxis: () => null, YAxis: () => null,
  CartesianGrid: () => null, LineChart: () => null, Line: () => null,
  AreaChart: () => null, Area: () => null, ReferenceLine: () => null,
}));

const etablissement = {
  id: 'etablissement-synthetique', nom: 'Établissement synthétique', email_contact: 'recette@example.invalid',
  telephone_contact: null, type: 'EHPAD', adresse_ville: null, taux_commission_negocie: null,
  groupe_sante_id: null, est_compte_test: false,
};
function facture(delta: Record<string, unknown> = {}): Record<string, any> {
  return {
    id: 'commission-partielle', numero_facture: 'COM-PARTIELLE', etablissement_id: etablissement.id,
    type_document: 'FACTURE', statut: 'EN_RETARD', montant_ht: 100, montant_tva: 20, montant_ttc: 120,
    montant_signe: 100, montant_avoirs_imputes: 40, montant_a_payer: 80, rapprochement_paiement_requis: false,
    date_emission: '2026-10-01', date_echeance: '2026-10-15', nombre_missions: 0,
    periode_debut: null, periode_fin: null, etablissements: { ...etablissement }, ...delta,
  };
}
let lignes: Record<string, any>[];
function ouvrir(Page: React.ComponentType) { return render(<MemoryRouter><Page /></MemoryRouter>); }
function verifierProjection() {
  const lectures = mocks.selects.filter(q => q.table === 'factures');
  expect(lectures.length).toBeGreaterThan(0);
  for (const { columns } of lectures) {
    for (const champ of ['montant_avoirs_imputes', 'montant_a_payer', 'rapprochement_paiement_requis']) {
      expect(columns.split(', ')).toContain(champ);
    }
  }
}
function avecExclusions() {
  lignes = [facture(),
    facture({ id: 'commission-gel', numero_facture: 'COM-RAPPROCHEMENT', rapprochement_paiement_requis: true }),
    facture({ id: 'commission-zero', numero_facture: 'COM-ZERO', montant_avoirs_imputes: 120, montant_a_payer: 0 }),
  ];
}
beforeEach(() => {
  vi.clearAllMocks(); mocks.selects = []; lignes = [facture()];
  vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-10-18T12:00:00Z'));
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
  mocks.insert.mockResolvedValue({ error: null });
  mocks.invoke.mockResolvedValue({ data: { success: true }, error: null });
  mocks.rpc.mockImplementation(async (nom: string) => {
    if (nom === 'fn_admin_kpi') return { data: {}, error: null };
    if (nom === 'fn_admin_metriques_argent') return { data: {
      commission: { total_reel: 100, tva_reel: 20 }, encaisse: { ht_reel: 0, ttc_reel: 0 },
      etab_a_valider: 0, nb_missions_terminees_reel: 0,
    }, error: null };
    if (nom === 'fn_admin_graphiques') return { data: { ca_par_mois: [], missions_par_semaine: [] }, error: null };
    if (nom === 'fn_admin_stripe_connect_stats') return { data: null, error: null };
    throw new Error(`RPC inattendue : ${nom}`);
  });
  mocks.from.mockImplementation((table: string) => {
    const data = table === 'factures' ? lignes
      : table === 'etablissements' ? [{ ...etablissement }]
      : ['missions', 'soignants', 'notifications', 'litiges', 'paiements_mission'].includes(table) ? [] : null;
    if (data === null) throw new Error(`Table inattendue : ${table}`);
    const q: any = { insert: mocks.insert };
    q.select = (columns: string) => { mocks.selects.push({ table, columns }); return q; };
    for (const methode of ['eq', 'in', 'order', 'range', 'limit', 'is', 'lt', 'gt', 'gte']) q[methode] = () => q;
    q.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
      Promise.resolve({ data, error: null }).then(resolve, reject);
    return q;
  });
});
afterEach(() => { cleanup(); vi.useRealTimers(); vi.restoreAllMocks(); });

describe('Lecteurs admin — impayés après imputation', () => {
  it('relance le net80 de la facture120 après avoir40, conserve le TTC et relit le même solde', async () => {
    const vue = ouvrir(AdminImpayees);
    await screen.findByText('COM-PARTIELLE');
    expect(screen.getByText('Total impayé').parentElement).toHaveTextContent(/80,00\s*€/);
    expect(screen.getByText(/^80,00\s*€ net dû$/)).toBeVisible();
    expect(screen.getByText(/^TTC du document : 120,00\s*€ · Avoirs imputés : 40,00\s*€$/)).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: /COM-PARTIELLE/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer une relance' }));
    await waitFor(() => expect(mocks.insert).toHaveBeenCalledOnce());
    expect(mocks.invoke.mock.calls).toEqual([['send-email', { body: {
      type: 'RAPPEL_FACTURE', destinataire_id: etablissement.id,
      data: { numero: 'COM-PARTIELLE', facture_id: 'commission-partielle', famille_document: 'COMMISSION',
        type_document: 'FACTURE', statut: 'EN_RETARD', montant_ttc: '120.00', montant_avoirs_imputes: '40.00',
        montant_a_payer: '80.00', rapprochement_paiement_requis: false, date_echeance: '15/10/2026',
        jours_retard: 3, etablissement_nom: etablissement.nom },
    } }]]);
    expect(mocks.insert.mock.calls[0][0].corps).toMatch(/net dû 80,00\s*€/);
    expect(mocks.insert.mock.calls[0][0].corps).not.toMatch(/120,00/);
    await screen.findByText('COM-PARTIELLE');
    vue.unmount(); ouvrir(AdminImpayees); await screen.findByText('COM-PARTIELLE');
    expect(screen.getByText('Total impayé').parentElement).toHaveTextContent(/80,00\s*€/);
    expect(lignes[0].montant_ttc).toBe(120); expect(lignes[0].montant_a_payer).toBe(80);
    verifierProjection();
  });

  it('exclut le rapprochement et le net0 de la file et de la relance groupée', async () => {
    avecExclusions(); ouvrir(AdminImpayees); await screen.findByText('COM-PARTIELLE');
    expect(screen.getByText('1 facture en attente de paiement')).toBeVisible();
    expect(screen.queryByText('COM-RAPPROCHEMENT')).not.toBeInTheDocument();
    expect(screen.queryByText('COM-ZERO')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Relancer toutes les factures' }));
    await waitFor(() => expect(mocks.success).toHaveBeenCalledWith('1 envoyée(s), 0 neutralisée(s), 0 en cours, 0 à vérifier/échouée(s)'));
    expect(mocks.invoke).toHaveBeenCalledOnce();
    expect(mocks.invoke.mock.calls[0][1].body.data.facture_id).toBe('commission-partielle');
    expect(mocks.invoke.mock.calls[0][1].body.data.montant_a_payer).toBe('80.00');
  });

  it.each([
    { success: true, skipped: true }, { success: true, pending: true }, { success: false },
  ])('ne journalise pas une relance dont le retour n’atteste pas l’envoi (%j)', async reponse => {
    mocks.invoke.mockResolvedValue({ data: reponse, error: null });
    ouvrir(AdminImpayees); fireEvent.click(await screen.findByRole('button', { name: /COM-PARTIELLE/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer une relance' }));
    await waitFor(() => expect(mocks.info.mock.calls.length + mocks.error.mock.calls.length).toBe(1));
    expect(mocks.insert).not.toHaveBeenCalled(); expect(mocks.success).not.toHaveBeenCalled();
  });

  it('calcule les urgences globales et par établissement sur80 tout en gardant le CA TTC documentaire360', async () => {
    avecExclusions(); ouvrir(AdminFinances); await screen.findByRole('heading', { name: 'Finances Jolene' });
    const resume = within(screen.getByRole('region', { name: 'Résumé financier — Tout' }));
    expect(resume.getByText('Factures impayées').parentElement!.parentElement).toHaveTextContent(/1\s*80,00\s*€ en attente/);
    expect(resume.getByText('CA TTC').parentElement!.parentElement).toHaveTextContent(/360,00\s*€/);
    expect(screen.getByRole('button', { name: /^Établissement synthétique 80,00/ })).toBeVisible();
    expect(lignes.map(f => f.montant_ttc)).toEqual([120, 120, 120]); verifierProjection();
  });

  it('affiche une seule urgence dashboard au net80, sans TTC120 ni faux zéro pour les deux exclusions', async () => {
    avecExclusions(); ouvrir(AdminDashboard); await screen.findByRole('heading', { name: 'Tableau de bord' });
    expect(screen.getByText('1 facture impayée')).toBeVisible();
    expect(screen.getByRole('button', { name: /COM-PARTIELLE/ })).toHaveTextContent(/80,00\s*€ net dû/);
    expect(screen.getByRole('button', { name: /COM-PARTIELLE/ })).not.toHaveTextContent(/120/);
    expect(screen.queryByText('COM-RAPPROCHEMENT')).not.toBeInTheDocument();
    expect(screen.queryByText('COM-ZERO')).not.toBeInTheDocument(); verifierProjection();
  });

  for (const [nom, Page] of [['file', AdminImpayees], ['finances', AdminFinances], ['dashboard', AdminDashboard]] as const) {
    it.each(['absente', 'incohérente'])(`${nom} : rend l’indisponibilité explicite si la projection est %s, sans repli TTC`, async cas => {
      if (cas === 'absente') delete lignes[0].montant_a_payer;
      else lignes[0].montant_a_payer = 120;
      ouvrir(Page);
      if (nom === 'dashboard') {
        expect(await screen.findByRole('alert')).toHaveTextContent('Suivi des impayés indisponible');
        expect(screen.queryByText('Aucune urgence détectée')).not.toBeInTheDocument();
      } else expect(await screen.findByRole('heading', { name: 'Données financières indisponibles' })).toBeVisible();
      expect(screen.queryByText('COM-PARTIELLE')).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Relancer toutes les factures' })).not.toBeInTheDocument();
      expect(mocks.invoke).not.toHaveBeenCalled(); expect(mocks.insert).not.toHaveBeenCalled();
    });
  }
});

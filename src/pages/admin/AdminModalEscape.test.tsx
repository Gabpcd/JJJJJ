import React from 'react';
import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNativeBackHandler } from '@/lib/nativeBack';
import AdminAlertesPointage from './AdminAlertesPointage';
import AdminHeuresExternes from './AdminHeuresExternes';
import AdminDetailUtilisateur from './AdminDetailUtilisateur';
import AdminModeration from './AdminModeration';
import AdminSales from './AdminSales';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(), from: vi.fn(), write: vi.fn(), notification: vi.fn(),
  rows: {} as Record<string, any[]>, pending: null as Promise<any> | null,
}));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</> }));
vi.mock('@/components/admin/ChargementAdmin', () => ({ ChargementAdmin: () => <p>Chargement</p>, ChargementSectionAdmin: () => <p>Chargement</p> }));
vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));
vi.mock('@/components/admin/litiges/RefundsQueueWidget', () => ({ RefundsQueueWidget: () => null }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/hooks/useOuvrirConversation', () => ({ useOuvrirConversation: () => vi.fn() }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notification }) }));
vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn() } }));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'http://localhost', SUPABASE_PUBLISHABLE_KEY: 'fixture',
  supabase: { rpc: mocks.rpc, from: mocks.from, auth: { getUser: async () => ({ data: { user: null } }) }, storage: { from: vi.fn() } },
}));

const alerte = { id: 'alerte-test', type_alerte: 'POINTAGE_INCOHERENT', severite: 'WARNING', source: 'test', message: 'Alerte de simulation', details: {}, resolu_le: null, cree_le: '2026-09-26T10:00:00Z' };
const heure = { id: 'heure-test', soignant_id: 'soignant-test', soignant_nom: 'Test', soignant_prenom: 'Camille', profession: 'IDE', type_exercice: 'SALARIE', etablissement_nom: 'Établissement de test', heures_declarees: 8, statut_validation: 'EN_ATTENTE', date_debut: '2026-09-20', date_fin: '2026-09-21', cree_le: '2026-09-22T10:00:00Z' };
const readRpcs = new Set(['fn_admin_resume_alertes_pointage', 'fn_admin_lister_alertes_pointage', 'fn_admin_lister_heures_externes', 'fn_admin_incoherences_identite', 'fn_admin_prospection_stats']);

function retourNatif() {
  const back = vi.fn();
  const exit = vi.fn();
  const notify = vi.fn();
  const handler = createNativeBackHandler({ document, pathname: () => '/admin/recette', back, exit, notify });
  act(() => handler({ canGoBack: true }));
  expect(back).not.toHaveBeenCalled();
  expect(exit).not.toHaveBeenCalled();
  expect(notify).not.toHaveBeenCalled();
}
function monter(component: React.ReactElement, path = '/admin/recette') {
  render(<MemoryRouter initialEntries={[path]}><Routes><Route path="/admin/:id" element={component} /></Routes></MemoryRouter>);
}
async function onglet(nom: RegExp) {
  const tab = await screen.findByRole('tab', { name: nom });
  fireEvent.mouseDown(tab, { button: 0, ctrlKey: false });
  fireEvent.keyDown(tab, { key: 'Enter' });
}

const cas = [
  {
    nom: 'confirmation compte',
    async ouvrir() {
      monter(<AdminDetailUtilisateur />, '/admin/soignant-test');
      await onglet(/^Actions/);
      fireEvent.click(screen.getByRole('button', { name: /Suspendre le compte/ }));
      return screen.getByRole('dialog', { name: 'Suspendre le compte' });
    },
  },
  {
    nom: 'traitement pointage',
    async ouvrir() {
      monter(<AdminAlertesPointage />);
      fireEvent.click(await screen.findByRole('button', { name: 'Traiter' }));
      return screen.getByRole('dialog', { name: "Traiter l'alerte" });
    },
    remplir(dialog: HTMLElement) {
      fireEvent.click(within(dialog).getByRole('radio', { name: /Légitime/ }));
      fireEvent.change(within(dialog).getByRole('textbox'), { target: { value: 'Motif précis de simulation' } });
      fireEvent.click(within(dialog).getByRole('button', { name: 'Confirmer la décision' }));
    },
  },
  {
    nom: 'validation heures',
    async ouvrir() {
      monter(<AdminHeuresExternes />);
      fireEvent.click(await screen.findByRole('button', { name: 'Traiter' }));
      return screen.getByRole('dialog', { name: 'Valider les heures externes' });
    },
    remplir(dialog: HTMLElement) { fireEvent.click(within(dialog).getByRole('button', { name: 'Appliquer' })); },
  },
  {
    nom: 'rejet document',
    async ouvrir() {
      monter(<AdminModeration />, '/admin/recette?onglet=documents');
      fireEvent.click(await screen.findByRole('button', { name: /Rejeter/ }));
      return screen.getByRole('dialog', { name: 'Rejeter le document' });
    },
    remplir(dialog: HTMLElement) {
      fireEvent.change(within(dialog).getByRole('textbox'), { target: { value: 'Motif précis de simulation' } });
      fireEvent.click(within(dialog).getByRole('button', { name: 'Confirmer le rejet' }));
    },
  },
  {
    nom: 'masquage notation',
    async ouvrir() {
      monter(<AdminModeration />);
      await onglet(/^Évaluations/);
      fireEvent.click(screen.getByRole('button', { name: 'Masquer' }));
      return screen.getByRole('dialog', { name: 'Masquer la notation' });
    },
    remplir(dialog: HTMLElement) {
      fireEvent.change(within(dialog).getByRole('textbox'), { target: { value: 'Raison de simulation' } });
      fireEvent.click(within(dialog).getByRole('button', { name: 'Masquer' }));
    },
  },
  {
    nom: 'création litige',
    async ouvrir() {
      monter(<AdminModeration />);
      fireEvent.click(await screen.findByRole('button', { name: 'Créer un litige par dérogation admin' }));
      return screen.getByRole('dialog', { name: 'Créer un litige par dérogation' });
    },
    remplir(dialog: HTMLElement) {
      within(dialog).getAllByRole('textbox').forEach(field => fireEvent.change(field, { target: { value: 'Valeur de simulation' } }));
      fireEvent.click(within(dialog).getByRole('button', { name: /Créer/ }));
    },
  },
  {
    nom: 'périmètre gel',
    async ouvrir() {
      monter(<AdminModeration />);
      fireEvent.click(await screen.findByRole('button', { name: 'Modifier gel scope litige litige-test' }));
      return screen.getByRole('dialog', { name: 'Modifier le périmètre de gel' });
    },
    remplir(dialog: HTMLElement) {
      fireEvent.change(within(dialog).getByRole('combobox'), { target: { value: 'AUCUN' } });
      fireEvent.change(within(dialog).getByRole('textbox'), { target: { value: 'Raison de simulation' } });
      fireEvent.click(within(dialog).getByRole('button', { name: 'Mettre à jour' }));
    },
  },
  {
    nom: 'import CSV',
    async ouvrir() {
      monter(<AdminSales />, '/admin/recette?tab=groupes');
      fireEvent.click(await screen.findByRole('button', { name: 'Importer CSV' }));
      return screen.getByRole('dialog', { name: 'Importer en masse (groupes)' });
    },
    remplir(dialog: HTMLElement) {
      fireEvent.change(within(dialog).getByRole('textbox'), { target: { value: 'Groupe de recette;https://example.invalid;IDE;Bretagne' } });
      fireEvent.click(within(dialog).getByRole('button', { name: 'Importer' }));
    },
  },
];

beforeEach(() => {
  mocks.rpc.mockReset(); mocks.from.mockReset(); mocks.write.mockReset(); mocks.pending = null;
  mocks.rows = {
    soignants: [{ id: 'soignant-test', prenom: 'Camille', nom: 'Test', profession: 'IDE', statut: 'ACTIF', cree_le: '2026-09-22T10:00:00Z' }],
    documents_soignants: [{ id: 'doc-test', nom_fichier: 'diplome-test.pdf', type_document: 'DIPLOME', soignant_id: 'soignant-test', televerse_le: '2026-09-22T10:00:00Z', statut_verification: 'EN_ATTENTE', s3_cle: 'simulation.pdf', s3_bucket: 'jolene-documents' }],
    evaluations: [{ id: 'notation-test', note: 2, commentaire: 'Simulation', cree_le: '2026-09-22T10:00:00Z' }],
    litiges: [{ id: 'litige-test', motif: 'Litige de simulation', statut: 'OUVERT', cree_le: '2026-09-22T10:00:00Z', type_litige: 'DESACCORD_HEURES_POINTAGE', soignant_id: 'soignant-test', montant_tresorerie_bloquee: 0 }],
  };
  mocks.rpc.mockImplementation((name: string) => {
    if (!readRpcs.has(name)) return mocks.pending ?? Promise.resolve({ data: { success: false, error: 'Simulation' }, error: null });
    const data = name === 'fn_admin_lister_heures_externes' ? { success: true, heures: [heure] }
      : name === 'fn_admin_lister_alertes_pointage' ? { success: true, alertes: [alerte], total: 1 }
      : name === 'fn_admin_resume_alertes_pointage' ? { success: true, kpis: { total_ouvertes: 1 } }
      : name === 'fn_admin_incoherences_identite' ? [] : null;
    return Promise.resolve({ data, error: null });
  });
  mocks.from.mockImplementation((table: string) => {
    const builder: Record<string, any> = {};
    let single = false;
    for (const name of ['select', 'eq', 'in', 'is', 'order', 'limit', 'lt', 'range']) builder[name] = () => builder;
    builder.maybeSingle = () => { single = true; return builder; };
    builder.insert = (...args: any[]) => { mocks.write(table, ...args); return mocks.pending ?? Promise.resolve({ error: new Error('Simulation') }); };
    builder.then = (resolve: any, reject: any) => Promise.resolve({ data: single ? mocks.rows[table]?.[0] ?? null : mocks.rows[table] ?? [], count: 0, error: null }).then(resolve, reject);
    return builder;
  });
  vi.spyOn(HTMLElement.prototype, 'getClientRects').mockReturnValue([{ width: 100, height: 100 }] as unknown as DOMRectList);
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

describe('Retour Android sur les dialogues administrateur réels', () => {
  it.each(cas)('$nom : ferme sans mutation ni navigation', async ({ ouvrir }) => {
    await ouvrir();
    const rpcCount = mocks.rpc.mock.calls.length;
    retourNatif();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(rpcCount);
    expect(mocks.write).not.toHaveBeenCalled();
  });

  it.each(cas.filter(c => c.remplir))('$nom : garde la couche pendant la mutation puis permet l’annulation', async ({ ouvrir, remplir }) => {
    const dialog = await ouvrir();
    let finish!: (value: any) => void;
    mocks.pending = new Promise(resolve => { finish = resolve; });
    remplir!(dialog);
    const rpcCount = mocks.rpc.mock.calls.length;
    const writes = mocks.write.mock.calls.length;
    expect(mocks.rpc.mock.calls.filter(([name]) => !readRpcs.has(name)).length + writes).toBe(1);
    retourNatif();
    expect(dialog).toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledTimes(rpcCount);
    expect(mocks.write).toHaveBeenCalledTimes(writes);
    await act(async () => finish({ data: { success: false }, error: new Error('Simulation : décision non appliquée') }));
    retourNatif();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('respecte Escape déjà consommé dans un champ et laisse Enter sans confirmer', async () => {
    const dialog = await cas[2].ouvrir();
    const field = within(dialog).getByRole('textbox');
    field.focus();
    const blockEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') event.preventDefault(); };
    field.addEventListener('keydown', blockEscape);
    retourNatif();
    expect(dialog).toBeInTheDocument();
    fireEvent.keyDown(field, { key: 'Enter' });
    expect(dialog).toBeInTheDocument();
    expect(mocks.rpc.mock.calls.filter(([name]) => !readRpcs.has(name))).toHaveLength(0);
    field.removeEventListener('keydown', blockEscape);
    retourNatif();
    expect(dialog).not.toBeInTheDocument();
  });
});

import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import PageParametresNotifications from './PageParametresNotifications';
import { MonGroupeContent } from './MonGroupe';
import DashboardGroupe from './DashboardGroupe';

const m = vi.hoisted(() => ({ rpc: vi.fn(), query: vi.fn(), success: vi.fn(), error: vi.fn(), role: 'SOIGNANT', scope: 'etab-invite' }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'utilisateur-invite' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: m.role, resolved: true, error: null }) }));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => ({ etablissementId: m.scope, resolved: true, loading: false, error: null }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement</p> }));
vi.mock('@/components/y2k/CarteKPIY2K', () => ({ CarteKPIY2K: ({ label, valeur }: any) => <div aria-label={label}>{valeur}</div> }));
vi.mock('sonner', () => ({ toast: { success: m.success, error: m.error } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: m.rpc, from: (table: string) => {
  const args: any = { table, filters: {} };
  const q: any = { then: (resolve: any, reject: any) => Promise.resolve(m.query(args)).then(resolve, reject) };
  for (const method of ['select', 'eq', 'in', 'is', 'gte', 'order', 'limit', 'range', 'single', 'maybeSingle', 'update']) q[method] = (...values: any[]) => {
    if (method === 'eq' || method === 'in') args.filters[values[0]] = values[1];
    else args[method] = values;
    return q;
  };
  return q;
} } }));
const preferences = { global: { canal_email: false, canal_sms: false, canal_push: false, canal_in_app: true }, par_evenement: [{ type_evenement: 'CANDIDATURE_ACCEPTEE', canal: 'EMAIL', actif: false }] };
const afficher = (node: React.ReactNode) => render(<MemoryRouter>{node}</MemoryRouter>);
const etablissements = [{ id: 'a', nom: 'Clinique A', adresse_ville: 'Paris' }, { id: 'b', nom: 'Clinique B', adresse_ville: 'Lyon' }];

beforeEach(() => { vi.clearAllMocks(); m.role = 'SOIGNANT'; m.query.mockResolvedValue({ data: { sms_alertes_actives: false, type_exercice: 'SALARIE' }, error: null }); });
describe('préférences : aucune écriture à partir d’une lecture en échec', () => {
  it.each(['SOIGNANT', 'ADMIN_ETABLISSEMENT'])('%s : 503 puis réessai préserve les vrais choix', async role => {
    m.role = role;
    m.rpc.mockResolvedValueOnce({ data: null, error: { message: '503' } }).mockResolvedValueOnce({ data: preferences, error: null }).mockResolvedValue({ data: { success: true }, error: null });
    afficher(<PageParametresNotifications />);
    expect(await screen.findByRole('alert')).toHaveTextContent('choix enregistrés sont conservés');
    expect(screen.queryByRole('button', { name: /Enregistrer/ })).toBeNull();
    expect(m.rpc).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('switch', { name: 'Email' })).toHaveAttribute('aria-checked', 'false');
    fireEvent.click(screen.getByRole('button', { name: /Enregistrer/ }));
    await waitFor(() => expect(m.rpc).toHaveBeenCalledWith('fn_modifier_preferences_notifications', expect.objectContaining({ p_canal_email: false, p_canal_push: false, p_par_evenement: preferences.par_evenement })));
    await waitFor(() => expect(m.success).toHaveBeenCalledWith('Préférences enregistrées'));
  });
  it('bloque aussi la sauvegarde si le réglage SMS soignant ne peut pas être lu', async () => {
    m.rpc.mockResolvedValue({ data: preferences, error: null });
    m.query.mockResolvedValue({ data: null, error: { message: '503' } });
    afficher(<PageParametresNotifications />);
    await screen.findByRole('alert');
    expect(screen.queryByRole('switch')).toBeNull();
    expect(m.rpc).toHaveBeenCalledTimes(1);
  });
});
describe('compatibilité des préférences d’alertes établissement', () => {
  const legacy = 'NOUVELLE_MISSION_MATCHANT_FILTRE';
  const canonique = 'NOUVEAU_SOIGNANT_MATCHANT_FILTRE';
  it.each([
    [false, undefined], [undefined, false], [true, false], [false, true],
  ])('préserve le refus historique (%s, %s), puis synchronise les deux clés sur choix explicite', async (ancien, nouveau) => {
    m.role = 'ADMIN_ETABLISSEMENT';
    const par_evenement = [[legacy, ancien], [canonique, nouveau]]
      .filter(([, actif]) => actif !== undefined)
      .map(([type_evenement, actif]) => ({ type_evenement, canal: 'EMAIL', actif }));
    m.rpc.mockImplementation(async name => ({ data: name === 'fn_obtenir_mes_preferences_notifications'
      ? { global: { ...preferences.global, canal_email: true }, par_evenement }
      : { success: true }, error: null }));
    afficher(<PageParametresNotifications />);
    const alerte = await screen.findByRole('switch', { name: /EMAIL pour Nouveaux soignants disponibles/ });
    expect(alerte).toHaveAttribute('aria-checked', 'false');
    fireEvent.click(screen.getByRole('button', { name: /Enregistrer/ }));
    await waitFor(() => expect(m.rpc).toHaveBeenCalledWith('fn_modifier_preferences_notifications', expect.objectContaining({ p_par_evenement: par_evenement })));
    await waitFor(() => expect(screen.getByRole('button', { name: /Enregistrer/ })).not.toBeDisabled());
    fireEvent.click(alerte);
    expect(alerte).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(screen.getByRole('button', { name: /Enregistrer/ }));
    await waitFor(() => expect(m.rpc).toHaveBeenLastCalledWith('fn_modifier_preferences_notifications', expect.objectContaining({ p_par_evenement: expect.arrayContaining([
      { type_evenement: legacy, canal: 'EMAIL', actif: true }, { type_evenement: canonique, canal: 'EMAIL', actif: true },
    ]) })));
    await waitFor(() => expect(screen.getByRole('button', { name: /Enregistrer/ })).not.toBeDisabled());
    fireEvent.click(alerte);
    fireEvent.click(screen.getByRole('button', { name: /Enregistrer/ }));
    await waitFor(() => expect(m.rpc).toHaveBeenLastCalledWith('fn_modifier_preferences_notifications', expect.objectContaining({ p_par_evenement: expect.arrayContaining([
      { type_evenement: legacy, canal: 'EMAIL', actif: false }, { type_evenement: canonique, canal: 'EMAIL', actif: false },
    ]) })));
  });
  it('conserve le défaut actif et ne relie pas les deux événements pour un soignant', async () => {
    const par_evenement = [{ type_evenement: canonique, canal: 'EMAIL', actif: false }];
    m.rpc.mockImplementation(async name => ({ data: name === 'fn_obtenir_mes_preferences_notifications'
      ? { global: { ...preferences.global, canal_email: true }, par_evenement }
      : { success: true }, error: null }));
    afficher(<PageParametresNotifications />);
    const alerte = await screen.findByRole('switch', { name: /EMAIL pour Nouvelles missions matchant mes filtres/ });
    expect(alerte).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(alerte);
    fireEvent.click(screen.getByRole('button', { name: /Enregistrer/ }));
    await waitFor(() => expect(m.rpc).toHaveBeenLastCalledWith('fn_modifier_preferences_notifications', expect.objectContaining({ p_par_evenement: [
      ...par_evenement, { type_evenement: legacy, canal: 'EMAIL', actif: false },
    ] })));
  });
});
describe('périmètre et statistiques du groupe', () => {
  it('utilise l’établissement rattaché de l’invité et ne confond pas panne et indépendance', async () => {
    m.query.mockResolvedValueOnce({ data: null, error: { message: '503' } }).mockResolvedValueOnce({ data: { groupe_sante_id: 'g', groupes_sante: { nom: 'Groupe test' } }, error: null }).mockResolvedValue({ data: [{ id: 'etab-invite', nom: 'Clinique invitée' }], error: null });
    afficher(<MonGroupeContent />);
    await screen.findByRole('alert');
    expect(screen.queryByText('Établissement indépendant')).toBeNull();
    expect(m.query.mock.calls[0][0].filters.id).toBe('etab-invite');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByText('Groupe test');
    expect(screen.getByText('📍 Vous êtes ici')).toBeInTheDocument();
  });
  it('une seule sélection alimente les KPI et les lignes ; une panne ne devient pas zéro', async () => {
    let panne = false;
    m.query.mockImplementation((q: any) => {
      if (q.table === 'admins_groupe_sante') return { data: { groupe_id: 'g', groupes_sante: { nom: 'Groupe test' } }, error: null };
      if (q.table === 'etablissements') return { data: etablissements, error: null };
      if (panne) return { data: null, count: null, error: { message: '503' } };
      return q.select[1]?.head ? { count: q.filters.etablissement_id.length, error: null } : { data: q.filters.etablissement_id.map((id: string) => ({ etablissement_id: id, statut: 'OUVERTE' })), error: null };
    });
    afficher(<DashboardGroupe />);
    await screen.findByRole('table');
    fireEvent.change(screen.getByRole('combobox', { name: 'Établissement' }), { target: { value: 'a' } });
    await waitFor(() => expect(screen.getByLabelText('Établissements actifs')).toHaveTextContent('1'));
    expect(within(screen.getByRole('table')).queryByText('Clinique B')).toBeNull();
    panne = true;
    fireEvent.change(screen.getByRole('combobox', { name: 'Établissement' }), { target: { value: 'b' } });
    await screen.findByRole('alert');
    expect(screen.queryByRole('table')).toBeNull();
    panne = false;
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByRole('table');
    expect(within(screen.getByRole('table')).getByText('Clinique B')).toBeInTheDocument();
  });
  it('ignore les statistiques tardives d’une ancienne sélection', async () => {
    let terminer!: (v: any) => void;
    m.query.mockImplementation((q: any) => {
      if (q.table === 'admins_groupe_sante') return { data: { groupe_id: 'g' }, error: null };
      if (q.table === 'etablissements') return { data: etablissements, error: null };
      if (q.select[1]?.head) return { count: 1, error: null };
      if (q.filters.etablissement_id.join() === 'a') return new Promise(resolve => { terminer = resolve; });
      return { data: [{ etablissement_id: 'b', statut: 'OUVERTE' }], error: null };
    });
    afficher(<DashboardGroupe />);
    await screen.findByRole('table');
    fireEvent.change(screen.getByRole('combobox', { name: 'Établissement' }), { target: { value: 'a' } });
    await waitFor(() => expect(terminer).toBeDefined());
    fireEvent.change(screen.getByRole('combobox', { name: 'Établissement' }), { target: { value: 'b' } });
    await screen.findByRole('table');
    await act(async () => terminer({ data: [{ etablissement_id: 'a', statut: 'TERMINEE' }], error: null }));
    expect(within(screen.getByRole('table')).queryByText('Clinique A')).toBeNull();
    expect(within(screen.getByRole('table')).getByText('Clinique B')).toBeInTheDocument();
  });
});

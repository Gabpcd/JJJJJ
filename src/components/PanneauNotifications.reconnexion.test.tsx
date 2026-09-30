import React from 'react';
import { act, fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { BadgeNotification } from './PanneauNotifications';

const m = vi.hoisted(() => ({
  user: { id: 'compte-a' }, rows: [] as any[], channels: [] as any[], reads: [] as any[],
  failure: '' as string, pending: false, completions: [] as (() => void)[], info: vi.fn(), error: vi.fn(),
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: m.user }) }));
vi.mock('sonner', () => ({ toast: { info: m.info, error: m.error } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  from: () => {
    const args: any = { filters: {} };
    const q: any = { then: (resolve: any, reject: any) => {
      const rows = m.rows.filter(n => Object.entries(args.filters).every(([k,v]) => Array.isArray(v) ? v.includes(n[k]) : n[k] === v));
      if (args.update && m.failure !== 'update') rows.forEach(n => Object.assign(n, args.update));
      const head = args.options?.head;
      m.reads.push({ ...args });
      const failure = m.failure === (args.update ? 'update' : head ? 'count' : 'list');
      const result = failure ? { data: null, count: null, error: { message: 'panne simulée' } }
        : { data: rows.slice(0, args.limit ?? 50).map(n => ({ ...n })), count: rows.length, error: null };
      const response = m.pending ? new Promise(r => m.completions.push(() => r(result))) : Promise.resolve(result);
      return response.then(resolve, reject);
    } };
    q.select = (_: string, options: any) => { args.options = options; return q; };
    q.eq = q.in = (k: string, v: any) => { args.filters[k] = v; return q; };
    q.order = () => q;
    q.limit = (limit: number) => { args.limit = limit; return q; };
    q.update = (update: any) => { args.update = update; return q; };
    return q;
  },
  channel: (name: string) => {
    const ch: any = { name, on: (_: any, filter: any, cb: any) => { ch.insert = cb; ch.filter = filter; return ch; },
      subscribe: (cb: any) => { ch.status = cb; return ch; } };
    m.channels.push(ch); return ch;
  },
  removeChannel: vi.fn(),
} }));
const row = (id: string, uid = 'compte-a') => ({ id, destinataire_id: uid, titre: `Notification ${id}`, corps: 'Fixture locale', type: 'SYSTEME', lue: false, lien: null, cree_le: '2026-09-30T08:00:00Z' });
const app = () => <MemoryRouter initialEntries={['/soignant/mon-compte']} future={{v7_startTransition:true,v7_relativeSplatPath:true}}><BadgeNotification /></MemoryRouter>;
const bell = (count: number) => screen.getByRole('button', { name: count ? `Notifications, ${count} non lue${count > 1 ? 's' : ''}` : 'Notifications' });
const status = async (value: string, channel = m.channels.at(-1)) => act(async () => channel.status(value));
const open = async (count = 1) => { fireEvent.click(bell(count)); await screen.findByText('Notification initiale'); };
beforeEach(() => {
  m.user = { id: 'compte-a' }; m.rows = [row('initiale')]; m.channels = []; m.reads = [];
  m.failure = ''; m.pending = false; m.completions = []; vi.clearAllMocks(); localStorage.setItem('notif_sound', 'off');
  vi.spyOn(HTMLElement.prototype, 'getClientRects').mockReturnValue([{}] as unknown as DOMRectList);
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

it('rattrape liste et compteur après coupure, sans toast rétroactif ni doublon, puis reçoit le flux suivant', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  await status('SUBSCRIBED'); await open();
  await status('CHANNEL_ERROR'); m.rows.push(row('manquée'));
  expect(screen.getByRole('alert')).toHaveTextContent('Connexion aux notifications interrompue');
  await status('SUBSCRIBED');
  await screen.findByText('Notification manquée'); expect(bell(2)).toBeInTheDocument(); expect(m.info).not.toHaveBeenCalled();
  await act(async () => m.channels[0].insert({ new: row('manquée') }));
  m.rows.push(row('nouvelle'));
  await act(async () => { m.channels[0].insert({ new: row('nouvelle') }); m.channels[0].insert({ new: row('nouvelle') }); });
  await screen.findByText('Notification nouvelle'); expect(bell(3)).toBeInTheDocument();
  expect(screen.getAllByText('Notification manquée')).toHaveLength(1); expect(m.info).toHaveBeenCalledTimes(1);
});

it.each(['list', 'count'])('panne de %s pendant le rattrapage : conserve les données, erreur visible et nouvel essai', async failure => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); await open();
  await status('CHANNEL_ERROR'); m.rows.push(row('manquée')); m.failure = failure;
  await status('SUBSCRIBED');
  await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Impossible d’actualiser'));
  expect(screen.getByText('Notification initiale')).toBeInTheDocument(); expect(screen.queryByText('Notification manquée')).toBeNull();
  expect(screen.getByRole('button', { name: 'Notifications, 1 non lue, actualisation nécessaire' })).toBeInTheDocument();
  m.failure = ''; fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await screen.findByText('Notification manquée'); expect(bell(2)).toBeInTheDocument(); expect(screen.queryByRole('alert')).toBeNull();
  expect(m.info).not.toHaveBeenCalled();
});

it('une réponse antérieure à un nouvel INSERT ne remplace pas le rattrapage récent', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); await open();
  m.pending = true; await status('SUBSCRIBED');
  await waitFor(() => expect(m.completions).toHaveLength(2));
  const anciennes = m.completions.splice(0); m.rows.push(row('récente'));
  await act(async () => m.channels[0].insert({ new: row('récente') }));
  await waitFor(() => expect(m.completions).toHaveLength(2));
  await act(async () => m.completions.splice(0).forEach(done => done()));
  await screen.findByText('Notification récente'); expect(bell(2)).toBeInTheDocument();
  await act(async () => anciennes.forEach(done => done())); expect(bell(2)).toBeInTheDocument();
  expect(screen.getByText('Notification récente')).toBeInTheDocument();
});

it('changement de compte : efface immédiatement le panneau et ignore lectures et événements tardifs', async () => {
  const view = render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); await open();
  const ancien = m.channels[0]; m.pending = true; await status('SUBSCRIBED');
  await waitFor(() => expect(m.completions).toHaveLength(2)); const anciennes = m.completions.splice(0);
  m.user = { id: 'compte-b' }; m.rows.push(row('privée-b', 'compte-b')); view.rerender(app());
  expect(screen.queryByText('Notification initiale')).toBeNull(); expect(screen.queryByRole('dialog')).toBeNull(); expect(bell(0)).toBeInTheDocument();
  await waitFor(() => expect(m.completions).toHaveLength(2));
  await act(async () => { anciennes.forEach(done => done()); ancien.insert({new:row('tardive-a')}); ancien.status('SUBSCRIBED'); m.completions.splice(0).forEach(done => done()); });
  await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); m.pending = false;
  fireEvent.click(bell(1)); await screen.findByText('Notification privée-b');
  expect(screen.queryByText('Notification initiale')).toBeNull(); expect(screen.queryByText('Notification tardive-a')).toBeNull();
  await act(async () => m.channels.at(-1).insert({new:row('étrangère-a')}));
  expect(m.info).not.toHaveBeenCalled(); expect(bell(1)).toBeInTheDocument();
  expect(m.reads.slice(-2).every(r => r.filters.destinataire_id === 'compte-b')).toBe(true);
});

it('le compteur reste exact au-delà des 50 éléments, même après lecture d’un élément', async () => {
  m.rows = Array.from({ length: 60 }, (_, i) => row(`n${i}`)); render(app());
  await screen.findByRole('button', { name: 'Notifications, 60 non lues' }); fireEvent.click(bell(60));
  await screen.findByText('Notification n0'); expect(screen.queryByText('Notification n59')).toBeNull(); expect(bell(60)).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /^Notification n0 Non lue/ }));
  await screen.findByRole('button', { name: 'Notifications, 59 non lues' });
});


it('une mutation en échec conserve la notification non lue', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); await open();
  m.failure = 'update'; fireEvent.click(screen.getByRole('button', { name: /^Notification initiale Non lue/ }));
  await waitFor(() => expect(m.error).toHaveBeenCalledWith('Impossible de marquer cette notification comme lue'));
  expect(bell(1)).toBeInTheDocument();
  expect(screen.getByRole('button', { name: /^Notification initiale Non lue/ })).toBeInTheDocument();
});

it('une mutation tardive du compte précédent ne déclenche ni toast ni relecture du nouveau compte', async () => {
  const view = render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' }); await open();
  m.pending = true; m.failure = 'update';
  fireEvent.click(screen.getByRole('button', { name: /^Notification initiale Non lue/ }));
  await waitFor(() => expect(m.completions).toHaveLength(1)); const ancienne = m.completions.pop()!;
  m.pending = false; m.failure = ''; m.user = { id: 'compte-b' }; view.rerender(app());
  await waitFor(() => expect(m.reads.at(-1).filters.destinataire_id).toBe('compte-b'));
  const lectures = m.reads.length; await act(async () => ancienne());
  expect(m.error).not.toHaveBeenCalled(); expect(m.reads).toHaveLength(lectures); expect(bell(0)).toBeInTheDocument();
});

it('la première souscription rattrape aussi un INSERT survenu après la lecture initiale', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  m.rows.push(row('avant-souscription')); await status('SUBSCRIBED');
  await screen.findByRole('button', { name: 'Notifications, 2 non lues' });
  fireEvent.click(bell(2)); await screen.findByText('Notification avant-souscription');
  expect(m.info).not.toHaveBeenCalled();
});

it('les deux en-têtes utilisent des canaux distincts et seul le visible émet une alerte', async () => {
  vi.mocked(HTMLElement.prototype.getClientRects).mockImplementation(function(this: HTMLElement) {
    return (this.closest('[hidden]') ? [] : [{}]) as unknown as DOMRectList;
  });
  render(<MemoryRouter future={{v7_startTransition:true,v7_relativeSplatPath:true}}><div hidden><BadgeNotification /></div><BadgeNotification /></MemoryRouter>);
  await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  expect(new Set(m.channels.map(c => c.name)).size).toBe(2);
  await act(async () => m.channels.forEach(c => c.status('SUBSCRIBED')));
  m.rows.push(row('commune'));
  await act(async () => m.channels.forEach(c => c.insert({new:row('commune')})));
  await screen.findByRole('button', { name: 'Notifications, 2 non lues' });
  expect(m.info).toHaveBeenCalledTimes(1);
});

it('une lecture actualise aussi le badge caché avant de changer de breakpoint sans rechargement', async () => {
  const responsive = (desktop: boolean) => <MemoryRouter future={{v7_startTransition:true,v7_relativeSplatPath:true}}>
    <div hidden={desktop}><BadgeNotification /></div><div hidden={!desktop}><BadgeNotification /></div>
  </MemoryRouter>;
  const view = render(responsive(false));
  await waitFor(() => expect(screen.getAllByLabelText('Notifications, 1 non lue')).toHaveLength(2));
  await open(); fireEvent.click(screen.getByRole('button', { name: /^Notification initiale Non lue/ }));
  await waitFor(() => expect(bell(0)).toBeInTheDocument());
  fireEvent.click(screen.getByRole('button', { name: 'Fermer les notifications' }));
  view.rerender(responsive(true));
  await waitFor(() => expect(bell(0)).toBeInTheDocument());
  expect(m.channels).toHaveLength(2); // aucun remontage / aucune reconnexion pour sauver le compteur.
});

it.each([0, 50])('tout marquer comme lu couvre 60 lignes dont %s déjà lues, sans toucher un autre destinataire', async dejaLues => {
  m.rows = Array.from({ length: 60 }, (_, i) => ({ ...row(`n${i}`), lue: i < dejaLues }));
  m.rows.push(row('étrangère', 'compte-b'));
  render(app()); await screen.findByRole('button', { name: `Notifications, ${60 - dejaLues} non lues` });
  fireEvent.click(bell(60 - dejaLues)); await screen.findByText('Notification n0');
  expect(screen.queryByText('Notification n59')).toBeNull();
  const tout = screen.getByRole('button', { name: 'Tout marquer comme lu' });
  expect(tout).not.toBeDisabled(); fireEvent.click(tout);
  await waitFor(() => expect(bell(0)).toBeInTheDocument());
  expect(m.rows.filter(n => n.destinataire_id === 'compte-a' && !n.lue)).toHaveLength(0);
  expect(m.rows.find(n => n.id === 'étrangère').lue).toBe(false);
  const mutation = m.reads.find(r => r.update);
  expect(mutation.filters).toEqual({ destinataire_id: 'compte-a', lue: false });
});

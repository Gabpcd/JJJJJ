import React from 'react';
import { act, fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { BadgeNotification } from './PanneauNotifications';

const m = vi.hoisted(() => ({
  user: { id: 'compte-a' }, rows: [] as any[], channels: [] as any[], reads: [] as any[],
  failure: '' as string, pending: false, completions: [] as (() => void)[], info: vi.fn(), error: vi.fn(),
  countOverride: undefined as number | null | undefined, native: false, nativeListeners: [] as any[], joinThrows: false,
}));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => m.native } }));
vi.mock('@capacitor/app', () => ({ App: { addListener: vi.fn(async (_: string, callback: any) => {
  const handle = { remove: vi.fn(async () => undefined) };
  m.nativeListeners.push({ callback, handle });
  return handle;
}) } }));
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
        : { data: rows.slice(0, args.limit ?? 50).map(n => ({ ...n })), count: head && m.countOverride !== undefined ? m.countOverride : rows.length, error: null };
      const response = m.pending ? new Promise(r => m.completions.push(() => r(result))) : Promise.resolve(result);
      return response.then(resolve, reject);
    } };
    q.select = (_: string, options: any) => { args.options = options; return q; };
    q.eq = q.in = (k: string, v: any) => { args.filters[k] = v; return q; };
    q.order = () => q;
    q.limit = (limit: number) => { args.limit = limit; return q; };
    q.update = (update: any) => { args.update = update; return q; };
    q.abortSignal = (signal: AbortSignal) => { args.signal = signal; return q; };
    return q;
  },
  channel: (name: string) => {
    const ch: any = { name, on: (_: any, filter: any, cb: any) => { ch.insert = cb; ch.filter = filter; return ch; },
      subscribe: (cb: any) => { ch.status = cb; if (m.joinThrows) throw new Error('connexion simulée refusée'); return ch; } };
    m.channels.push(ch); return ch;
  },
  removeChannel: vi.fn(async () => 'ok'),
} }));
const row = (id: string, uid = 'compte-a') => ({ id, destinataire_id: uid, titre: `Notification ${id}`, corps: 'Fixture locale', type: 'SYSTEME', lue: false, lien: null, cree_le: '2026-09-30T08:00:00Z' });
const app = () => <MemoryRouter initialEntries={['/soignant/mon-compte']} future={{v7_startTransition:true,v7_relativeSplatPath:true}}><BadgeNotification /></MemoryRouter>;
const bell = (count: number) => screen.getByRole('button', { name: count ? `Notifications, ${count} non lue${count > 1 ? 's' : ''}` : 'Notifications' });
const status = async (value: string, channel = m.channels.at(-1)) => act(async () => channel.status(value));
const open = async (count = 1) => { fireEvent.click(bell(count)); await screen.findByText('Notification initiale'); };
beforeEach(() => {
  m.user = { id: 'compte-a' }; m.rows = [row('initiale')]; m.channels = []; m.reads = [];
  m.failure = ''; m.pending = false; m.completions = []; m.countOverride = undefined;
  m.native = false; m.nativeListeners = []; m.joinThrows = false; vi.clearAllMocks(); localStorage.setItem('notif_sound', 'off');
  vi.spyOn(HTMLElement.prototype, 'getClientRects').mockReturnValue([{}] as unknown as DOMRectList);
});
afterEach(() => { cleanup(); vi.useRealTimers(); vi.restoreAllMocks(); });

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
  expect(screen.queryByText('Notification initiale')).toBeNull(); expect(screen.queryByRole('dialog')).toBeNull();
  expect(screen.getByRole('button', { name: 'Notifications, compteur indisponible' })).toBeInTheDocument();
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

it.each(['CANDIDATURE_RECUE', 'SYSTEME'])('page masquée : %s conserve l’in-app et respecte son circuit OS', async type => {
  const os = vi.fn();
  const previous = Object.getOwnPropertyDescriptor(window, 'Notification');
  Object.defineProperty(window, 'Notification', { configurable: true, value: Object.assign(function Notification() { os(); }, { permission: 'granted' }) });
  vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
  try {
    render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
    await status('SUBSCRIBED');
    const nouvelle = { ...row('candidature'), type };
    m.rows.push(nouvelle);
    await act(async () => m.channels[0].insert({ new: nouvelle }));
    await screen.findByRole('button', { name: 'Notifications, 2 non lues' });
    expect(m.info).toHaveBeenCalledTimes(1);
    expect(os).toHaveBeenCalledTimes(type === 'CANDIDATURE_RECUE' ? 0 : 1);
  } finally {
    if (previous) Object.defineProperty(window, 'Notification', previous);
    else Reflect.deleteProperty(window, 'Notification');
  }
});

it('ne présente aucun zéro connu avant la première lecture complète, même si le flux échoue entretemps', async () => {
  m.pending = true;
  render(app());
  expect(screen.getByRole('button', { name: 'Notifications, compteur indisponible' })).toBeInTheDocument();
  expect(screen.queryByText('!')).toBeNull();
  await waitFor(() => expect(m.completions).toHaveLength(2));
  await status('CHANNEL_ERROR');
  expect(screen.getByRole('button', { name: 'Notifications, compteur indisponible, actualisation nécessaire' })).toBeInTheDocument();
  await act(async () => m.completions.splice(0).forEach(done => done()));
  const bouton = screen.getByRole('button', { name: 'Notifications, 1 non lue, actualisation nécessaire' });
  expect(bouton).toHaveTextContent('1');
  expect(bouton).toHaveAttribute('aria-description', expect.stringContaining('Connexion aux notifications interrompue'));
  expect(m.info).not.toHaveBeenCalled();
});

it('un compteur null demeure indisponible et un vrai zéro relu devient connu', async () => {
  m.rows = []; m.countOverride = null;
  render(app());
  const bouton = await screen.findByRole('button', { name: 'Notifications, compteur indisponible, actualisation nécessaire' });
  fireEvent.click(bouton);
  await screen.findByRole('alert');
  expect(screen.getByRole('button', { name: 'Tout marquer comme lu' })).toBeDisabled();
  expect(screen.queryByText('Aucune notification')).toBeNull();
  m.countOverride = undefined;
  await waitFor(() => expect(screen.getByRole('button', { name: 'Réessayer' })).not.toBeDisabled());
  fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await screen.findByText('Aucune notification');
  expect(bell(0)).toBeInTheDocument();
  expect(screen.queryByRole('alert')).toBeNull();
});

it.each(['CHANNEL_ERROR', 'CLOSED', 'TIMED_OUT'])('HTTP réussi après %s : garde l’erreur de flux, le vrai compteur et tente uniquement le canal interrompu', async panne => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  await status('SUBSCRIBED'); await open();
  const ancien = m.channels[0];
  await status(panne); m.rows.push(row('pendant-coupure'));
  fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await screen.findByText('Notification pendant-coupure');
  expect(screen.getByRole('button', { name: 'Notifications, 2 non lues, actualisation nécessaire' })).toHaveTextContent('2');
  expect(screen.getByRole('alert')).toHaveTextContent('Connexion aux notifications interrompue');
  expect(screen.queryByText('!')).toBeNull();
  expect(m.channels).toHaveLength(2);
  const { supabase } = await import('@/integrations/supabase/client');
  expect(supabase.removeChannel).toHaveBeenCalledWith(ancien);
  expect(m.channels[1].filter).toEqual({ event: 'INSERT', schema: 'public', table: 'notifications', filter: 'destinataire_id=eq.compte-a' });
  const lectures = m.reads.length;
  await act(async () => { ancien.status('SUBSCRIBED'); ancien.insert({ new: row('ancien-canal') }); });
  expect(m.reads).toHaveLength(lectures); expect(m.info).not.toHaveBeenCalled();
  await status('SUBSCRIBED');
  await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
  expect(bell(2)).toBeInTheDocument(); expect(m.info).not.toHaveBeenCalled();
  m.rows.push(row('après-reprise'));
  await act(async () => m.channels[1].insert({ new: row('après-reprise') }));
  await screen.findByText('Notification après-reprise'); expect(m.info).toHaveBeenCalledTimes(1);
});

it('distingue les deux pannes et ne laisse pas SUBSCRIBED masquer une lecture encore en échec', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  await status('SUBSCRIBED'); await open();
  await status('CHANNEL_ERROR'); m.failure = 'count';
  fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Impossible d’actualiser'));
  expect(screen.getByRole('alert')).toHaveTextContent('Connexion aux notifications interrompue');
  await status('SUBSCRIBED');
  await waitFor(() => expect(screen.getByRole('alert')).not.toHaveTextContent('Connexion aux notifications interrompue'));
  expect(screen.getByRole('alert')).toHaveTextContent('Impossible d’actualiser');
  m.failure = ''; fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
  expect(bell(1)).toBeInTheDocument();
});

it('une tentative de connexion qui lève immédiatement ne bloque pas la relecture HTTP', async () => {
  render(app()); await screen.findByRole('button', { name: 'Notifications, 1 non lue' });
  await status('SUBSCRIBED'); await open();
  await status('CHANNEL_ERROR'); m.joinThrows = true; m.rows.push(row('lecture-disponible'));
  fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
  await screen.findByText('Notification lecture-disponible');
  expect(screen.getByRole('button', { name: 'Notifications, 2 non lues, actualisation nécessaire' })).toBeInTheDocument();
  expect(screen.getByRole('alert')).toHaveTextContent('Connexion aux notifications interrompue');
  expect(screen.queryByText('Actualisation...')).toBeNull();
  expect(m.info).not.toHaveBeenCalled();
});

it('regroupe les signaux web et borne la reprise automatique sans recréer un canal déjà connecté', async () => {
  vi.useFakeTimers();
  await act(async () => { render(app()); });
  await status('SUBSCRIBED');
  const lectures = m.reads.length;
  m.rows.push(row('hors-page'));
  await act(async () => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('online'));
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(250);
  });
  expect(m.reads).toHaveLength(lectures + 2); expect(bell(2)).toBeInTheDocument();
  expect(m.channels).toHaveLength(1); expect(m.info).not.toHaveBeenCalled();
  await act(async () => {
    window.dispatchEvent(new Event('online'));
    document.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(4_999);
  });
  expect(m.reads).toHaveLength(lectures + 2);
  await act(async () => { await vi.advanceTimersByTimeAsync(1); });
  expect(m.reads).toHaveLength(lectures + 4);
  await act(async () => { await vi.advanceTimersByTimeAsync(20_000); });
  expect(m.reads).toHaveLength(lectures + 4); // aucun polling ni boucle de retry.
});

it('ne relit pas en arrière-plan et reprend une fois au retour visible', async () => {
  vi.useFakeTimers();
  const visibilite = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
  await act(async () => { render(app()); });
  await status('SUBSCRIBED');
  const lectures = m.reads.length;
  visibilite.mockReturnValue('hidden');
  await act(async () => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(6_000);
  });
  expect(m.reads).toHaveLength(lectures);
  visibilite.mockReturnValue('visible');
  await act(async () => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(250);
  });
  expect(m.reads).toHaveLength(lectures + 2);
});

it('reprend les deux lecteurs natifs une fois chacun et retire seulement leurs anciens canaux', async () => {
  vi.useFakeTimers(); m.native = true;
  await act(async () => {
    render(<MemoryRouter future={{v7_startTransition:true,v7_relativeSplatPath:true}}><div hidden><BadgeNotification /></div><BadgeNotification /></MemoryRouter>);
  });
  const anciens = [...m.channels];
  await act(async () => anciens.forEach(c => c.status('CHANNEL_ERROR')));
  const lectures = m.reads.length;
  m.rows.push(row('retour-natif'));
  await act(async () => {
    m.nativeListeners.forEach(l => l.callback({ isActive: false }));
    m.nativeListeners.forEach(l => { l.callback({ isActive: true }); l.callback({ isActive: true }); });
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(250);
  });
  expect(m.channels).toHaveLength(4); expect(m.reads).toHaveLength(lectures + 4);
  expect(screen.getAllByLabelText('Notifications, 2 non lues, actualisation nécessaire')).toHaveLength(2);
  const { supabase } = await import('@/integrations/supabase/client');
  expect(supabase.removeChannel).toHaveBeenCalledTimes(2);
  anciens.forEach(c => expect(supabase.removeChannel).toHaveBeenCalledWith(c));
  expect(m.info).not.toHaveBeenCalled();
});

it('annule une reprise programmée au démontage et ignore les callbacks natifs conservés', async () => {
  vi.useFakeTimers(); m.native = true;
  let view!: ReturnType<typeof render>;
  await act(async () => { view = render(app()); });
  const listener = m.nativeListeners[0];
  act(() => listener.callback({ isActive: true }));
  const lectures = m.reads.length;
  view.unmount();
  await act(async () => {
    listener.callback({ isActive: true });
    window.dispatchEvent(new Event('online'));
    document.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(20_000);
  });
  expect(listener.handle.remove).toHaveBeenCalledTimes(1);
  expect(m.reads).toHaveLength(lectures); expect(m.channels).toHaveLength(1);
});

it('borne une lecture bloquée à 15 secondes en conservant le dernier compteur exact', async () => {
  vi.useFakeTimers();
  await act(async () => { render(app()); });
  await status('SUBSCRIBED');
  m.pending = true; m.rows.push(row('tardive'));
  await act(async () => { fireEvent.click(bell(1)); });
  expect(m.completions).toHaveLength(2);
  const signal = m.reads.at(-1).signal as AbortSignal;
  await act(async () => { await vi.advanceTimersByTimeAsync(15_000); });
  expect(signal.aborted).toBe(true);
  expect(screen.getByRole('alert')).toHaveTextContent('Impossible d’actualiser');
  expect(screen.getByRole('button', { name: 'Notifications, 1 non lue, actualisation nécessaire' })).toBeInTheDocument();
  expect(screen.queryByText('Actualisation...')).toBeNull();
  await act(async () => m.completions.splice(0).forEach(done => done()));
  expect(screen.queryByText('Notification tardive')).toBeNull();
  expect(screen.getByRole('alert')).toBeInTheDocument();
});

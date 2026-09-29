import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { NativeSessionResume } from './NativeSessionResume';
import { signalerNavigationNative } from '@/lib/nativeResume';

const mock = vi.hoisted(() => ({ native: true, user: { id: 'user' } as { id: string } | null, role: 'SOIGNANT', parcours: null as null | { type_compte: string }, listener: (_: { isActive: boolean }) => {} }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => mock.native } }));
vi.mock('@capacitor/app', () => ({ App: { addListener: vi.fn(async (_, callback) => { mock.listener = callback; return { remove: vi.fn() }; }) } }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mock.user, loading: false }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: mock.role, parcours: mock.parcours }) }));
function Route() { return <><output>{useLocation().pathname}</output><form><input aria-label="Brouillon" /></form><textarea aria-label="Message" /><canvas aria-label="Signature" /></>; }
function mount(path = '/soignant/missions') { return render(<MemoryRouter initialEntries={[path]}><NativeSessionResume /><Route /></MemoryRouter>); }
async function absence(ms: number) {
  act(() => mock.listener({ isActive: false }));
  await act(async () => { await vi.advanceTimersByTimeAsync(ms); mock.listener({ isActive: true }); mock.listener({ isActive: true }); await vi.advanceTimersByTimeAsync(400); });
}
let scenario = 0;
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-09-29T12:00:00Z').getTime() + ++scenario * 86400_000); localStorage.clear(); mock.user = { id: 'user' }; mock.native = true; mock.role = 'SOIGNANT'; mock.parcours = null; });
afterEach(() => { cleanup(); vi.useRealTimers(); });
it.each([['SOIGNANT', null, '/soignant/tableau-de-bord'], ['ADMIN_ETABLISSEMENT', null, '/etablissement/tableau-de-bord'], ['INCONNU', { type_compte: 'SOIGNANT' }, '/soignant/tableau-de-bord'], ['INCONNU', { type_compte: 'ETABLISSEMENT' }, '/etablissement/tableau-de-bord']] as const)('returns %s to the dashboard without changing the session', async (role, parcours, path) => {
  mock.role = role; mock.parcours = parcours; const user = mock.user; mount(); await absence(31 * 60_000);
  expect(screen.getByRole('status')).toHaveTextContent(path); expect(mock.user).toBe(user);
});
it('keeps the active tab after a brief interruption', async () => { mount(); await absence(60_000); expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions'); });
it('restores a persisted long absence only for this account', async () => {
  localStorage.setItem('jolene.native.background.user', String(Date.now() - 86400_000)); mount();
  await act(async () => { await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/tableau-de-bord');
});
it('keeps an unsaved form after a long interruption', async () => {
  mount(); fireEvent.input(screen.getByLabelText('Brouillon'), { target: { value: 'À conserver' } }); await absence(31 * 60_000);
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions'); expect(screen.getByLabelText('Brouillon')).toHaveValue('À conserver');
});
it('lets an explicit notification win during resume', async () => {
  mount(); act(() => mock.listener({ isActive: false }));
  await act(async () => { await vi.advanceTimersByTimeAsync(31 * 60_000); mock.listener({ isActive: true }); signalerNavigationNative(); await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions');
});
it.each(['/auth/psc/callback?code=test', '/contrat/123', '/soignant/mon-compte?success=1'])('preserves the external flow %s', async path => {
  mount(path); await absence(31 * 60_000); expect(screen.getByRole('status')).toHaveTextContent(path.split('?')[0]);
});
it('does not redirect the web app or another account', async () => {
  mock.native = false; localStorage.setItem('jolene.native.background.someone-else', '1'); mount();
  await act(async () => { await vi.advanceTimersByTimeAsync(400); }); expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions');
});

it('keeps a pending cold-start decision across a temporary role revalidation', async () => {
  localStorage.setItem('jolene.native.background.user', String(Date.now() - 86400_000));
  const tree = <MemoryRouter initialEntries={['/soignant/missions']}><NativeSessionResume /><Route /></MemoryRouter>;
  const view = render(tree);
  await act(async () => { await vi.advanceTimersByTimeAsync(100); });
  mock.role = 'INCONNU';
  view.rerender(<MemoryRouter initialEntries={['/soignant/missions']}><NativeSessionResume /><Route /></MemoryRouter>);
  expect(localStorage.getItem('jolene.native.background.user')).not.toBeNull();
  mock.role = 'SOIGNANT';
  view.rerender(<MemoryRouter initialEntries={['/soignant/missions']}><NativeSessionResume /><Route /></MemoryRouter>);
  await act(async () => { await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/tableau-de-bord');
  expect(localStorage.getItem('jolene.native.background.user')).toBeNull();
});

it('preserves an unsaved message outside a form', async () => {
  mount(); fireEvent.input(screen.getByLabelText('Message'), { target: { value: 'Brouillon hors formulaire' } });
  await absence(31 * 60_000); expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions');
  expect(screen.getByLabelText('Message')).toHaveValue('Brouillon hors formulaire');
});
it('preserves canvas input outside a form', async () => {
  mount(); fireEvent.pointerDown(screen.getByLabelText('Signature')); await absence(31 * 60_000);
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/missions');
});
it.each([true, false])('only preserves a visible custom dialog (visible=%s)', async visible => {
  mount(); const dialog = document.createElement('div'); dialog.setAttribute('role', 'dialog'); document.body.append(dialog);
  vi.spyOn(dialog, 'getClientRects').mockReturnValue((visible ? [{ width: 300, height: 100 }] : []) as unknown as DOMRectList);
  await absence(31 * 60_000);
  expect(screen.getByRole('status')).toHaveTextContent(visible ? '/soignant/missions' : '/soignant/tableau-de-bord'); dialog.remove();
});
it('preserves the cold-start link during slow authentication, but not the next absence', async () => {
  localStorage.setItem('jolene.native.background.user', String(Date.now() - 86400_000));
  signalerNavigationNative(); await vi.advanceTimersByTimeAsync(15_000); mount('/soignant/messagerie');
  await act(async () => { await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByRole('status')).toHaveTextContent('/soignant/messagerie');
  await absence(31 * 60_000); expect(screen.getByRole('status')).toHaveTextContent('/soignant/tableau-de-bord');
});

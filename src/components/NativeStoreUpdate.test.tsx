import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { NativeStoreUpdate, VERIFIER_MISE_A_JOUR } from './NativeStoreUpdate';

const mock = vi.hoisted(() => ({ get: vi.fn(), open: vi.fn(), success: vi.fn(), error: vi.fn(), info: vi.fn(), listener: (_: { isActive: boolean }) => {} }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => true, isPluginAvailable: () => true } }));
vi.mock('@capacitor/app', () => ({ App: { addListener: vi.fn(async (_, callback) => { mock.listener = callback; return { remove: vi.fn() }; }) } }));
vi.mock('@capawesome/capacitor-app-update', () => ({ AppUpdate: { getAppUpdateInfo: mock.get, openAppStore: mock.open }, AppUpdateAvailability: { UNKNOWN: 0, UPDATE_NOT_AVAILABLE: 1, UPDATE_AVAILABLE: 2, UPDATE_IN_PROGRESS: 3 } }));
vi.mock('sonner', () => ({ toast: { success: mock.success, error: mock.error, info: mock.info } }));
beforeEach(() => { vi.clearAllMocks(); mock.get.mockResolvedValue({ updateAvailability: 2, availableVersionName: '1.0.7' }); mock.open.mockResolvedValue(undefined); });
afterEach(cleanup);
it('shows a store update, opens the correct app and permits dismissal without blocking navigation', async () => {
  render(<NativeStoreUpdate />); const button = await screen.findByRole('button', { name: 'Mettre à jour' }); fireEvent.click(button);
  await waitFor(() => expect(mock.open).toHaveBeenCalledWith({ appId: '6774672845', androidPackageName: 'app.jolene' }));
  fireEvent.click(screen.getByRole('button', { name: 'Me le rappeler plus tard' })); expect(screen.queryByRole('complementary')).not.toBeInTheDocument();
  await act(async () => window.dispatchEvent(new Event(VERIFIER_MISE_A_JOUR)));
  expect(await screen.findByRole('button', { name: 'Mettre à jour' })).toBeVisible();
});
it('does not advertise a version that the store has not made available', async () => {
  mock.get.mockResolvedValue({ updateAvailability: 1 }); render(<NativeStoreUpdate />);
  await act(async () => {}); expect(screen.queryByRole('complementary')).not.toBeInTheDocument();
  await act(async () => window.dispatchEvent(new Event(VERIFIER_MISE_A_JOUR))); expect(mock.success).toHaveBeenCalledWith('Jolene est à jour sur cet appareil.');
});
it('does not call a failed or unknown check up to date', async () => {
  mock.get.mockRejectedValue(new Error('Offline')); render(<NativeStoreUpdate />); await act(async () => {});
  await act(async () => window.dispatchEvent(new Event(VERIFIER_MISE_A_JOUR)));
  expect(mock.error).toHaveBeenCalled(); expect(mock.success).not.toHaveBeenCalled(); expect(screen.queryByRole('complementary')).not.toBeInTheDocument();
});
it('throttles ordinary resume checks', async () => {
  render(<NativeStoreUpdate />); await screen.findByRole('complementary');
  await act(async () => { mock.listener({ isActive: true }); mock.listener({ isActive: true }); }); expect(mock.get).toHaveBeenCalledTimes(1);
});

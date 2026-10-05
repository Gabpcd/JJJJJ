import React, { Suspense } from 'react';
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import * as Sentry from '@sentry/react';
import { ErrorBoundary } from '@/components/ErrorBoundary';
import { APP_RELEASE, installVitePreloadRecovery } from './chunkRecovery';
import { lazyRetry } from './lazyRetry';

vi.mock('@sentry/react', () => ({ captureException: vi.fn() }));

// Contrat du helper de préchargement Vite 8.1.4 : annuler l'événement fait
// résoudre le catch avec undefined. La promesse ne conserve alors plus le rejet.
function importerAvecPrechargement(factory: () => Promise<{ default: React.ComponentType }>) {
  return factory().catch((error: unknown) => {
    const event = new Event('vite:preloadError', { cancelable: true });
    Object.assign(event, { payload: error });
    window.dispatchEvent(event);
    if (!event.defaultPrevented) throw error;
  }) as Promise<{ default: React.ComponentType }>;
}

const reload = vi.fn();
let desinstaller: () => void;
function afficher(factory: () => Promise<{ default: React.ComponentType }>) {
  const Page = lazyRetry(factory);
  return render(<ErrorBoundary><Suspense fallback={<p>Chargement de la page</p>}><Page /></Suspense></ErrorBoundary>);
}

beforeEach(() => {
  vi.clearAllMocks();
  window.sessionStorage.clear();
  const location = window.location;
  vi.spyOn(window, 'location', 'get').mockReturnValue({ ...location, reload } as Location);
  vi.spyOn(console, 'error').mockImplementation(() => {});
  desinstaller = installVitePreloadRecovery();
});
afterEach(() => { cleanup(); desinstaller(); vi.restoreAllMocks(); });

describe('React.lazy et récupération du préchargement Vite', () => {
  it('rend un module chargé sans recharger ni signaler une erreur', async () => {
    afficher(() => importerAvecPrechargement(async () => ({ default: () => <h1>Page disponible</h1> })));
    expect(await screen.findByRole('heading', { name: 'Page disponible' })).toBeVisible();
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('garde le rejet original pendant le reload, sans module undefined ni second reload', async () => {
    const erreur = new TypeError('Importing a module script failed.');
    afficher(() => importerAvecPrechargement(() => Promise.reject(erreur)));
    expect(await screen.findByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
    expect(reload).toHaveBeenCalledTimes(1);
    expect(Sentry.captureException).toHaveBeenCalledExactlyOnceWith(erreur, expect.any(Object));
    expect(JSON.parse(window.sessionStorage.getItem('jolene:chunk-recovery')!)).toMatchObject({ release: APP_RELEASE });
  });

  it('laisse une panne persistante à l’ErrorBoundary après un rechargement de la même release', async () => {
    window.sessionStorage.setItem('jolene:chunk-recovery', JSON.stringify({ release: APP_RELEASE, at: Date.now() }));
    const erreur = new TypeError('Failed to fetch dynamically imported module: /assets/Page-old.js');
    afficher(() => importerAvecPrechargement(() => Promise.reject(erreur)));
    expect(await screen.findByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).toHaveBeenCalledExactlyOnceWith(erreur, expect.any(Object));
    expect(screen.getByRole('button', { name: 'Rafraîchir la page' })).toBeEnabled();
  });

  it('ne masque pas une erreur applicative et ne la transforme pas en rechargement', async () => {
    const erreur = new Error('Erreur métier du module');
    afficher(() => importerAvecPrechargement(() => Promise.reject(erreur)));
    expect(await screen.findByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).toHaveBeenCalledExactlyOnceWith(erreur, expect.any(Object));
  });

  it('conserve le rejet et évite une boucle si le marqueur de session ne peut pas être écrit', async () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new DOMException('Stockage refusé', 'QuotaExceededError'); });
    const erreur = new TypeError('Importing a module script failed.');
    afficher(() => importerAvecPrechargement(() => Promise.reject(erreur)));
    expect(await screen.findByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).toHaveBeenCalledExactlyOnceWith(erreur, expect.any(Object));
  });

  it('conserve le comportement lazyRetry pour un rejet direct sans événement Vite', async () => {
    afficher(() => Promise.reject(new TypeError('Importing a module script failed.')));
    await waitFor(() => expect(reload).toHaveBeenCalledTimes(1));
    await act(async () => { await Promise.resolve(); });
    expect(screen.getByText('Chargement de la page')).toBeVisible();
    expect(screen.queryByRole('heading', { name: 'Une erreur est survenue' })).not.toBeInTheDocument();
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('conserve le rejet si l’accès à sessionStorage est lui-même interdit', async () => {
    vi.spyOn(window, 'sessionStorage', 'get').mockImplementation(() => {
      throw new DOMException('Stockage inaccessible', 'SecurityError');
    });
    const erreur = new TypeError('Importing a module script failed.');
    afficher(() => importerAvecPrechargement(() => Promise.reject(erreur)));
    expect(await screen.findByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).toHaveBeenCalledExactlyOnceWith(erreur, expect.any(Object));
  });
});

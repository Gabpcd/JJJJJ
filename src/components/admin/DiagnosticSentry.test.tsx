import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DiagnosticSentry } from './DiagnosticSentry';

const mocks = vi.hoisted(() => ({ getClient: vi.fn(), isEnabled: vi.fn(), captureException: vi.fn() }));
vi.mock('@sentry/react', () => mocks);

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv('VITE_SENTRY_DSN', 'https://fixture@example.invalid/1');
  mocks.getClient.mockReturnValue({});
  mocks.isEnabled.mockReturnValue(true);
  mocks.captureException.mockReturnValue('a'.repeat(32));
});
afterEach(() => { cleanup(); vi.unstubAllEnvs(); });

describe('Diagnostic Sentry — configuration et tentative sans fausse réception', () => {
  it.each(['', '   '])('désactive le test sans DSN (%j)', dsn => {
    vi.stubEnv('VITE_SENTRY_DSN', dsn);
    render(<DiagnosticSentry />);
    expect(screen.getByText('Sentry non configuré pour cette version.')).toBeVisible();
    const bouton = screen.getByRole('button', { name: 'Tester Sentry' });
    expect(bouton).toBeDisabled();
    fireEvent.click(bouton);
    expect(mocks.captureException).not.toHaveBeenCalled();
  });
  it.each(['absent', 'désactivé'])('désactive le test pour un client %s', etat => {
    if (etat === 'absent') mocks.getClient.mockReturnValue(undefined);
    else mocks.isEnabled.mockReturnValue(false);
    render(<DiagnosticSentry />);
    expect(screen.getByRole('button', { name: 'Tester Sentry' })).toBeDisabled();
    expect(screen.getByText('Sentry configuré, mais le client est indisponible ou désactivé.')).toBeVisible();
    expect(mocks.captureException).not.toHaveBeenCalled();
  });
  it('recontrôle la disponibilité au clic', () => {
    render(<DiagnosticSentry />);
    mocks.isEnabled.mockReturnValue(false);
    fireEvent.click(screen.getByRole('button', { name: 'Tester Sentry' }));
    expect(screen.getByRole('status')).toHaveTextContent('client est indisponible ou désactivé');
    expect(mocks.captureException).not.toHaveBeenCalled();
  });
  it('annonce seulement une tentative et garde une référence locale', () => {
    const vue = render(<DiagnosticSentry />);
    fireEvent.click(screen.getByRole('button', { name: 'Tester Sentry' }));
    expect(mocks.captureException).toHaveBeenCalledOnce();
    expect(mocks.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { test: 'true', source: 'admin-diagnostic' }, level: 'info',
    });
    expect(screen.getByRole('status')).toHaveTextContent(`Tentative d’envoi effectuée. La réception reste à confirmer dans Sentry. Référence : ${'a'.repeat(32)}.`);
    expect(screen.queryByText('Erreur test envoyée à Sentry. Vérifiez le dashboard.')).not.toBeInTheDocument();
    vue.unmount(); render(<DiagnosticSentry />);
    expect(screen.getByRole('status')).toBeEmptyDOMElement();
    expect(mocks.captureException).toHaveBeenCalledOnce();
  });
  it('n’affiche pas une réponse SDK inattendue potentiellement sensible', () => {
    mocks.captureException.mockReturnValue('configuration-privee');
    render(<DiagnosticSentry />);
    fireEvent.click(screen.getByRole('button', { name: 'Tester Sentry' }));
    expect(screen.getByRole('status')).toHaveTextContent('réception reste à confirmer');
    expect(screen.queryByText(/configuration-privee/)).not.toBeInTheDocument();
  });
  it('affiche l’échec sans exposer l’exception SDK', () => {
    mocks.captureException.mockImplementation(() => { throw new Error('configuration-privee'); });
    render(<DiagnosticSentry />);
    fireEvent.click(screen.getByRole('button', { name: 'Tester Sentry' }));
    expect(screen.getByRole('status')).toHaveTextContent('Le diagnostic Sentry a échoué. Aucun envoi confirmé.');
    expect(screen.queryByText(/configuration-privee/)).not.toBeInTheDocument();
  });
});

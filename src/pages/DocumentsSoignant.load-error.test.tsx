import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DocumentsSoignantContent } from './DocumentsSoignant';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  user: { id: 'soignant-test' },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user }),
}));

vi.mock('@/lib/handleError', () => ({ handleErrorSilent: vi.fn() }));

vi.mock('@/components/ChargementPage', () => ({
  ChargementPage: () => <p>Chargement</p>,
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
  ),
}));

vi.mock('@/integrations/supabase/client', () => {
  const resultatEnErreur = { data: null, error: new Error('réseau indisponible') };
  const creerBuilder = () => {
    const builder: Record<string, any> = {};
    for (const methode of ['select', 'eq', 'is', 'order']) builder[methode] = () => builder;
    builder.maybeSingle = () => Promise.resolve(resultatEnErreur);
    builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
      Promise.resolve(resultatEnErreur).then(resolve, reject);
    return builder;
  };
  mocks.from.mockImplementation(() => creerBuilder());
  return {
    supabase: {
      from: mocks.from,
      rpc: vi.fn(),
      storage: { from: vi.fn() },
    },
  };
});

describe('DocumentsSoignant — échec de chargement', () => {
  beforeEach(() => {
    mocks.from.mockClear();
  });

  it('affiche une erreur persistante, jamais le faux succès, et permet de réessayer', async () => {
    render(
      <MemoryRouter>
        <DocumentsSoignantContent />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Documents indisponibles');
    expect(screen.queryByText(/Tous tes documents obligatoires sont à jour/i)).not.toBeInTheDocument();

    const appelsInitiaux = mocks.from.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));

    await waitFor(() => expect(mocks.from.mock.calls.length).toBeGreaterThan(appelsInitiaux));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
  });
});

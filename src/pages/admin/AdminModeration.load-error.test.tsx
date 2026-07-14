import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AdminModeration from './AdminModeration';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  from: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/admin/ChargementAdmin', () => ({
  ChargementAdmin: () => <p>Chargement</p>,
}));

vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
  ),
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

vi.mock('sonner', () => ({
  toast: { error: mocks.toastError, success: vi.fn() },
}));

vi.mock('@/integrations/supabase/client', () => {
  const creerBuilder = () => {
    const resultat = { data: [], error: null, count: 0 };
    const builder: Record<string, any> = {};
    for (const methode of ['select', 'in', 'order', 'eq', 'limit', 'is', 'lt']) builder[methode] = () => builder;
    builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
      Promise.resolve(resultat).then(resolve, reject);
    return builder;
  };
  mocks.from.mockImplementation(() => creerBuilder());
  return {
    supabase: {
      from: mocks.from,
      rpc: mocks.rpc,
      storage: { from: vi.fn() },
    },
  };
});

describe('AdminModeration — échec de chargement', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.from.mockClear();
    mocks.toastError.mockReset();
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('service indisponible') });
  });

  it('masque toutes les files partielles et propose un nouveau chargement', async () => {
    render(
      <MemoryRouter>
        <AdminModeration />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Modération indisponible');
    expect(screen.queryByRole('tablist')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });
});

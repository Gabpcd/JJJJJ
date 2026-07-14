import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AdminRevuesManuelles from './AdminRevuesManuelles';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  notification: vi.fn(),
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ui/EmptyState', () => ({
  EmptyState: ({ titre }: { titre: string }) => <p>{titre}</p>,
}));

vi.mock('@/components/y2k/CardY2K', () => ({
  CardY2K: ({ children }: { children: React.ReactNode }) => <article>{children}</article>,
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, variant: _variant, size: _size, ...props }: any) => (
    <button type="button" {...props}>{children}</button>
  ),
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.notification }),
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    storage: { from: vi.fn() },
  },
}));

describe('AdminRevuesManuelles', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.notification.mockReset();
  });

  it('reste fail-closed si la file AAL2 ne peut pas être chargée', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('service indisponible') });

    render(
      <MemoryRouter>
        <AdminRevuesManuelles />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('File indisponible');
    expect(screen.queryByText('Aucune revue en attente')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });

  it('n’affiche l’état vide qu’après une réponse serveur valide', async () => {
    mocks.rpc.mockResolvedValue({
      data: { success: true, revues: [] },
      error: null,
    });

    render(
      <MemoryRouter>
        <AdminRevuesManuelles />
      </MemoryRouter>,
    );

    expect(await screen.findByText('Aucune revue en attente')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
});

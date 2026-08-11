import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AdminExternalisationsActions from './AdminExternalisationsActions';
import AdminVerificationEtablissements from './AdminVerificationEtablissements';

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

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, loading: _loading, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
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

describe('files admin — échec de chargement', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.notification.mockReset();
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('service indisponible') });
  });

  it('ne transforme pas une erreur établissements en file vide réussie', async () => {
    render(<AdminVerificationEtablissements />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Dossiers indisponibles');
    expect(screen.queryByText('Aucun dossier en attente')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });

  it('écarte les fixtures de la file opérationnelle des établissements', async () => {
    mocks.rpc.mockResolvedValueOnce({
      data: {
        success: true,
        etablissements: [{ id: 'fixture-etab', nom: 'Établissement test', est_compte_test: true }],
      },
      error: null,
    });

    render(<AdminVerificationEtablissements />);

    expect(await screen.findByText('Aucun dossier en attente')).toBeInTheDocument();
    expect(screen.queryByText('Établissement test')).not.toBeInTheDocument();
  });

  it('ne transforme pas une erreur d’externalisation en succès et expose un retry', async () => {
    render(<AdminExternalisationsActions />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Actions indisponibles');
    expect(screen.queryByText('Toutes les actions ont été traitées')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });
});

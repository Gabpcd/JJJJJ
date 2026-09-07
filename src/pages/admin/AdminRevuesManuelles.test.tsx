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

  it('permet à l’admin seule de retrouver immédiatement une revue dans une file chargée', async () => {
    const revue = (id: string, nom: string, estCompteTest: boolean) => ({
      id,
      type_entite: 'TELEVERSEMENT_DOCUMENT',
      id_entite: id,
      service_en_echec: 'REVUE_DEMANDEE_PAR_SOIGNANT',
      motif_echec: 'Contrôle humain demandé',
      statut: 'EN_ATTENTE',
      priorite: 4,
      cree_le: '2026-09-07T12:00:00Z',
      expire_le: null,
      est_compte_test: estCompteTest,
      decision_directe: false,
      ressource_libelle: nom,
      route_ressource: '/admin/moderation?onglet=documents',
      preuve_bucket: 'documents',
      preuve_path: `${id}.pdf`,
      preuve_type: 'DIPLOME',
      contexte: {},
      jeton_cas: `jeton-${id}`,
    });
    mocks.rpc.mockResolvedValue({
      data: {
        success: true,
        revues: [
          revue('1', 'Camille Audit', true),
          revue('2', 'Clinique Réelle', false),
        ],
      },
      error: null,
    });

    render(
      <MemoryRouter>
        <AdminRevuesManuelles />
      </MemoryRouter>,
    );

    expect(await screen.findByText('Camille Audit')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Retrouver une revue'), { target: { value: 'Clinique' } });
    expect(screen.getByText('Clinique Réelle')).toBeInTheDocument();
    expect(screen.queryByText('Camille Audit')).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('Retrouver une revue'), { target: { value: '' } });
    fireEvent.click(screen.getByRole('button', { name: 'Tests' }));
    expect(screen.getByText('Camille Audit')).toBeInTheDocument();
    expect(screen.queryByText('Clinique Réelle')).not.toBeInTheDocument();
    expect(screen.getByText('1 revue affichée sur 2 en attente')).toBeInTheDocument();
  });
});

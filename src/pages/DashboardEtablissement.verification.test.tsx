import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import DashboardEtablissement from './DashboardEtablissement';

const mocks = vi.hoisted(() => ({
  publication: undefined as boolean | null | undefined,
  bloqueLe: null as string | null,
}));
vi.mock('@tanstack/react-query', () => ({
  useQuery: () => ({ isLoading: false, data: {
    etab: { nom: 'Établissement de recette', peut_publier_missions: mocks.publication, bloque_auto_le: mocks.bloqueLe },
    aDejaPublie: false,
  } }),
  useQueryClient: () => ({ resetQueries: vi.fn() }),
}));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => ({ user: { id: 'recette' }, etablissementId: 'recette' }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: { children: React.ReactNode }) => <main>{children}</main> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

describe('Cohérence de la vérification sur la première mission', () => {
  it.each([false, null, undefined])('ne confirme pas la vérification quand peut_publier_missions vaut %s', (publication) => {
    mocks.publication = publication;
    mocks.bloqueLe = null;
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByText('Votre compte est en cours de vérification')).toBeInTheDocument();
    expect(screen.getByText('Vérification en cours')).toBeInTheDocument();
    expect(screen.queryByText('Validé', { exact: true })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Publier une mission' })).toBeEnabled();
  });

  it('confirme la vérification seulement lorsque la publication est autorisée explicitement', () => {
    mocks.publication = true;
    mocks.bloqueLe = null;
    render(<MemoryRouter><DashboardEtablissement /></MemoryRouter>);
    expect(screen.getByText('Validé', { exact: true })).toBeInTheDocument();
    expect(screen.queryByText('Votre compte est en cours de vérification')).not.toBeInTheDocument();
    expect(screen.queryByText('Vérification en cours')).not.toBeInTheDocument();
  });
});

import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AdminCalendrier from './AdminCalendrier';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));

vi.mock('@/components/admin/ChargementAdmin', () => ({
  ChargementAdmin: () => <p>Chargement</p>,
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from },
}));

function creerBuilder(data: unknown[]) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'gte', 'lte', 'order', 'in', 'eq', 'not']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
    Promise.resolve({ data, error: null }).then(resolve, reject);
  return builder;
}

describe('AdminCalendrier', () => {
  let creneauxBuilder: Record<string, any>;
  let missionsData: unknown[];
  let creneauxData: unknown[];

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 6, 31, 12));
    mocks.from.mockReset();
    creneauxData = [
      {
        mission_id: 'mission-longue',
        debut: '2026-07-06T08:00:00.000Z',
        fin: '2026-07-06T16:00:00.000Z',
      },
      {
        mission_id: 'mission-longue',
        debut: '2026-08-31T08:00:00.000Z',
        fin: '2026-08-31T16:00:00.000Z',
      },
    ];
    missionsData = [{
      id: 'mission-longue',
      intitule: 'Mission IDE — médecine polyvalente',
      debut_le: '2026-07-06T08:00:00.000Z',
      fin_le: '2026-08-31T16:00:00.000Z',
      statut: 'EN_COURS',
      soignant_assigne_id: 'soignant-1',
      etablissement_id: 'etablissement-1',
      profession_requise: 'IDE',
      service: null,
      est_urgente: false,
    }];

    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder(missionsData);
      }
      if (table === 'mission_creneaux') {
        creneauxBuilder = creerBuilder(creneauxData);
        return creneauxBuilder;
      }
      if (table === 'etablissements') {
        return creerBuilder([{ id: 'etablissement-1', nom: 'Établissement test' }]);
      }
      if (table === 'soignants') {
        return creerBuilder([{ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre' }]);
      }
      return creerBuilder([]);
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('affiche une mission longue uniquement les jours de ses créneaux prévisionnels', async () => {
    render(
      <MemoryRouter>
        <AdminCalendrier />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Calendrier des missions' })).toBeInTheDocument();

    // Le créneau du 6 juillet est rendu une fois dans l'agenda mobile et une fois
    // dans la grille desktop. L'ancien calcul par plage en produisait un par jour.
    expect(screen.getAllByText('Mission IDE — médecine polyvalente')).toHaveLength(2);
    expect(screen.getByRole('button', { name: '1 active' })).toBeInTheDocument();
    expect(screen.queryByText('Mission en cours toute la journée')).not.toBeInTheDocument();
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('type_creneau', 'PREVISIONNEL');
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('est_pause', false);
  });

  it('découpe une garde de nuit à minuit dans chacun des deux jours', async () => {
    missionsData = [{
      ...(missionsData[0] as Record<string, unknown>),
      id: 'mission-nuit',
      intitule: 'Garde IDE de nuit',
      debut_le: '2026-07-06T18:00:00.000Z',
      fin_le: '2026-07-07T04:00:00.000Z',
    }];
    creneauxData = [{
      mission_id: 'mission-nuit',
      debut: '2026-07-06T18:00:00.000Z',
      fin: '2026-07-07T04:00:00.000Z',
    }];

    render(
      <MemoryRouter>
        <AdminCalendrier />
      </MemoryRouter>,
    );

    expect(await screen.findByText(/20:00–00:00/)).toBeInTheDocument();
    expect(screen.getByText(/00:00–06:00/)).toBeInTheDocument();
    expect(screen.queryByText('20:00–06:00')).not.toBeInTheDocument();
  });
});

import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AdminPlanningGlobal from './AdminPlanningGlobal';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  toastError: vi.fn(),
  chargerCreneaux: vi.fn(),
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));
vi.mock('@/lib/mission-creneaux-pagines', () => ({
  chargerCreneauxMissionsPagines: mocks.chargerCreneaux,
}));
vi.mock('sonner', () => ({ toast: { error: mocks.toastError } }));

type ResultatBuilder = { data: unknown[] | null; error: { message: string } | null };

function creerBuilder(resultat: ResultatBuilder) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'gt', 'lt', 'order', 'in', 'eq', 'not']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.then = (resolve: (value: ResultatBuilder) => unknown, reject: (reason: unknown) => unknown) =>
    Promise.resolve(resultat).then(resolve, reject);
  return builder;
}

const missionLongue = {
  id: 'mission-longue',
  intitule: 'Mission IDE — médecine polyvalente',
  statut: 'EN_COURS',
  profession_requise: 'IDE',
  service: null,
  debut_le: '2026-07-06T08:00:00',
  fin_le: '2026-08-31T16:00:00',
  est_urgente: false,
  etablissement_id: 'etablissement-1',
  soignant_assigne_id: 'soignant-1',
  nb_creneaux: 2,
};

describe('AdminPlanningGlobal', () => {
  let missionsData: unknown[];
  let creneauxData: unknown[];
  let erreurMissions: { message: string } | null;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 6, 31, 12));
    mocks.from.mockReset();
    mocks.toastError.mockReset();
    mocks.chargerCreneaux.mockReset();
    erreurMissions = null;
    missionsData = [missionLongue];
    creneauxData = [
      {
        id: 'creneau-30-juillet',
        mission_id: missionLongue.id,
        debut: '2026-07-30T08:00:00',
        fin: '2026-07-30T16:00:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
      {
        id: 'creneau-31-aout',
        mission_id: missionLongue.id,
        debut: '2026-08-31T08:00:00',
        fin: '2026-08-31T16:00:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
    ];
    mocks.chargerCreneaux.mockImplementation(async () => creneauxData);

    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({ data: erreurMissions ? null : missionsData, error: erreurMissions });
      }
      if (table === 'etablissements') {
        return creerBuilder({
          data: [{ id: 'etablissement-1', nom: 'Établissement test', adresse_ville: 'Paris' }],
          error: null,
        });
      }
      if (table === 'soignants') {
        return creerBuilder({
          data: [{ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre' }],
          error: null,
        });
      }
      return creerBuilder({ data: [], error: null });
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  function rendreEtCharger() {
    render(
      <MemoryRouter>
        <AdminPlanningGlobal />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Charger' }));
  }

  it('affiche une mission longue uniquement au jour de son créneau dans la période', async () => {
    rendreEtCharger();

    expect(await screen.findByText('jeudi 30 juillet 2026')).toBeInTheDocument();
    expect(screen.getByText('08:00 → 16:00')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getAllByText(missionLongue.intitule)).toHaveLength(1);
    expect(screen.queryByText(/31 août/)).not.toBeInTheDocument();
    expect(mocks.chargerCreneaux).toHaveBeenCalledWith(
      ['mission-longue'],
      { typeCreneau: 'PREVISIONNEL', exclurePauses: true },
    );
  });

  it('réutilise la plage globale uniquement pour une ancienne mission ponctuelle de 24 h maximum', async () => {
    missionsData = [
      {
        ...missionLongue,
        id: 'ponctuelle-legacy',
        intitule: 'Mission ponctuelle legacy',
        statut: 'OUVERTE',
        debut_le: '2026-07-31T09:00:00',
        fin_le: '2026-07-31T17:00:00',
        soignant_assigne_id: null,
        nb_creneaux: null,
      },
    ];
    creneauxData = [];

    rendreEtCharger();

    expect(await screen.findByText('vendredi 31 juillet 2026')).toBeInTheDocument();
    expect(screen.getAllByText('Mission ponctuelle legacy').length).toBeGreaterThan(0);
    expect(screen.getAllByText('09:00 → 17:00').length).toBeGreaterThan(0);
  });

  it('échoue fermé si un planning paginé reste incomplet par rapport à nb_creneaux', async () => {
    creneauxData = creneauxData.slice(0, 1);

    rendreEtCharger();

    const alerte = await screen.findByRole('alert');
    expect(alerte).toHaveTextContent('Impossible de charger le planning');
    expect(alerte).toHaveTextContent(/planning détaillé.*incomplet/i);
    expect(screen.queryByText('jeudi 30 juillet 2026')).not.toBeInTheDocument();
  });

  it('affiche une erreur explicite et permet de relancer', async () => {
    erreurMissions = { message: 'Base indisponible' };
    rendreEtCharger();

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger le planning');
    expect(screen.getByRole('alert')).toHaveTextContent('Base indisponible');
    expect(screen.queryByText('Aucune mission sur cette période.')).not.toBeInTheDocument();

    erreurMissions = null;
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument());
    expect(await screen.findByText('jeudi 30 juillet 2026')).toBeInTheDocument();
  });
});

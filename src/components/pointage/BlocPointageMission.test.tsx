import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { BlocPointageMission } from './BlocPointageMission';

vi.mock('@/components/pointage/PointageRotatifSoignant', () => ({
  PointageRotatifSoignant: ({ missionId }: { missionId: string }) => (
    <div data-testid={`pointage-${missionId}`} />
  ),
}));

const mission = (creneaux: Array<{
  debut: string;
  fin: string;
  est_pause: boolean;
  type_creneau: string;
}>) => ({
  id: 'mission-longue',
  intitule: 'Mission IDE longue',
  debut_le: '2026-07-06T08:00:00+02:00',
  fin_le: '2026-08-31T16:00:00+02:00',
  etablissements: { nom: 'Clinique Jolene' },
  creneaux,
});

afterEach(() => vi.useRealTimers());

describe('BlocPointageMission', () => {
  it('explique le jour sans créneau au lieu de masquer une mission active', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    render(
      <MemoryRouter>
        <BlocPointageMission
          mission={mission([{
            debut: '2026-08-31T08:00:00+02:00',
            fin: '2026-08-31T16:00:00+02:00',
            est_pause: false,
            type_creneau: 'PREVISIONNEL',
          }])}
          contrat={{ id: 'contrat', statut: 'SIGNE_COMPLET' }}
          consentementGPS={false}
        />
      </MemoryRouter>,
    );

    expect(screen.getByText(/Aucun créneau à pointer aujourd’hui/i)).toBeInTheDocument();
    expect(screen.getByText(/Prochain créneau le lundi 31 août à 08h00/i)).toBeInTheDocument();
    expect(screen.queryByTestId('pointage-mission-longue')).not.toBeInTheDocument();
  });

  it('affiche le pointage pendant un créneau lorsque le contrat est signé', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    render(
      <MemoryRouter>
        <BlocPointageMission
          mission={mission([{
            debut: '2026-07-31T08:00:00+02:00',
            fin: '2026-07-31T16:00:00+02:00',
            est_pause: false,
            type_creneau: 'PREVISIONNEL',
          }])}
          contrat={{ id: 'contrat', statut: 'SIGNE_COMPLET' }}
          consentementGPS={false}
        />
      </MemoryRouter>,
    );

    expect(screen.getByTestId('pointage-mission-longue')).toBeInTheDocument();
  });

  it('conserve le pointage des missions ponctuelles legacy sans ligne PREVISIONNEL', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    render(
      <MemoryRouter>
        <BlocPointageMission
          mission={{
            ...mission([]),
            debut_le: '2026-07-31T08:00:00+02:00',
            fin_le: '2026-07-31T16:00:00+02:00',
          }}
          contrat={{ id: 'contrat', statut: 'SIGNE_COMPLET' }}
          consentementGPS={false}
        />
      </MemoryRouter>,
    );

    expect(screen.getByTestId('pointage-mission-longue')).toBeInTheDocument();
  });

  it('explique séparément le contrat non signé', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));

    render(
      <MemoryRouter>
        <BlocPointageMission
          mission={mission([{
            debut: '2026-07-31T08:00:00+02:00',
            fin: '2026-07-31T16:00:00+02:00',
            est_pause: false,
            type_creneau: 'PREVISIONNEL',
          }])}
          consentementGPS={false}
        />
      </MemoryRouter>,
    );

    expect(screen.getByText(/Contrat non signé/i)).toBeInTheDocument();
    expect(screen.queryByTestId('pointage-mission-longue')).not.toBeInTheDocument();
  });
});

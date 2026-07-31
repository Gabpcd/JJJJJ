import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { CarteMission } from './CarteMission';

vi.mock('react-router-dom', async (importOriginal) => {
  const original = await importOriginal<typeof import('react-router-dom')>();
  return { ...original, useNavigate: () => vi.fn() };
});

const missionLongue = {
  id: 'mission-longue',
  intitule: 'Mission IDE longue',
  description: null,
  service: 'Soins continus',
  profession_requise: 'IDE',
  debut_le: '2026-07-06T08:00:00',
  fin_le: '2026-08-31T16:00:00',
  duree_heures: 80,
  taux_horaire_base: 25,
  statut: 'EN_COURS',
  est_urgente: false,
  soignants: null,
  creneaux: [
    {
      id: 'creneau-1',
      debut: '2026-07-06T08:00:00',
      fin: '2026-07-06T16:00:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    },
    {
      id: 'creneau-2',
      debut: '2026-08-31T09:00:00',
      fin: '2026-08-31T17:00:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    },
  ],
};

describe('CarteMission — planning établissement', () => {
  it('distingue la période active et affiche les créneaux exacts sans moyenne heures/jour', () => {
    render(<CarteMission mission={missionLongue} />);

    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText(/Période active : 6 juil\. → 31 août 2026/i)).toBeInTheDocument();
    expect(screen.getByText(/lun\. 6 juil\. · 08:00–16:00 \(8 h\)/i)).toBeInTheDocument();
    expect(screen.getByText(/lun\. 31 août · 09:00–17:00 \(8 h\)/i)).toBeInTheDocument();
    expect(screen.getByText('2 créneaux · 16 h planifiées')).toBeInTheDocument();
    expect(screen.queryByText(/h\/jour/i)).not.toBeInTheDocument();
  });

  it('n’étale pas une mission longue sans planning détaillé sur toute sa période', () => {
    render(<CarteMission mission={{ ...missionLongue, creneaux: [] }} />);

    expect(screen.getByText('Planning détaillé à confirmer')).toBeInTheDocument();
    expect(screen.queryByText(/h\/jour/i)).not.toBeInTheDocument();
  });
});

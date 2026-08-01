import { fireEvent, render, screen } from '@testing-library/react';
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

  it('affiche les instants absolus dans le fuseau métier Europe/Paris', () => {
    render(<CarteMission mission={{
      ...missionLongue,
      debut_le: '2026-07-06T06:00:00.000Z',
      fin_le: '2026-08-31T14:00:00.000Z',
      creneaux: [{
        id: 'creneau-paris',
        debut: '2026-07-06T06:00:00.000Z',
        fin: '2026-07-06T14:00:00.000Z',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      }],
    }} />);

    expect(screen.getByText(/lun\. 6 juil\. · 08:00–16:00 \(8 h\)/i)).toBeInTheDocument();
  });

  it('convertit les dates de republication depuis l’heure de Paris', () => {
    const onRepublier = vi.fn();
    render(<CarteMission
      mission={{ ...missionLongue, statut: 'TERMINEE', creneaux: [missionLongue.creneaux[0]] }}
      onRepublier={onRepublier}
    />);

    fireEvent.click(screen.getByRole('button', { name: 'Republier cette mission' }));
    fireEvent.change(screen.getByLabelText('Nouvelle date et heure de début *'), {
      target: { value: '2026-08-31T08:00' },
    });
    fireEvent.change(screen.getByLabelText('Nouvelle date et heure de fin *'), {
      target: { value: '2026-08-31T16:00' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Republier' }));

    expect(onRepublier).toHaveBeenCalledWith(
      expect.objectContaining({ id: missionLongue.id }),
      {
        debut: '2026-08-31T06:00:00.000Z',
        fin: '2026-08-31T14:00:00.000Z',
      },
    );
  });

  it("refuse explicitement une heure de republication inexistante sans faire tomber le rendu", () => {
    const onRepublier = vi.fn();
    render(<CarteMission
      mission={{ ...missionLongue, statut: 'TERMINEE', creneaux: [missionLongue.creneaux[0]] }}
      onRepublier={onRepublier}
    />);

    fireEvent.click(screen.getByRole('button', { name: 'Republier cette mission' }));
    fireEvent.change(screen.getByLabelText('Nouvelle date et heure de début *'), {
      target: { value: '2026-03-29T02:30' },
    });
    fireEvent.change(screen.getByLabelText('Nouvelle date et heure de fin *'), {
      target: { value: '2026-03-29T05:00' },
    });

    expect(screen.getByRole('alert')).toHaveTextContent(/n’existent pas à Paris/i);
    expect(screen.getByRole('button', { name: 'Republier' })).toBeDisabled();
    expect(onRepublier).not.toHaveBeenCalled();
  });

  it('ne remplace jamais un planning multi-creneaux par une enveloppe de republication', () => {
    const onRepublier = vi.fn();
    render(<CarteMission
      mission={{ ...missionLongue, statut: 'TERMINEE' }}
      onRepublier={onRepublier}
    />);

    fireEvent.click(screen.getByRole('button', { name: 'Republier cette mission' }));
    expect(screen.queryByLabelText('Nouvelle date et heure de début *')).not.toBeInTheDocument();
    expect(screen.getByText(/planning exact sera repris dans le formulaire/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Republier' }));

    expect(onRepublier).toHaveBeenCalledWith(expect.objectContaining({ id: missionLongue.id }));
    expect(onRepublier).not.toHaveBeenCalledWith(expect.anything(), expect.anything());
  });
});

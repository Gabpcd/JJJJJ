import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { CarteSerie } from './CarteSerie';

const navigate = vi.fn();

vi.mock('react-router-dom', () => ({
  useNavigate: () => navigate,
}));

describe('CarteSerie — établissement legacy', () => {
  beforeEach(() => navigate.mockReset());

  it('affiche les créneaux distincts en heure de Paris et ouvre une mission', () => {
    render(
      <CarteSerie
        role="etablissement"
        missions={[
          {
            id: 'mission-1',
            intitule: 'Série IDE',
            description: '[SERIE_ID:SERIE_1760000000000_abcd]',
            debut_le: '2026-07-30T18:00:00Z',
            fin_le: '2026-07-31T04:00:00Z',
            statut: 'OUVERTE',
            nb_creneaux: 1,
            taux_horaire_base: 25,
            creneaux: [{ id: 'c1', debut: '2026-07-30T18:00:00Z', fin: '2026-07-31T04:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' }],
          },
          {
            id: 'mission-2',
            intitule: 'Série IDE',
            description: '[SERIE_ID:SERIE_1760000000000_abcd]',
            debut_le: '2026-08-02T06:00:00Z',
            fin_le: '2026-08-02T14:00:00Z',
            statut: 'OUVERTE',
            nb_creneaux: 1,
            taux_horaire_base: 30,
            creneaux: [{ id: 'c2', debut: '2026-08-02T06:00:00Z', fin: '2026-08-02T14:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' }],
          },
        ]}
      />,
    );

    expect(screen.getByText('2 créneaux planifiés')).toBeInTheDocument();
    expect(screen.getByText(/jeu\. 30 juil\. · 20:00 → ven\. 31 juil\. · 06:00/)).toBeInTheDocument();
    expect(screen.getByText(/dim\. 2 août · 08:00 → 16:00/)).toBeInTheDocument();
    expect(screen.getByText(/Tarifs variables/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Ouvrir une mission de la série/i }));
    expect(navigate).toHaveBeenCalledWith('/etablissement/missions/mission-1');
  });

  it('montre aussi le planning exact au soignant et refuse un compte partiel', () => {
    const mission = {
      id: 'mission-soignant',
      intitule: 'Série IDE',
      description: '[SERIE_ID:SERIE_1760000000000_abcd]',
      debut_le: '2026-08-03T06:00:00Z',
      fin_le: '2026-08-04T14:00:00Z',
      statut: 'OUVERTE',
      taux_horaire_base: 25,
      nb_creneaux: 2,
      creneaux: [
        { id: 'c1', debut: '2026-08-03T06:00:00Z', fin: '2026-08-03T14:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' },
        { id: 'c2', debut: '2026-08-04T06:00:00Z', fin: '2026-08-04T14:00:00Z', est_pause: false, type_creneau: 'PREVISIONNEL' },
      ],
    };
    const { rerender } = render(<CarteSerie role="soignant" missions={[mission]} />);

    expect(screen.getByText('2 créneaux planifiés')).toBeInTheDocument();
    expect(screen.getByText(/lun\. 3 août · 08:00 → 16:00/)).toBeInTheDocument();
    expect(screen.getByText(/mar\. 4 août · 08:00 → 16:00/)).toBeInTheDocument();

    rerender(<CarteSerie role="soignant" missions={[{ ...mission, creneaux: mission.creneaux.slice(0, 1) }]} />);
    expect(screen.getByText('Planning détaillé à confirmer.')).toBeInTheDocument();
    expect(screen.queryByText('1 créneau planifié')).not.toBeInTheDocument();
  });
});

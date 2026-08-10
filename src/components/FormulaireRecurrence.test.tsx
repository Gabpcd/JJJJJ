import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { FormulaireRecurrence, type RecurrenceFlexConfig } from './FormulaireRecurrence';

describe('FormulaireRecurrence — planning exact établissement', () => {
  it("n'affiche pas d'erreur avant la première saisie de dates", () => {
    render(<FormulaireRecurrence onChange={vi.fn()} />);

    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(screen.queryByText('Choisissez une période valide.')).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/Première date affichée/i), {
      target: { value: '2026-08-10' },
    });
    expect(screen.getByRole('alert')).toHaveTextContent('Choisissez une période valide.');
  });

  it('préremplit les créneaux réels, y compris une garde finissant le lendemain', async () => {
    const onChange = vi.fn();
    render(
      <FormulaireRecurrence
        onChange={onChange}
        initialCreneaux={[
          {
            id: 'nuit-1',
            debut: '2026-08-02T18:00:00.000Z',
            fin: '2026-08-03T06:00:00.000Z',
          },
        ]}
      />,
    );

    expect(screen.getByLabelText('Début du créneau 1 du 2026-08-02')).toHaveValue('20:00');
    expect(screen.getByLabelText('Fin du créneau 1 du 2026-08-02')).toHaveValue('08:00');
    expect(screen.getByLabelText('Date de fin du créneau 1 du 2026-08-02')).toHaveValue('LENDEMAIN');
    expect(screen.getAllByText('dimanche 2 août 2026', { exact: false }).length).toBeGreaterThan(0);
    expect(screen.getByText('lundi 3 août 2026', { exact: false })).toBeInTheDocument();

    await waitFor(() => expect(onChange).toHaveBeenCalled());
    const [, creneaux] = onChange.mock.calls.at(-1)!;
    expect(creneaux).toEqual([
      expect.objectContaining({
        id: 'nuit-1',
        debut: '2026-08-02T18:00:00.000Z',
        fin: '2026-08-03T06:00:00.000Z',
        dureeHeures: 12,
      }),
    ]);
  });

  it("ne décale pas un créneau inchangé pendant l'heure répétée d'automne", async () => {
    const onChange = vi.fn();
    render(
      <FormulaireRecurrence
        onChange={onChange}
        initialCreneaux={[
          {
            id: 'heure-repetee',
            debut: '2026-10-25T00:30:00.000Z',
            fin: '2026-10-25T02:30:00.000Z',
          },
        ]}
      />,
    );

    expect(screen.getByLabelText('Début du créneau 1 du 2026-10-25')).toHaveValue('02:30');
    expect(screen.getByLabelText('Fin du créneau 1 du 2026-10-25')).toHaveValue('03:30');

    await waitFor(() => expect(onChange).toHaveBeenCalled());
    const [, creneaux] = onChange.mock.calls.at(-1)!;
    expect(creneaux).toEqual([
      expect.objectContaining({
        id: 'heure-repetee',
        debut: '2026-10-25T00:30:00.000Z',
        fin: '2026-10-25T02:30:00.000Z',
        dureeHeures: 2,
      }),
    ]);
  });

  it('permet plusieurs créneaux sur une date sans modifier les autres dates', async () => {
    const onChange = vi.fn();
    render(
      <FormulaireRecurrence
        onChange={onChange}
        initialDateDebut="2026-08-03"
        initialDateFin="2026-08-05"
      />,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Toutes les dates' }));
    const mardi = await screen.findByTestId('jour-planning-2026-08-04');
    fireEvent.click(within(mardi).getByRole('button', { name: 'Ajouter un créneau ce jour' }));
    expect(within(mardi).getAllByLabelText(/Début du créneau/)).toHaveLength(2);

    fireEvent.click(screen.getByLabelText('lundi 3 août 2026 travaillé'));
    await waitFor(() => {
      const [config] = onChange.mock.calls.at(-1)! as [RecurrenceFlexConfig];
      expect(config.jours.find((jour) => jour.date === '2026-08-03')?.actif).toBe(false);
      expect(config.jours.find((jour) => jour.date === '2026-08-04')?.creneaux).toHaveLength(2);
      expect(config.jours.find((jour) => jour.date === '2026-08-05')?.actif).toBe(true);
    });
  });

  it('une exception sur un mercredi ne désactive pas le mercredi suivant', async () => {
    const onChange = vi.fn();
    render(
      <FormulaireRecurrence
        onChange={onChange}
        initialDateDebut="2026-08-05"
        initialDateFin="2026-08-12"
      />,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Toutes les dates' }));
    fireEvent.click(await screen.findByLabelText('mercredi 5 août 2026 travaillé'));
    await waitFor(() => {
      const [config] = onChange.mock.calls.at(-1)! as [RecurrenceFlexConfig];
      expect(config.jours.find((jour) => jour.date === '2026-08-05')?.actif).toBe(false);
      expect(config.jours.find((jour) => jour.date === '2026-08-12')?.actif).toBe(true);
    });
  });
});

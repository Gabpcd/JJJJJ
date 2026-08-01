import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  construireOccurrencesPlanning,
  finFenetrePlanningParis,
  SectionPlanning,
  type CreneauPlanning,
  type MissionPlanningSource,
} from './SectionPlanning';

const missionLongue: MissionPlanningSource = {
  id: 'mission-longue',
  intitule: 'Mission IDE — médecine polyvalente',
  debut_le: '2026-07-06T08:00:00',
  fin_le: '2026-08-31T16:00:00',
  statut: 'EN_COURS',
  duree_heures: 16,
  soignant_assigne_id: 'soignant-1',
  soignant_nom: 'Marie Lefèvre',
};

const creneauxLongs: CreneauPlanning[] = [
  {
    id: 'creneau-6-juillet',
    mission_id: missionLongue.id,
    debut: '2026-07-06T08:00:00',
    fin: '2026-07-06T16:00:00',
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

describe('planning établissement par créneaux', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 6, 31, 16));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('aplatit une mission longue uniquement sur ses deux jours réellement travaillés', () => {
    const occurrences = construireOccurrencesPlanning(
      [missionLongue],
      creneauxLongs,
      new Date(2026, 6, 1),
      new Date(2026, 8, 1),
    );

    expect(occurrences).toHaveLength(2);
    expect(occurrences.map((occurrence) => occurrence.creneau_debut)).toEqual([
      '2026-07-06T08:00:00',
      '2026-08-31T08:00:00',
    ]);
    expect(occurrences.map((occurrence) => occurrence.duree_creneau_heures)).toEqual([8, 8]);
  });

  it('ne conserve que le prochain créneau au 31 août depuis le 31 juillet', () => {
    const debutFenetre = new Date('2026-07-31T16:00:00+02:00');
    const finFenetre = finFenetrePlanningParis(debutFenetre);
    expect(finFenetre.toISOString()).toBe('2026-08-31T21:59:59.999Z');

    const occurrences = construireOccurrencesPlanning(
      [missionLongue],
      creneauxLongs,
      debutFenetre,
      finFenetre,
    );

    expect(occurrences).toHaveLength(1);
    expect(occurrences[0].creneau_debut).toBe('2026-08-31T08:00:00');

    render(
      <MemoryRouter>
        <SectionPlanning missions={occurrences} />
      </MemoryRouter>,
    );

    expect(screen.getByText('(1 créneau)')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText(/31 août · 08:00 → 16:00 · 8h/)).toBeInTheDocument();
  });

  it('utilise le repli global seulement pour une ancienne mission ponctuelle de 24 h maximum', () => {
    const ponctuelle: MissionPlanningSource = {
      ...missionLongue,
      id: 'mission-ponctuelle',
      debut_le: '2026-08-02T08:00:00',
      fin_le: '2026-08-02T16:00:00',
      duree_heures: 8,
    };
    const longueSansPlanning: MissionPlanningSource = {
      ...missionLongue,
      id: 'mission-longue-sans-planning',
    };

    const occurrences = construireOccurrencesPlanning(
      [ponctuelle, longueSansPlanning],
      [],
      new Date(2026, 6, 31),
      new Date(2026, 7, 31, 23, 59, 59),
    );

    expect(occurrences).toHaveLength(1);
    expect(occurrences[0].id).toBe('mission-ponctuelle');
    expect(occurrences[0].duree_creneau_heures).toBe(8);
  });

  it('affiche une garde de nuit sur ses deux jours civils Paris sans dupliquer la liste', () => {
    const gardeDeNuit = construireOccurrencesPlanning(
      [{
        ...missionLongue,
        id: 'mission-nuit',
        intitule: 'Garde de nuit',
        debut_le: '2026-07-30T20:00:00+02:00',
        fin_le: '2026-07-31T06:00:00+02:00',
        duree_heures: 10,
      }],
      [{
        id: 'creneau-nuit',
        mission_id: 'mission-nuit',
        debut: '2026-07-30T20:00:00+02:00',
        fin: '2026-07-31T06:00:00+02:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      }],
      new Date('2026-07-01T00:00:00+02:00'),
      new Date('2026-08-01T00:00:00+02:00'),
    );

    render(
      <MemoryRouter>
        <SectionPlanning missions={gardeDeNuit} />
      </MemoryRouter>,
    );

    fireEvent.mouseDown(screen.getByRole('tab', { name: 'Mois' }), { button: 0 });
    expect(screen.getByRole('button', { name: '20:00 Garde de nuit' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '00:00 Garde de nuit' })).toBeInTheDocument();

    fireEvent.mouseDown(screen.getByRole('tab', { name: 'Semaine' }), { button: 0 });
    expect(screen.getByRole('button', { name: /Garde de nuit 20:00 → 00:00/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Garde de nuit 00:00 → 06:00/ })).toBeInTheDocument();

    fireEvent.mouseDown(screen.getByRole('tab', { name: 'Liste' }), { button: 0 });
    expect(screen.getAllByRole('button', { name: /Garde de nuit/ })).toHaveLength(1);
    expect(screen.getByText(/jeu\. 30 juil\. · 20:00 → ven\. 31 juil\. · 06:00 \(lendemain\) · 10h/)).toBeInTheDocument();
  });

  it('garde visible une mission sans créneau prévisionnel et la signale à confirmer', () => {
    render(
      <MemoryRouter>
        <SectionPlanning missions={[]} missionsSansPlanning={[missionLongue]} />
      </MemoryRouter>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('Planning détaillé à confirmer');
    expect(screen.getByRole('button', { name: /Mission IDE — médecine polyvalente/i })).toBeInTheDocument();
    expect(screen.queryByText('Aucun créneau planifié dans les 31 prochains jours.')).not.toBeInTheDocument();
  });

  it('borne la navigation aux 31 jours réellement chargés', () => {
    const debutFenetre = new Date('2026-07-31T16:00:00+02:00');
    const finFenetre = finFenetrePlanningParis(debutFenetre);
    const occurrences = construireOccurrencesPlanning(
      [missionLongue],
      creneauxLongs,
      debutFenetre,
      finFenetre,
    );

    render(
      <MemoryRouter>
        <SectionPlanning
          missions={occurrences}
          debutFenetre={debutFenetre}
          finFenetre={finFenetre}
        />
      </MemoryRouter>,
    );

    fireEvent.mouseDown(screen.getByRole('tab', { name: 'Mois' }), { button: 0 });
    expect(screen.getByRole('button', { name: 'Mois précédent' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Mois suivant' })).not.toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: 'Mois suivant' }));
    expect(screen.getByText('août 2026')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Mois précédent' })).not.toBeDisabled();
    expect(screen.getByRole('button', { name: 'Mois suivant' })).toBeDisabled();
  });

  it('affiche une erreur explicite et permet de relancer', () => {
    const onRetry = vi.fn();
    render(
      <MemoryRouter>
        <SectionPlanning
          missions={[]}
          erreur="Le planning n'a pas pu être chargé."
          onRetry={onRetry}
        />
      </MemoryRouter>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent("Le planning n'a pas pu être chargé.");
    expect(screen.queryByText(/Aucun créneau planifié/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/ }));
    expect(onRetry).toHaveBeenCalledOnce();
  });
});

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { PlanningMissionCandidat } from './PlanningMissionCandidat';
import { RecapitulatifCandidatureDialog } from './RecapitulatifCandidatureDialog';
import {
  construirePlanningCandidat,
  construirePlanningConformite,
  planningCorrespondAuFiltre,
  trouverChevauchementPlannings,
  trouverReposInsuffisant,
  type CreneauMissionCandidat,
  type MissionPlanningCandidat,
} from './planning-candidat';

const missionLongue: MissionPlanningCandidat & { intitule: string } = {
  id: 'mission-longue',
  intitule: 'Mission deux journées',
  debut_le: '2026-07-06T08:00:00+02:00',
  fin_le: '2026-08-31T16:00:00+02:00',
  nb_creneaux: 2,
};

const deuxCreneaux: CreneauMissionCandidat[] = [
  {
    id: 'jour-1',
    mission_id: 'mission-longue',
    debut: '2026-07-06T08:00:00+02:00',
    fin: '2026-07-06T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
  {
    id: 'jour-2',
    mission_id: 'mission-longue',
    debut: '2026-08-31T08:00:00+02:00',
    fin: '2026-08-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
];

describe('planning candidat exact', () => {
  it('affiche chaque journée éloignée, le total et exclut explicitement les jours non listés', () => {
    render(<PlanningMissionCandidat mission={{ ...missionLongue, creneaux_planifies: deuxCreneaux }} />);

    expect(screen.getByText('2 créneaux')).toBeInTheDocument();
    expect(screen.getByText('16 h au total')).toBeInTheDocument();
    expect(screen.getByText(/lundi 6 juillet 2026/i)).toBeInTheDocument();
    expect(screen.getByText(/lundi 31 août 2026/i)).toBeInTheDocument();
    expect(screen.getByText(/Les autres jours de la période ne sont pas travaillés/i)).toBeInTheDocument();
  });

  it('affiche la date de fin et « lendemain » pour un créneau de nuit', () => {
    render(<PlanningMissionCandidat mission={{
      id: 'nuit',
      debut_le: '2026-07-06T20:00:00+02:00',
      fin_le: '2026-07-07T08:00:00+02:00',
      nb_creneaux: 1,
      creneaux_planifies: [{
        debut: '2026-07-06T20:00:00+02:00',
        fin: '2026-07-07T08:00:00+02:00',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      }],
    }} />);

    expect(screen.getByText(/mardi 7 juillet 2026 · 08h00 \(lendemain\)/i)).toBeInTheDocument();
  });

  it('bloque un planning multi-créneaux incomplet', () => {
    const planning = construirePlanningCandidat(missionLongue, deuxCreneaux.slice(0, 1));

    expect(planning.exact).toBe(false);
    expect(planning.messageBlocage).toMatch(/candidature est bloquée/i);
  });

  it('bloque aussi un planning dont le nombre de créneaux dépasse le compteur annoncé', () => {
    const planning = construirePlanningCandidat(
      { ...missionLongue, nb_creneaux: 1 },
      deuxCreneaux,
    );

    expect(planning.exact).toBe(false);
    expect(planning.messageBlocage).toMatch(/candidature est bloquée/i);
  });

  it('conserve le repli contractuel d’une mission ponctuelle de moins de 24 h', () => {
    const planning = construirePlanningCandidat({
      id: 'ponctuelle',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-07-06T16:00:00+02:00',
      nb_creneaux: 1,
    });

    expect(planning.exact).toBe(true);
    expect(planning.creneaux).toHaveLength(1);
    expect(planning.totalHeures).toBe(8);
  });

  it('applique les filtres jour, nuit et week-end aux créneaux exacts', () => {
    const mission = {
      ...missionLongue,
      creneaux_planifies: [
        {
          debut: '2026-07-11T21:00:00+02:00',
          fin: '2026-07-12T07:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        deuxCreneaux[1],
      ],
    };

    expect(planningCorrespondAuFiltre(mission, 'NUIT')).toBe(true);
    expect(planningCorrespondAuFiltre(mission, 'JOUR')).toBe(true);
    expect(planningCorrespondAuFiltre(mission, 'WEEKEND')).toBe(true);
  });

  it('compare les vrais créneaux sans confondre leur enveloppe globale', () => {
    const cible = construirePlanningCandidat(missionLongue, deuxCreneaux);
    const entreLesDeux = construirePlanningCandidat({
      id: 'entre-deux',
      debut_le: '2026-07-20T08:00:00+02:00',
      fin_le: '2026-07-20T16:00:00+02:00',
      nb_creneaux: 1,
    });
    const reposCourt = construirePlanningCandidat({
      id: 'repos-court',
      debut_le: '2026-07-05T23:00:00+02:00',
      fin_le: '2026-07-05T23:30:00+02:00',
      nb_creneaux: 1,
    });

    expect(trouverChevauchementPlannings(cible, entreLesDeux)).toBeNull();
    expect(trouverReposInsuffisant(cible, reposCourt)?.heures).toBe(8.5);
  });

  it('utilise les heures EFFECTIF d’une mission terminée pour la conformité', () => {
    const planning = construirePlanningConformite(
      { ...missionLongue, statut: 'TERMINEE' },
      [
        ...deuxCreneaux,
        {
          id: 'effectif-1',
          mission_id: 'mission-longue',
          debut: '2026-08-31T09:00:00+02:00',
          fin: '2026-08-31T18:00:00+02:00',
          est_pause: false,
          type_creneau: 'EFFECTIF',
        },
      ],
    );

    expect(planning.exact).toBe(true);
    expect(planning.creneaux).toHaveLength(1);
    expect(planning.creneaux[0].debut).toBe('2026-08-31T09:00:00+02:00');
    expect(planning.totalHeures).toBe(9);
  });
});

describe('récapitulatif candidature', () => {
  it('désactive la confirmation si le planning détaillé est incomplet', () => {
    render(<RecapitulatifCandidatureDialog
      mission={{ ...missionLongue, creneaux_planifies: deuxCreneaux.slice(0, 1) }}
      ouvert
      onFermer={vi.fn()}
      onConfirmer={vi.fn()}
    />);

    expect(screen.getByRole('button', { name: 'Envoyer ma candidature' })).toBeDisabled();
  });

  it('confirme uniquement après avoir affiché tous les créneaux exacts', () => {
    const onConfirmer = vi.fn();
    render(<RecapitulatifCandidatureDialog
      mission={{ ...missionLongue, creneaux_planifies: deuxCreneaux }}
      ouvert
      onFermer={vi.fn()}
      onConfirmer={onConfirmer}
    />);

    fireEvent.click(screen.getByRole('button', { name: 'Envoyer ma candidature' }));
    expect(onConfirmer).toHaveBeenCalledTimes(1);
  });
});

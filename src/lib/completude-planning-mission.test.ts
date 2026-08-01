import { describe, expect, it } from 'vitest';
import { analyserCompletudePlanningMission } from './completude-planning-mission';

const missionLongue = {
  id: 'mission-1',
  debut_le: '2026-07-06T08:00:00+02:00',
  fin_le: '2026-08-31T16:00:00+02:00',
  nb_creneaux: 2,
};

const creneauxExacts = [
  {
    id: 'creneau-1',
    debut: '2026-07-06T08:00:00+02:00',
    fin: '2026-07-06T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
  {
    id: 'creneau-2',
    debut: '2026-08-31T08:00:00+02:00',
    fin: '2026-08-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
];

describe('analyserCompletudePlanningMission', () => {
  it('accepte uniquement le nombre exact de créneaux valides', () => {
    const resultat = analyserCompletudePlanningMission(missionLongue, creneauxExacts);

    expect(resultat.complet).toBe(true);
    expect(resultat.nombrePlanifie).toBe(2);
    expect(resultat.dureeTotaleHeures).toBe(16);
  });

  it('échoue fermé lorsque la réponse est tronquée par rapport au count attendu', () => {
    const resultat = analyserCompletudePlanningMission(missionLongue, creneauxExacts.slice(0, 1));

    expect(resultat.complet).toBe(false);
    expect(resultat.creneauxPlanifies).toEqual([]);
  });

  it('échoue fermé lorsqu’un créneau est invalide', () => {
    const resultat = analyserCompletudePlanningMission(
      { ...missionLongue, nb_creneaux: 1 },
      [{ ...creneauxExacts[0], fin: '2026-07-06T07:59:00+02:00' }],
    );

    expect(resultat.complet).toBe(false);
    expect(resultat.nombrePlanifie).toBe(0);
  });

  it('conserve le repli legacy pour une mission ponctuelle de 24 h maximum', () => {
    const resultat = analyserCompletudePlanningMission({
      id: 'mission-legacy',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-07-06T16:00:00+02:00',
      nb_creneaux: null,
    });

    expect(resultat.complet).toBe(true);
    expect(resultat.nombrePlanifie).toBe(1);
    expect(resultat.dureeTotaleHeures).toBe(8);
  });

  it('n’invente aucun planning pour une mission longue legacy', () => {
    const resultat = analyserCompletudePlanningMission({
      id: 'mission-longue-legacy',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
      nb_creneaux: null,
    });

    expect(resultat.complet).toBe(false);
    expect(resultat.creneauxPlanifies).toEqual([]);
  });
});

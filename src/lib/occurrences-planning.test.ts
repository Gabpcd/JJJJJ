import { describe, expect, it } from 'vitest';
import {
  construireOccurrencesPlanning,
  decouperOccurrencesParJour,
  missionsLonguesSansPlanning,
} from './occurrences-planning';

const missionLongue = {
  id: 'mission-longue',
  intitule: 'Mission longue',
  debut_le: '2026-07-06T06:00:00.000Z',
  fin_le: '2026-08-31T14:00:00.000Z',
  duree_heures: 16,
};

describe('construireOccurrencesPlanning', () => {
  it('affiche une mission longue uniquement sur ses deux créneaux réels', () => {
    const occurrences = construireOccurrencesPlanning([missionLongue], [
      {
        id: 'juillet',
        mission_id: missionLongue.id,
        debut: '2026-07-06T06:00:00.000Z',
        fin: '2026-07-06T14:00:00.000Z',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
      {
        id: 'aout',
        mission_id: missionLongue.id,
        debut: '2026-08-31T06:00:00.000Z',
        fin: '2026-08-31T14:00:00.000Z',
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      },
    ]);

    expect(occurrences).toHaveLength(2);
    expect(occurrences.map((occurrence) => occurrence.debut_le)).toEqual([
      '2026-07-06T06:00:00.000Z',
      '2026-08-31T06:00:00.000Z',
    ]);
    expect(occurrences.map((occurrence) => occurrence.duree_heures)).toEqual([8, 8]);
  });

  it("conserve le repli global d'une ancienne mission ponctuelle", () => {
    const occurrences = construireOccurrencesPlanning([{
      id: 'ponctuelle',
      debut_le: '2026-07-31T06:00:00.000Z',
      fin_le: '2026-07-31T14:00:00.000Z',
      duree_heures: 8,
    }], []);

    expect(occurrences).toHaveLength(1);
    expect(occurrences[0].duree_heures).toBe(8);
  });

  it("n'étale jamais une mission longue sans planning", () => {
    expect(construireOccurrencesPlanning([missionLongue], [])).toEqual([]);
    expect(missionsLonguesSansPlanning([missionLongue], [])).toEqual([missionLongue]);
  });

  it('répartit une garde de nuit sur les deux jours civils', () => {
    const [occurrence] = construireOccurrencesPlanning([{
      id: 'nuit',
      debut_le: '2026-08-02T20:00:00+02:00',
      fin_le: '2026-08-03T06:00:00+02:00',
    }], []);

    const segments = decouperOccurrencesParJour([occurrence]);

    expect(segments).toHaveLength(2);
    expect(segments.map((segment) => segment.duree_heures)).toEqual([4, 6]);
    expect(segments.reduce((total, segment) => total + segment.duree_heures, 0)).toBe(10);
  });
});

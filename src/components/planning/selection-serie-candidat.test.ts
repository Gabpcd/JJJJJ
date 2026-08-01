import { describe, expect, it } from 'vitest';
import { analyserSelectionSerie, type MissionSerieCandidat } from './selection-serie-candidat';

function mission(id: string): MissionSerieCandidat {
  return {
    id,
    debut_le: `2026-08-0${id}T08:00:00+02:00`,
    fin_le: `2026-08-0${id}T16:00:00+02:00`,
    nb_creneaux: 1,
    creneaux_planifies: [{
      id: `c-${id}`,
      debut: `2026-08-0${id}T08:00:00+02:00`,
      fin: `2026-08-0${id}T16:00:00+02:00`,
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }],
  };
}

describe('analyserSelectionSerie', () => {
  const missions = Array.from({ length: 7 }, (_, index) => mission(String(index + 1)));

  it('ne retire jamais silencieusement une mission conflictuelle', () => {
    const resultat = analyserSelectionSerie(
      missions,
      new Set(missions.map((item) => item.id)),
      new Set(['7']),
    );

    expect(resultat.missionsSelectionnees).toHaveLength(7);
    expect(resultat.idsEnConflit).toEqual(['7']);
    expect(resultat.peutAccepter).toBe(false);
  });

  it('autorise le sous-ensemble de six créneaux après décochage du septième', () => {
    const resultat = analyserSelectionSerie(
      missions,
      new Set(missions.slice(0, 6).map((item) => item.id)),
      new Set(),
    );

    expect(resultat.missionsSelectionnees.map((item) => item.id)).toEqual(['1', '2', '3', '4', '5', '6']);
    expect(resultat.peutAccepter).toBe(true);
  });

  it('bloque une sélection dont un planning exact est absent', () => {
    const resultat = analyserSelectionSerie(
      [{ ...mission('1'), nb_creneaux: 2 }],
      new Set(['1']),
      new Set(),
    );

    expect(resultat.idsPlanningInexact).toEqual(['1']);
    expect(resultat.peutAccepter).toBe(false);
  });
});

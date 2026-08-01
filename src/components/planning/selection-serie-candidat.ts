import {
  construirePlanningCandidat,
  type MissionPlanningCandidat,
} from './planning-candidat';

export interface MissionSerieCandidat extends MissionPlanningCandidat {
  id: string;
}
export interface AnalyseSelectionSerie<T extends MissionSerieCandidat> {
  missionsSelectionnees: T[];
  idsEnConflit: string[];
  idsPlanningInexact: string[];
  peutAccepter: boolean;
}

/**
 * Analyse la sélection sans jamais retirer silencieusement une mission.
 * L'interface peut ainsi laisser l'utilisateur décocher le ou les créneaux
 * responsables d'un conflit, puis accepter exactement le sous-ensemble vu.
 */
export function analyserSelectionSerie<T extends MissionSerieCandidat>(
  missionsOuvertes: T[],
  idsSelectionnes: ReadonlySet<string>,
  idsConflit: ReadonlySet<string>,
): AnalyseSelectionSerie<T> {
  const missionsSelectionnees = missionsOuvertes.filter((mission) => idsSelectionnes.has(mission.id));
  const idsEnConflit = missionsSelectionnees
    .filter((mission) => idsConflit.has(mission.id))
    .map((mission) => mission.id);
  const idsPlanningInexact = missionsSelectionnees
    .filter((mission) => !construirePlanningCandidat(mission).exact)
    .map((mission) => mission.id);

  return {
    missionsSelectionnees,
    idsEnConflit,
    idsPlanningInexact,
    peutAccepter: missionsSelectionnees.length > 0
      && idsEnConflit.length === 0
      && idsPlanningInexact.length === 0,
  };
}

import {
  additionnerHeuresSalarieesParSemaine,
  heuresMissionParSemaine,
  planningMissionHebdomadaireDisponible,
  type CreneauMissionPourCalculHebdomadaire,
  type MissionPourCalculHebdomadaire,
} from './heures-hebdomadaires-mission';

export interface SemaineAttestationProposition {
  semaineISO: string;
  heuresJoleneSemaine: number;
}
export type ResultatSemainesAttestation =
  | { ok: true; semaines: SemaineAttestationProposition[] }
  | { ok: false; semaines: []; erreur: string };

function planningDetailleDisponible(
  mission: MissionPourCalculHebdomadaire,
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): boolean {
  const lignesTravail = creneaux.filter((creneau) => (
    creneau.mission_id === mission.id && !creneau.est_pause
  ));
  return lignesTravail.length > 0
    && planningMissionHebdomadaireDisponible(mission, creneaux);
}

/**
 * Calcule les heures Jolene de chacune des semaines réellement touchées par
 * une proposition. Le résultat provient uniquement des créneaux datés ; une
 * enveloppe mission ou une durée globale ne peut pas masquer une semaine.
 */
export function calculerSemainesAttestationProposition(
  missionCandidate: MissionPourCalculHebdomadaire,
  missionsExistantes: MissionPourCalculHebdomadaire[],
  creneaux: CreneauMissionPourCalculHebdomadaire[],
): ResultatSemainesAttestation {
  const missions = [missionCandidate, ...missionsExistantes];
  if (missions.some((mission) => !planningDetailleDisponible(mission, creneaux))) {
    return {
      ok: false,
      semaines: [],
      erreur: 'Le planning exact d’une mission de la période est indisponible.',
    };
  }

  const semainesCandidate = heuresMissionParSemaine(missionCandidate, creneaux);
  if (semainesCandidate.length === 0) {
    return {
      ok: false,
      semaines: [],
      erreur: 'La proposition ne contient aucun créneau vérifiable.',
    };
  }

  const totaux = additionnerHeuresSalarieesParSemaine(missions, creneaux);
  return {
    ok: true,
    semaines: semainesCandidate.map((semaine) => ({
      semaineISO: semaine.cleSemaine,
      heuresJoleneSemaine: totaux.get(semaine.cleSemaine)?.heures ?? 0,
    })),
  };
}

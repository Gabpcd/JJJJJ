import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import {
  ajouterJoursCivilsParis,
  debutJourParis,
  instantDateHeureParis,
  instantJolene,
  partiesDateHeureParis,
} from '@/lib/date-heure-paris';

export interface MissionPlanningCandidat {
  id?: string;
  mission_id?: string;
  debut_le: string | null;
  fin_le: string | null;
  duree_heures?: number | string | null;
  nb_creneaux?: number | null;
  creneaux_planifies?: CreneauPointage[];
  planning_exact?: boolean;
  erreur_planning?: boolean;
  statut?: string | null;
}

export interface CreneauMissionCandidat extends CreneauPointage {
  mission_id?: string;
}

export interface PlanningCandidat {
  creneaux: CreneauPointage[];
  exact: boolean;
  totalHeures: number;
  periodeEtendue: boolean;
  messageBlocage: string | null;
}

export type FiltreHoraireCandidat = 'TOUS' | 'JOUR' | 'NUIT' | 'WEEKEND';

export interface CreneauConfirmeAction {
  debut: string;
  fin: string;
}

function missionId(mission: MissionPlanningCandidat): string | undefined {
  return mission.id ?? mission.mission_id;
}

function chevauchement(
  debutA: number,
  finA: number,
  debutB: number,
  finB: number,
): boolean {
  return debutA < finB && finA > debutB;
}

function instantParisDuJour(
  jour: Date,
  heure: number,
): Date {
  const parties = partiesDateHeureParis(jour);
  return instantDateHeureParis({ ...parties, heure, minute: 0, seconde: 0 });
}

export function construirePlanningCandidat(
  mission: MissionPlanningCandidat,
  creneaux: CreneauMissionCandidat[] = mission.creneaux_planifies ?? [],
  erreur = mission.erreur_planning ?? false,
): PlanningCandidat {
  const tousLesPrevisionnels = creneaux.filter((creneau) => creneau.type_creneau === 'PREVISIONNEL');
  const creneauxTravail = tousLesPrevisionnels.filter((creneau) => !creneau.est_pause);
  const attendus = Number(mission.nb_creneaux ?? 0);
  const debutMission = mission.debut_le;
  const finMission = mission.fin_le;
  const avecRepliPonctuel = attendus <= 1 && debutMission && finMission
    ? ajouterRepliMissionPonctuelle(creneauxTravail, {
        id: missionId(mission),
        debut_le: debutMission,
        fin_le: finMission,
      })
    : creneauxTravail;
  const planifies = creneauxPrevisionnels(avecRepliPonctuel);
  const planningIncomplet = creneauxTravail.some((creneau) => !creneau.fin)
    || (attendus > 0 && attendus !== planifies.length);
  const exact = !erreur && planifies.length > 0 && !planningIncomplet;
  const totalHeures = planifies.reduce((total, creneau) => {
    if (!creneau.fin) return total;
    return total + Math.max(
      0,
      (instantJolene(creneau.fin).getTime() - instantJolene(creneau.debut).getTime()) / 3_600_000,
    );
  }, 0);
  const periodeEtendue = planifies.length > 1 || (
    planifies[0]?.fin
      ? debutJourParis(planifies[0].debut).getTime() !== debutJourParis(planifies[0].fin).getTime()
      : false
  );

  return {
    creneaux: planifies,
    exact,
    totalHeures,
    periodeEtendue,
    messageBlocage: exact
      ? null
      : erreur
        ? 'Le planning détaillé ne peut pas être vérifié. La candidature est bloquée jusqu’à son chargement.'
        : 'Les dates et horaires détaillés ne sont pas tous confirmés. La candidature est bloquée jusqu’à confirmation du planning.',
  };
}

/**
 * Pour les contrôles légaux, une mission terminée est comparée à ce qui a été
 * réellement pointé. Les créneaux EFFECTIF remplacent alors complètement les
 * PREVISIONNEL, comme dans les garde-fous SQL, sans jamais additionner les deux.
 */
export function construirePlanningConformite(
  mission: MissionPlanningCandidat,
  creneaux: CreneauMissionCandidat[] = mission.creneaux_planifies ?? [],
): PlanningCandidat {
  const effectifs = creneaux.filter((creneau) => (
    creneau.type_creneau === 'EFFECTIF' && !creneau.est_pause
  ));
  if (mission.statut !== 'TERMINEE' || effectifs.length === 0) {
    return construirePlanningCandidat(mission, creneaux);
  }

  return construirePlanningCandidat(
    { ...mission, nb_creneaux: effectifs.length },
    effectifs.map((creneau) => ({ ...creneau, type_creneau: 'PREVISIONNEL' })),
  );
}

export function creneauxConfirmesPourAction(
  mission: MissionPlanningCandidat,
): CreneauConfirmeAction[] | null {
  const planning = construirePlanningCandidat(mission);
  if (!planning.exact || planning.creneaux.some((creneau) => !creneau.fin)) {
    return null;
  }
  return planning.creneaux.map((creneau) => ({
    debut: creneau.debut,
    fin: creneau.fin!,
  }));
}

export function associerCreneauxAuxMissions<T extends MissionPlanningCandidat>(
  missions: T[],
  creneaux: CreneauMissionCandidat[],
  erreur = false,
): Array<T & MissionPlanningCandidat> {
  const parMission = new Map<string, CreneauMissionCandidat[]>();
  for (const creneau of creneaux) {
    if (!creneau.mission_id) continue;
    const liste = parMission.get(creneau.mission_id) ?? [];
    liste.push(creneau);
    parMission.set(creneau.mission_id, liste);
  }

  return missions.map((mission) => {
    const id = missionId(mission);
    const creneauxMission = id ? parMission.get(id) ?? [] : [];
    const planning = construirePlanningCandidat(
      mission,
      creneauxMission,
      erreur,
    );
    return {
      ...mission,
      // Conserver les lignes incomplètes permet aux rendus suivants de rester
      // fail-closed. Pour une mission ponctuelle legacy sans ligne, le repli
      // contractuel calculé devient en revanche le planning affichable.
      creneaux_planifies: creneauxMission.length > 0 ? creneauxMission : planning.creneaux,
      planning_exact: planning.exact,
      erreur_planning: erreur,
    };
  });
}

export function creneauContientNuit(creneau: CreneauPointage): boolean {
  if (!creneau.fin) return false;
  const debutMs = instantJolene(creneau.debut).getTime();
  const finMs = instantJolene(creneau.fin).getTime();
  let jour = debutJourParis(creneau.debut);

  while (jour.getTime() < finMs) {
    const lendemain = ajouterJoursCivilsParis(jour, 1);
    const finNuitMatin = instantParisDuJour(jour, 7);
    const debutNuitSoir = instantParisDuJour(jour, 20);
    if (
      chevauchement(debutMs, finMs, jour.getTime(), finNuitMatin.getTime())
      || chevauchement(debutMs, finMs, debutNuitSoir.getTime(), lendemain.getTime())
    ) return true;
    jour = lendemain;
  }
  return false;
}

export function creneauChevaucheWeekend(creneau: CreneauPointage): boolean {
  if (!creneau.fin) return false;
  const debutMs = instantJolene(creneau.debut).getTime();
  const finMs = instantJolene(creneau.fin).getTime();
  let jour = debutJourParis(creneau.debut);

  while (jour.getTime() < finMs) {
    const parties = partiesDateHeureParis(jour);
    const jourSemaine = new Date(Date.UTC(parties.annee, parties.mois - 1, parties.jour, 12)).getUTCDay();
    const lendemain = ajouterJoursCivilsParis(jour, 1);
    if (
      (jourSemaine === 0 || jourSemaine === 6)
      && chevauchement(debutMs, finMs, jour.getTime(), lendemain.getTime())
    ) return true;
    jour = lendemain;
  }
  return false;
}

export function planningCorrespondAuFiltre(
  mission: MissionPlanningCandidat,
  filtre: FiltreHoraireCandidat,
): boolean {
  if (filtre === 'TOUS') return true;
  const planning = construirePlanningCandidat(mission);
  if (!planning.exact) return false;
  if (filtre === 'NUIT') return planning.creneaux.some(creneauContientNuit);
  if (filtre === 'JOUR') return planning.creneaux.some((creneau) => !creneauContientNuit(creneau));
  return planning.creneaux.some(creneauChevaucheWeekend);
}

export function trouverChevauchementPlannings(
  cible: PlanningCandidat,
  existant: PlanningCandidat,
): { cible: CreneauPointage; existant: CreneauPointage } | null {
  for (const creneauCible of cible.creneaux) {
    if (!creneauCible.fin) continue;
    for (const creneauExistant of existant.creneaux) {
      if (!creneauExistant.fin) continue;
      if (chevauchement(
        instantJolene(creneauCible.debut).getTime(),
        instantJolene(creneauCible.fin).getTime(),
        instantJolene(creneauExistant.debut).getTime(),
        instantJolene(creneauExistant.fin).getTime(),
      )) return { cible: creneauCible, existant: creneauExistant };
    }
  }
  return null;
}

export function trouverReposInsuffisant(
  cible: PlanningCandidat,
  existant: PlanningCandidat,
): { heures: number; position: 'AVANT' | 'APRES'; creneauExistant: CreneauPointage } | null {
  for (const creneauCible of cible.creneaux) {
    if (!creneauCible.fin) continue;
    const debutCible = instantJolene(creneauCible.debut).getTime();
    const finCible = instantJolene(creneauCible.fin).getTime();
    for (const creneauExistant of existant.creneaux) {
      if (!creneauExistant.fin) continue;
      const debutExistant = instantJolene(creneauExistant.debut).getTime();
      const finExistant = instantJolene(creneauExistant.fin).getTime();
      if (finExistant <= debutCible) {
        const heures = (debutCible - finExistant) / 3_600_000;
        if (heures < 11) return { heures, position: 'APRES', creneauExistant };
      } else if (finCible <= debutExistant) {
        const heures = (debutExistant - finCible) / 3_600_000;
        if (heures < 11) return { heures, position: 'AVANT', creneauExistant };
      }
    }
  }
  return null;
}

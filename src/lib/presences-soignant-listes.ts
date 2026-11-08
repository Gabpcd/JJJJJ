import { ajouterJoursCivilsParis, debutJourParis } from '@/lib/date-heure-paris';
import {
  ajouterRepliMissionPonctuelle,
  choisirContratPointage,
  creneauChevauchePeriode,
  creneauxPrevisionnels,
  filtrerMissionsEnCours,
  type ContratPointage,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';

/**
 * Listes de la page Présences du soignant (Aujourd'hui, À venir, Actives),
 * extraites de `PresencesSoignant.tsx` pour être partagées avec le port natif
 * (vecteurs golden iOS, lot 2 W1). Règle pure : horloge explicite, jour civil
 * de Paris, aucun accès réseau.
 */

/** Mission ASSIGNEE ou EN_COURS du soignant, telle que lue par la page. */
export interface MissionPresenceSoignant {
  id: string;
  statut: string;
  debut_le: string;
  fin_le: string;
  duree_heures?: number | null;
  etablissement_id?: string | null;
}

/** Contrat de mission lu pour le pointage. */
export interface ContratPresenceSoignant extends ContratPointage {
  mission_id: string;
}

export type MissionPresenceEnrichie<M extends MissionPresenceSoignant, E = unknown> = M & {
  creneaux: CreneauPointage[];
  /** Nom et adresse lus par `fn_etablissements_safe` (null si inconnu). */
  etablissements: E | null;
};

export type MissionPresenceAVenir<M extends MissionPresenceSoignant, E = unknown> = MissionPresenceEnrichie<M, E> & {
  dateAffichage: string | null;
  prochainCreneau: CreneauPointage | null;
  dureeAffichageHeures: number | null;
  planningAConfirmer?: true;
};

export interface ListesPresencesSoignant<
  M extends MissionPresenceSoignant,
  C extends ContratPresenceSoignant,
  E = unknown,
> {
  /** Onglet « Aujourd'hui » : segment EFFECTIF ouvert ou créneau prévu ce jour. */
  missionsAujourdhui: MissionPresenceEnrichie<M, E>[];
  /** Onglet « À venir » : prochain créneau dès demain, puis plannings à confirmer (20 au plus). */
  missionsAVenir: MissionPresenceAVenir<M, E>[];
  /** Onglet « Actives » : missions EN_COURS. */
  missionsEnCours: MissionPresenceEnrichie<M, E>[];
  /** Contrat retenu pour le pointage, par mission. */
  contrats: Record<string, C>;
}

/** Regroupe les lignes `mission_creneaux` par mission, dans l'ordre reçu. */
export function regrouperCreneauxParMission<T extends CreneauPointage & { mission_id: string }>(
  creneaux: T[] | null | undefined,
): Record<string, T[]> {
  const creneauxParMission: Record<string, T[]> = {};
  (creneaux || []).forEach((creneau) => {
    (creneauxParMission[creneau.mission_id] ||= []).push(creneau);
  });
  return creneauxParMission;
}

export function construireListesPresences<
  M extends MissionPresenceSoignant,
  C extends ContratPresenceSoignant,
  E = unknown,
>({
  missions,
  creneauxParMission,
  contrats,
  maintenant,
  etablissements = {},
}: {
  missions: M[];
  creneauxParMission: Record<string, CreneauPointage[]>;
  contrats: C[] | null | undefined;
  maintenant: Date;
  etablissements?: Record<string, E>;
}): ListesPresencesSoignant<M, C, E> {
  const aujourdhui = debutJourParis(maintenant);
  const demain = ajouterJoursCivilsParis(aujourdhui, 1);

  const contratsParMission: Record<string, C[]> = {};
  (contrats || []).forEach((contrat) => {
    (contratsParMission[contrat.mission_id] ||= []).push(contrat);
  });
  const contratsMap: Record<string, C> = {};
  Object.entries(contratsParMission).forEach(([missionId, contratsMission]) => {
    const contrat = choisirContratPointage(contratsMission);
    if (contrat) contratsMap[missionId] = contrat;
  });

  const missionsEnrichies: MissionPresenceEnrichie<M, E>[] = missions.map((mission) => ({
    ...mission,
    creneaux: ajouterRepliMissionPonctuelle(creneauxParMission[mission.id] || [], mission),
    etablissements: etablissements[mission.etablissement_id] || null,
  }));

  const missionsList = missionsEnrichies.filter((mission) => {
    const creneaux = mission.creneaux;
    const aUnSegmentOuvert = creneaux.some((creneau) => (
      creneau.type_creneau === 'EFFECTIF' && !creneau.est_pause && !creneau.fin
    ));
    const planifies = creneauxPrevisionnels(creneaux);
    const aUnCreneauAujourdhui = planifies.some((creneau) => (
      creneauChevauchePeriode(creneau, aujourdhui, demain)
    ));
    return aUnSegmentOuvert
      || aUnCreneauAujourdhui;
  });

  const aVenirList: MissionPresenceAVenir<M, E>[] = missionsEnrichies
    .map((mission): MissionPresenceAVenir<M, E> | null => {
      const prochain = creneauxPrevisionnels(mission.creneaux)
        .find((creneau) => new Date(creneau.debut) >= demain);
      const dateAffichage = prochain?.debut ?? null;
      const dureeAffichageHeures = prochain?.fin
        ? (new Date(prochain.fin).getTime() - new Date(prochain.debut).getTime()) / 3_600_000
        : mission.duree_heures;
      return dateAffichage
        ? { ...mission, dateAffichage, prochainCreneau: prochain, dureeAffichageHeures }
        : null;
    })
    .filter(Boolean)
    .concat(missionsEnrichies
      .filter((mission) => (
        mission.statut === 'ASSIGNEE'
        && creneauxPrevisionnels(mission.creneaux).length === 0
      ))
      .map((mission) => ({
        ...mission,
        dateAffichage: null,
        prochainCreneau: null,
        dureeAffichageHeures: null,
        planningAConfirmer: true as const,
      })))
    .sort((a, b) => (
      a.dateAffichage && b.dateAffichage
        ? new Date(a.dateAffichage).getTime() - new Date(b.dateAffichage).getTime()
        : a.dateAffichage ? -1 : b.dateAffichage ? 1 : 0
    ))
    .slice(0, 20);

  // Une mission EN_COURS reste visible même sans présence legacy : les
  // créneaux EFFECTIF sont désormais la source de vérité du pointage.
  const enCoursList = filtrerMissionsEnCours(missionsEnrichies);

  return {
    missionsAujourdhui: missionsList,
    missionsAVenir: aVenirList,
    missionsEnCours: enCoursList,
    contrats: contratsMap,
  };
}

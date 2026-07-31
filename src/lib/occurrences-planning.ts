import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { ajouterJoursCivilsParis, debutJourParis } from '@/lib/date-heure-paris';

export interface MissionPlanifiable {
  id: string;
  debut_le: string;
  fin_le: string;
  duree_heures?: number | null;
}

export interface CreneauMissionPlanifiable extends CreneauPointage {
  mission_id: string;
}

export type OccurrenceMission<T extends MissionPlanifiable> = T & {
  occurrence_id: string;
  debut_le: string;
  fin_le: string;
  duree_heures: number;
};

export type SegmentJournalierOccurrence<T extends MissionPlanifiable> = OccurrenceMission<T> & {
  segment_id: string;
};

/**
 * Découpe un créneau traversant minuit en portions de jours civils. Cette
 * représentation évite qu'une garde dimanche soir → lundi matin disparaisse
 * du lundi ou soit entièrement comptée dans la semaine précédente.
 */
export function decouperOccurrencesParJour<T extends MissionPlanifiable>(
  occurrences: OccurrenceMission<T>[],
): SegmentJournalierOccurrence<T>[] {
  return occurrences.flatMap((occurrence) => {
    const debut = new Date(occurrence.debut_le);
    const fin = new Date(occurrence.fin_le);
    if (!Number.isFinite(debut.getTime()) || !Number.isFinite(fin.getTime()) || fin <= debut) {
      return [];
    }

    const segments: SegmentJournalierOccurrence<T>[] = [];
    let jour = debutJourParis(debut);
    while (jour < fin) {
      const lendemain = ajouterJoursCivilsParis(jour, 1);
      const debutSegment = new Date(Math.max(debut.getTime(), jour.getTime()));
      const finSegment = new Date(Math.min(fin.getTime(), lendemain.getTime()));
      if (finSegment > debutSegment) {
        segments.push({
          ...occurrence,
          segment_id: `${occurrence.occurrence_id}:${jour.toISOString()}`,
          debut_le: debutSegment.toISOString(),
          fin_le: finSegment.toISOString(),
          duree_heures: (finSegment.getTime() - debutSegment.getTime()) / 3_600_000,
        });
      }
      jour = lendemain;
    }
    return segments;
  });
}

/**
 * Matérialise uniquement les jours et horaires réellement travaillés.
 * La plage globale d'une mission longue n'est jamais transformée en présence
 * quotidienne. Le repli historique reste limité aux missions de 24 h maximum.
 */
export function construireOccurrencesPlanning<T extends MissionPlanifiable>(
  missions: T[],
  creneaux: CreneauMissionPlanifiable[],
): OccurrenceMission<T>[] {
  const creneauxParMission = new Map<string, CreneauMissionPlanifiable[]>();
  for (const creneau of creneaux) {
    const liste = creneauxParMission.get(creneau.mission_id) ?? [];
    liste.push(creneau);
    creneauxParMission.set(creneau.mission_id, liste);
  }

  return missions.flatMap((mission) => {
    const planification = ajouterRepliMissionPonctuelle(
      creneauxParMission.get(mission.id) ?? [],
      mission,
    );

    return creneauxPrevisionnels(planification).flatMap((creneau) => {
      if (!creneau.fin) return [];
      const dureeHeures = (
        new Date(creneau.fin).getTime() - new Date(creneau.debut).getTime()
      ) / 3_600_000;
      if (!Number.isFinite(dureeHeures) || dureeHeures <= 0) return [];

      return [{
        ...mission,
        occurrence_id: `${mission.id}:${creneau.id ?? creneau.debut}`,
        debut_le: creneau.debut,
        fin_le: creneau.fin,
        duree_heures: dureeHeures,
      }];
    });
  }).sort((a, b) => (
    new Date(a.debut_le).getTime() - new Date(b.debut_le).getTime()
  ));
}

export function missionsLonguesSansPlanning<T extends MissionPlanifiable>(
  missions: T[],
  creneaux: CreneauMissionPlanifiable[],
): T[] {
  const idsAvecPlanning = new Set(
    creneaux
      .filter((creneau) => (
        creneau.type_creneau === 'PREVISIONNEL'
        && !creneau.est_pause
        && Boolean(creneau.fin)
      ))
      .map((creneau) => creneau.mission_id),
  );

  return missions.filter((mission) => {
    const dureeGlobale = (
      new Date(mission.fin_le).getTime() - new Date(mission.debut_le).getTime()
    );
    return dureeGlobale > 24 * 60 * 60_000 && !idsAvecPlanning.has(mission.id);
  });
}

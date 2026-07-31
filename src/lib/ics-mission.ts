import { format } from 'date-fns';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { telechargerOuPartager } from '@/lib/telechargement';

export interface MissionCalendrier {
  id?: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  creneaux?: CreneauPointage[];
  etablissements?: {
    nom?: string;
    adresse_ville?: string;
    adresse_rue?: string;
  } | null;
}

function formatDateIcs(date: string): string {
  return new Date(date).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

function echapperIcs(valeur: string): string {
  return valeur
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/** Génère un événement par créneau travaillé, jamais par plage globale longue. */
export function generateMissionIcs(mission: MissionCalendrier): string {
  const location = [mission.etablissements?.adresse_rue, mission.etablissements?.adresse_ville].filter(Boolean).join(', ');
  const summary = echapperIcs(mission.intitule);
  const desc = `Mission Jolene — ${mission.etablissements?.nom || ''}`;
  const creneaux = creneauxPrevisionnels(
    ajouterRepliMissionPonctuelle(mission.creneaux ?? [], mission),
  );
  const identifiantMission = mission.id ?? mission.debut_le;

  const evenements = creneaux.flatMap((creneau, index) => {
    if (!creneau.fin) return [];
    return [
      'BEGIN:VEVENT',
      `DTSTART:${formatDateIcs(creneau.debut)}`,
      `DTEND:${formatDateIcs(creneau.fin)}`,
      `SUMMARY:${summary}`,
      `DESCRIPTION:${echapperIcs(desc)}`,
      location ? `LOCATION:${echapperIcs(location)}` : '',
      `UID:${identifiantMission}-${creneau.id ?? index}@jolene.app`,
      'END:VEVENT',
    ].filter(Boolean).join('\r\n');
  });

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Jolene//Missions//FR',
    ...evenements,
    'END:VCALENDAR',
  ].filter(Boolean).join('\r\n');
}

export async function downloadMissionIcs(mission: MissionCalendrier) {
  const ics = generateMissionIcs(mission);
  await telechargerOuPartager(
    ics,
    `mission-jolene-${format(new Date(mission.debut_le), 'yyyy-MM-dd')}.ics`,
    'text/calendar',
  );
}

import { format } from 'date-fns';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { isNative } from '@/lib/platform';
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

/**
 * Ouvre l'éditeur calendrier du système dans les apps iOS/Android.
 *
 * Le bouton du dashboard représente le prochain créneau visible : on reprend
 * donc exactement `debut_le` / `fin_le`, sans transformer une série avec
 * pauses en un événement continu. Sur le web, le fichier ICS complet reste le
 * comportement attendu.
 */
export async function ouvrirMissionDansCalendrier(mission: MissionCalendrier): Promise<void> {
  if (!isNative()) {
    await downloadMissionIcs(mission);
    return;
  }

  const debut = new Date(mission.debut_le).getTime();
  const fin = new Date(mission.fin_le).getTime();
  if (!Number.isFinite(debut) || !Number.isFinite(fin) || fin <= debut) {
    throw new Error('Le créneau de cette mission est invalide.');
  }

  const { CapacitorCalendar } = await import('@ebarooni/capacitor-calendar');
  const etablissement = mission.etablissements?.nom?.trim();
  const lieu = [
    mission.etablissements?.adresse_rue,
    mission.etablissements?.adresse_ville,
  ].filter(Boolean).join(', ');

  await CapacitorCalendar.createEventWithPrompt({
    title: mission.intitule,
    startDate: debut,
    endDate: fin,
    location: lieu || undefined,
    description: etablissement
      ? `Mission Jolene — ${etablissement}`
      : 'Mission Jolene',
    alerts: [-1440, -60],
    url: mission.id
      ? `https://jolene.app/soignant/missions/${encodeURIComponent(mission.id)}`
      : undefined,
  });
}

/**
 * Formatage unifié des dates/horaires/durées d'une mission (Lot 6a.3).
 *
 * Source unique pour toutes les surfaces soignant (carte liste, carte swipe,
 * modal swipe, détail, mes missions) : avant, chaque surface formatait à sa
 * façon et une mission multi-jours s'affichait « 13h00 → 21h00 (160h) » —
 * illisible et perçu comme un bug.
 *
 * Règles :
 * - Mission d'un jour  → « jeudi 3 juillet 2026 » + « 08h00 → 18h00 (10 h) »
 * - Mission multi-jours → « 13 → 7 août 2026 » + « 20 jours · 8 h/j · 13h–21h »
 * - Le label jour/nuit est TOUJOURS dérivé des horaires réels, jamais stocké.
 */
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export interface MissionHoraires {
  debut_le: string | null;
  fin_le: string | null;
  /** numeric Postgres → arrive parfois en string. */
  duree_heures?: number | string | null;
  nb_creneaux?: number | null;
}

const MS_JOUR = 86400000;

/** Nuit dérivée des horaires réels : début à 20 h ou plus, ou avant 7 h. */
export function estMissionDeNuit(debutISO: string | null): boolean {
  if (!debutISO) return false;
  const h = new Date(debutISO).getHours();
  return h >= 20 || h < 7;
}

/** Multi-jours : plusieurs créneaux, ou plage début→fin au-delà de 24 h. */
export function estMultiJours(m: MissionHoraires): boolean {
  if (!m.debut_le || !m.fin_le) return false;
  if ((m.nb_creneaux ?? 0) > 1) return true;
  return new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime() > MS_JOUR;
}

/** Durée quotidienne (h) dérivée des heures de la journée — gère la nuit qui passe minuit. */
function heuresParJour(debut: Date, fin: Date): number {
  let minutes = (fin.getHours() * 60 + fin.getMinutes()) - (debut.getHours() * 60 + debut.getMinutes());
  if (minutes <= 0) minutes += 24 * 60;
  return minutes / 60;
}

/** Nombre de jours travaillés : créneaux si connus, sinon durée totale / durée quotidienne. */
export function nbJoursTravailles(m: MissionHoraires): number {
  if (!m.debut_le || !m.fin_le) return 1;
  if ((m.nb_creneaux ?? 0) > 1) return m.nb_creneaux!;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  if (!estMultiJours(m)) return 1;
  const duree = Number(m.duree_heures) || 0;
  const hJour = heuresParJour(debut, fin);
  if (duree > 0 && hJour > 0) return Math.max(1, Math.round(duree / hJour));
  return Math.max(1, Math.ceil((fin.getTime() - debut.getTime()) / MS_JOUR));
}

/** « 10 » ou « 7,5 » — entier si rond, sinon 1 décimale (virgule FR). */
function fmtHeures(h: number): string {
  const arrondi = Math.round(h * 10) / 10;
  return Number.isInteger(arrondi) ? String(arrondi) : String(arrondi).replace('.', ',');
}

/** « 08h » ou « 08h30 » — minutes seulement si non nulles. */
function heureCompacte(d: Date): string {
  return format(d, d.getMinutes() === 0 ? "HH'h'" : "HH'h'mm", { locale: fr });
}

/**
 * Ligne date : « jeudi 3 juillet 2026 » (1 jour)
 * ou « 13 → 7 août 2026 » / « 28 juil. → 3 août 2026 » (multi-jours).
 */
export function formatDateMission(m: MissionHoraires): string {
  if (!m.debut_le) return '—';
  const debut = new Date(m.debut_le);
  if (!estMultiJours(m) || !m.fin_le) return format(debut, 'EEEE d MMMM yyyy', { locale: fr });
  const fin = new Date(m.fin_le);
  const memeMois = debut.getMonth() === fin.getMonth() && debut.getFullYear() === fin.getFullYear();
  return memeMois
    ? `${format(debut, 'd', { locale: fr })} → ${format(fin, 'd MMMM yyyy', { locale: fr })}`
    : `${format(debut, 'd MMM', { locale: fr })} → ${format(fin, 'd MMM yyyy', { locale: fr })}`;
}

/**
 * Ligne horaires : « 08h00 → 18h00 (10 h) » (1 jour)
 * ou « 20 jours · 8 h/j · 13h–21h » (multi-jours).
 */
export function formatHorairesMission(m: MissionHoraires): string {
  if (!m.debut_le || !m.fin_le) return '—';
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const duree = Number(m.duree_heures) || (fin.getTime() - debut.getTime()) / 3600000;

  if (!estMultiJours(m)) {
    return `${format(debut, "HH'h'mm", { locale: fr })} → ${format(fin, "HH'h'mm", { locale: fr })} (${fmtHeures(duree)} h)`;
  }

  const jours = nbJoursTravailles(m);
  const hJour = heuresParJour(debut, fin);
  return `${jours} jours · ${fmtHeures(hJour)} h/j · ${heureCompacte(debut)}–${heureCompacte(fin)}`;
}

/** Résumé une ligne (carte swipe) : « 10 h · jeu. 3 juil. » ou « 20 jours · 8 h/j ». */
export function formatDureeCompacte(m: MissionHoraires): string {
  if (!m.debut_le || !m.fin_le) return '—';
  const duree = Number(m.duree_heures) || 0;
  if (!estMultiJours(m)) return duree > 0 ? `${fmtHeures(duree)}h` : '—';
  return `${nbJoursTravailles(m)} jours · ${fmtHeures(heuresParJour(new Date(m.debut_le), new Date(m.fin_le)))} h/j`;
}

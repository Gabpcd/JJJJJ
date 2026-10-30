import type { PresenceAvailability, PresenceMission } from '../../workflows/presence/types';
const time = new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', hour: '2-digit', minute: '2-digit' });
const day = new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', day: 'numeric', month: 'long', year: 'numeric' });
export function presenceDate(value: string): string {
  const date = new Date(value); return Number.isFinite(date.getTime()) ? `${day.format(date)} à ${time.format(date)}` : 'Horaire indisponible';
}
export function presencePeriod(mission: PresenceMission): string { return `${presenceDate(mission.debut_le)} → ${presenceDate(mission.fin_le)}`; }
export function presenceReason(reason: PresenceAvailability['reason']): string | null {
  switch (reason) {
    case 'CONTRAT': return 'Le contrat doit être signé par les deux parties avant l’arrivée.';
    case 'HORS_CRENEAU': return 'Le pointage d’arrivée s’ouvre 15 minutes avant le début d’un créneau.';
    case 'AUCUN_CRENEAU': return 'Le planning de cette mission doit être précisé avant l’arrivée.';
    case 'PLANNING_INCOMPLETE': return 'Le planning complet n’a pas pu être confirmé. Actualisez avant de pointer.';
    case 'CONTRACT_PERMISSION': return 'Votre accès ne permet pas de vérifier le contrat nécessaire à l’arrivée.';
    case 'CONTRACT_UNAVAILABLE': return 'Le contrat ne peut pas être relu actuellement. Actualisez avant d’enregistrer une arrivée.';
    case 'SERVER_TIME_UNAVAILABLE': return 'L’heure du serveur est indisponible. Actualisez pour vérifier l’ouverture du pointage.';
    case 'TERMINAL': return 'Cette mission n’accepte plus de nouveau pointage.';
    default: return null;
  }
}
export function presenceStatus(status: string): string {
  return ({ ASSIGNEE: 'À venir', EN_COURS: 'En cours', TERMINEE: 'Terminée', LITIGE: 'Litige', ABSENCE: 'Absence' } as Record<string, string>)[status] ?? status;
}

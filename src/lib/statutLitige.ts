import { LucideIcon, Scale, MessageSquare, AlertTriangle, CheckCircle2, Gavel, XCircle, Users } from 'lucide-react';
import { statutLitigeRegle, type GroupeStatut, type IconeStatutLitige } from '@/lib/statut-litige-regles';

// La table des statuts (libellé, groupe, prédicats) est une règle pure partagée
// avec l'app iOS native ; ce module n'y ajoute que les icônes lucide.
export { estResolu, peutProposerMediation, peutConfirmerAccord } from '@/lib/statut-litige-regles';
export type { StatutLitige, GroupeStatut } from '@/lib/statut-litige-regles';

interface BadgeInfo {
  label: string;
  icon: LucideIcon;
  classes: string;
  groupe: GroupeStatut;
}

const ICONES: Record<IconeStatutLitige, LucideIcon> = {
  Scale,
  MessageSquare,
  AlertTriangle,
  Users,
  Gavel,
  CheckCircle2,
  XCircle,
};

export function statutBadgeV2(statut: string): BadgeInfo {
  const { label, icone, classes, groupe } = statutLitigeRegle(statut);
  return { label, icon: ICONES[icone], classes, groupe };
}

/** Heures restantes avant timeout 7j (depuis cree_le) — négatif si expiré */
export function heuresRestantes7j(creeLe: string): number {
  const debut = new Date(creeLe).getTime();
  const limite = debut + 7 * 24 * 60 * 60 * 1000;
  return (limite - Date.now()) / (1000 * 60 * 60);
}

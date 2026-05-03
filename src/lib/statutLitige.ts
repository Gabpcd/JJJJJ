import { LucideIcon, Scale, MessageSquare, AlertTriangle, CheckCircle2, Gavel, XCircle, Users } from 'lucide-react';

export type StatutLitige =
  | 'OUVERT' | 'EN_DISCUSSION' | 'EN_MEDIATION'
  | 'MEDIATION_EN_COURS' | 'RESOLU_ACCORD_PARTIES' | 'REVUE_ADMIN'
  | 'RESOLU_FAVEUR_SOIGNANT' | 'RESOLU_FAVEUR_ETAB' | 'RESOLU_PARTAGE'
  | 'RESOLU_SOIGNANT' | 'RESOLU_ETABLISSEMENT' | 'RESOLU_ADMIN' | 'FERME';

export type GroupeStatut = 'OUVERT' | 'MEDIATION' | 'ACTION_ATTENDUE' | 'RESOLU_ACCORD' | 'RESOLU_DECISION' | 'FERME';

interface BadgeInfo {
  label: string;
  icon: LucideIcon;
  classes: string;
  groupe: GroupeStatut;
}

export function statutBadgeV2(statut: string): BadgeInfo {
  switch (statut as StatutLitige) {
    case 'OUVERT':
      return { label: 'Ouvert', icon: Scale, classes: 'bg-warning/10 text-warning border-warning/30', groupe: 'OUVERT' };
    case 'EN_DISCUSSION':
      return { label: 'En discussion', icon: MessageSquare, classes: 'bg-warning/10 text-warning border-warning/30', groupe: 'OUVERT' };
    case 'EN_MEDIATION':
      return { label: 'Médiation', icon: AlertTriangle, classes: 'bg-info/10 text-info border-info/30', groupe: 'MEDIATION' };
    case 'MEDIATION_EN_COURS':
      return { label: 'Médiation en cours', icon: Users, classes: 'bg-info/10 text-info border-info/30', groupe: 'MEDIATION' };
    case 'REVUE_ADMIN':
      return { label: 'Revue admin', icon: Gavel, classes: 'bg-destructive/10 text-destructive border-destructive/30', groupe: 'ACTION_ATTENDUE' };
    case 'RESOLU_ACCORD_PARTIES':
      return { label: 'Accord mutuel ✅', icon: CheckCircle2, classes: 'bg-success/10 text-success border-success/30', groupe: 'RESOLU_ACCORD' };
    case 'RESOLU_FAVEUR_SOIGNANT':
      return { label: 'Tranché en faveur soignant', icon: Gavel, classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_FAVEUR_ETAB':
      return { label: 'Tranché en faveur étab', icon: Gavel, classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_PARTAGE':
      return { label: 'Tranché : décision partagée', icon: Gavel, classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_SOIGNANT':
      return { label: 'Résolu (soignant)', icon: CheckCircle2, classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_ETABLISSEMENT':
      return { label: 'Résolu (étab)', icon: CheckCircle2, classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_ADMIN':
      return { label: 'Résolu admin', icon: Gavel, classes: 'bg-muted text-muted-foreground border-border', groupe: 'FERME' };
    case 'FERME':
      return { label: 'Fermé', icon: XCircle, classes: 'bg-muted text-muted-foreground border-border', groupe: 'FERME' };
    default:
      return { label: statut, icon: Scale, classes: 'bg-muted text-muted-foreground border-border', groupe: 'OUVERT' };
  }
}

const STATUTS_RESOLUS = new Set<StatutLitige>([
  'RESOLU_ACCORD_PARTIES','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE',
  'RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
]);

export function estResolu(statut: string): boolean {
  return STATUTS_RESOLUS.has(statut as StatutLitige);
}

const STATUTS_PROPOSER_MEDIATION = new Set<StatutLitige>(['OUVERT','EN_DISCUSSION','EN_MEDIATION']);
export function peutProposerMediation(statut: string): boolean {
  return STATUTS_PROPOSER_MEDIATION.has(statut as StatutLitige);
}

const STATUTS_CONFIRMER_ACCORD = new Set<StatutLitige>([
  'OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS',
]);
export function peutConfirmerAccord(statut: string): boolean {
  return STATUTS_CONFIRMER_ACCORD.has(statut as StatutLitige);
}

/** Heures restantes avant timeout 7j (depuis cree_le) — négatif si expiré */
export function heuresRestantes7j(creeLe: string): number {
  const debut = new Date(creeLe).getTime();
  const limite = debut + 7 * 24 * 60 * 60 * 1000;
  return (limite - Date.now()) / (1000 * 60 * 60);
}

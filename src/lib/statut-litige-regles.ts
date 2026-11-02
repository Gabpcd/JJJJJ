/**
 * Partie pure des statuts de litige (libellé, groupe, icône nommée, prédicats),
 * extraite de `statutLitige.ts` sans `lucide-react` pour être partagée avec le
 * port natif (vecteurs golden iOS, lot 4 W0). `statutLitige.ts` la réexporte
 * et associe chaque icône nommée à son composant lucide.
 *
 * Périmètre : source unique de `statutBadgeV2` (`statutLitige.ts`) seulement.
 * `FilDiscussionLitige.tsx` (`STATUT_LABELS`, l.19) et `PanneauContestation.tsx`
 * (`STATUT_CONFIG`, l.48) gardent leurs propres libellés, classes et icônes,
 * antérieurs à cette extraction. Le natif (lot 4 T2) réplique `statutBadgeV2`,
 * sans viser la parité avec ces deux surfaces.
 */

export type StatutLitige =
  | 'OUVERT' | 'EN_DISCUSSION' | 'EN_MEDIATION'
  | 'MEDIATION_EN_COURS' | 'RESOLU_ACCORD_PARTIES' | 'REVUE_ADMIN'
  | 'RESOLU_FAVEUR_SOIGNANT' | 'RESOLU_FAVEUR_ETAB' | 'RESOLU_PARTAGE'
  | 'RESOLU_SOIGNANT' | 'RESOLU_ETABLISSEMENT' | 'RESOLU_ADMIN' | 'FERME';

export type GroupeStatut = 'OUVERT' | 'MEDIATION' | 'ACTION_ATTENDUE' | 'RESOLU_ACCORD' | 'RESOLU_DECISION' | 'FERME';

/** Nom de l'icône lucide du badge (le composant est choisi côté web). */
export type IconeStatutLitige =
  | 'Scale' | 'MessageSquare' | 'AlertTriangle' | 'Users' | 'Gavel' | 'CheckCircle2' | 'XCircle';

export interface StatutLitigeRegle {
  label: string;
  icone: IconeStatutLitige;
  classes: string;
  groupe: GroupeStatut;
}

export function statutLitigeRegle(statut: string): StatutLitigeRegle {
  switch (statut as StatutLitige) {
    case 'OUVERT':
      return { label: 'Ouvert', icone: 'Scale', classes: 'bg-warning/10 text-warning border-warning/30', groupe: 'OUVERT' };
    case 'EN_DISCUSSION':
      return { label: 'En discussion', icone: 'MessageSquare', classes: 'bg-warning/10 text-warning border-warning/30', groupe: 'OUVERT' };
    case 'EN_MEDIATION':
      return { label: 'Médiation', icone: 'AlertTriangle', classes: 'bg-info/10 text-info border-info/30', groupe: 'MEDIATION' };
    case 'MEDIATION_EN_COURS':
      return { label: 'Médiation en cours', icone: 'Users', classes: 'bg-info/10 text-info border-info/30', groupe: 'MEDIATION' };
    case 'REVUE_ADMIN':
      return { label: 'Revue admin', icone: 'Gavel', classes: 'bg-destructive/10 text-destructive border-destructive/30', groupe: 'ACTION_ATTENDUE' };
    case 'RESOLU_ACCORD_PARTIES':
      return { label: 'Accord mutuel ✅', icone: 'CheckCircle2', classes: 'bg-success/10 text-success border-success/30', groupe: 'RESOLU_ACCORD' };
    case 'RESOLU_FAVEUR_SOIGNANT':
      return { label: 'Tranché en faveur soignant', icone: 'Gavel', classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_FAVEUR_ETAB':
      return { label: 'Tranché en faveur étab', icone: 'Gavel', classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_PARTAGE':
      return { label: 'Tranché : décision partagée', icone: 'Gavel', classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_SOIGNANT':
      return { label: 'Résolu (soignant)', icone: 'CheckCircle2', classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_ETABLISSEMENT':
      return { label: 'Résolu (étab)', icone: 'CheckCircle2', classes: 'bg-success/5 text-foreground border-border', groupe: 'RESOLU_DECISION' };
    case 'RESOLU_ADMIN':
      return { label: 'Résolu admin', icone: 'Gavel', classes: 'bg-muted text-muted-foreground border-border', groupe: 'FERME' };
    case 'FERME':
      return { label: 'Fermé', icone: 'XCircle', classes: 'bg-muted text-muted-foreground border-border', groupe: 'FERME' };
    default:
      return { label: statut, icone: 'Scale', classes: 'bg-muted text-muted-foreground border-border', groupe: 'OUVERT' };
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

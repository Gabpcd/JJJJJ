import {
  AlertTriangle, Info, Banknote, FileSignature, MapPin, MessageCircle,
  Star, Bell, type LucideIcon
} from 'lucide-react';

/**
 * Mapping type_evenement → icône + couleur Tailwind pour distinction visuelle
 * des notifications soignant/étab.
 *
 * Sprint 7 PR 5 — Cosmétique P2 §12.
 *
 * Couleurs sémantiques :
 * - urgence (rouge), info (bleu), paiement (vert), signature (violet),
 *   pointage (orange), messagerie (cyan), évaluation (jaune), défaut (gris)
 */
export interface IconeNotifInfo {
  icone: LucideIcon;
  couleur: string; // Tailwind class
  fondCouleur: string;
}

const MAP: Record<string, IconeNotifInfo> = {
  URGENCE: { icone: AlertTriangle, couleur: 'text-destructive', fondCouleur: 'bg-destructive/10' },
  MISSION_ASSIGNEE: { icone: Info, couleur: 'text-info', fondCouleur: 'bg-info/10' },
  CANDIDATURE_ACCEPTEE: { icone: Info, couleur: 'text-success', fondCouleur: 'bg-success/10' },
  CANDIDATURE_RECUE: { icone: Info, couleur: 'text-info', fondCouleur: 'bg-info/10' },
  PAIEMENT_RECU: { icone: Banknote, couleur: 'text-success', fondCouleur: 'bg-success/10' },
  FACTURE_EMISE: { icone: Banknote, couleur: 'text-success', fondCouleur: 'bg-success/10' },
  CONTRAT_TRAVAIL_DEPOSE: { icone: FileSignature, couleur: 'text-violet-600', fondCouleur: 'bg-violet-500/10' },
  CONTRAT_A_SIGNER: { icone: FileSignature, couleur: 'text-violet-600', fondCouleur: 'bg-violet-500/10' },
  POINTAGE: { icone: MapPin, couleur: 'text-warning', fondCouleur: 'bg-warning/10' },
  RAPPEL_J1_MISSION: { icone: MapPin, couleur: 'text-warning', fondCouleur: 'bg-warning/10' },
  MESSAGERIE: { icone: MessageCircle, couleur: 'text-cyan-600', fondCouleur: 'bg-cyan-500/10' },
  NOTATION_RAPPEL: { icone: Star, couleur: 'text-yellow-600', fondCouleur: 'bg-yellow-500/10' },
  LITIGE_OUVERT: { icone: AlertTriangle, couleur: 'text-warning', fondCouleur: 'bg-warning/10' },
  LITIGE_RESOLU: { icone: Info, couleur: 'text-success', fondCouleur: 'bg-success/10' },
  SERIE_ONBOARDING: { icone: Info, couleur: 'text-info', fondCouleur: 'bg-info/10' },
};

const DEFAUT: IconeNotifInfo = {
  icone: Bell,
  couleur: 'text-muted-foreground',
  fondCouleur: 'bg-muted',
};

export function getIconeNotification(typeEvenement: string | null | undefined): IconeNotifInfo {
  if (!typeEvenement) return DEFAUT;
  return MAP[typeEvenement] || DEFAUT;
}

import React from 'react';
import { ShieldCheck, HelpCircle } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';

interface Props {
  score: number | null | undefined;
  totalMissionsTerminees?: number | null;
  /** Affichage compact (badge inline) ou large (avec icône) */
  variant?: 'badge' | 'inline' | 'jauge';
  /** Si true, masque le tooltip (utile dans listes très denses) */
  noTooltip?: boolean;
}

const SEUIL_MISSIONS = 3;

/**
 * Affichage uniforme du score fiabilité.
 *
 * Règle J5.F : Score affiché uniquement si total_missions_terminees >= 3.
 * Sinon "Non noté" avec tooltip explicatif.
 *
 * Cohérent avec les RPCs DB qui retournent NULL au-dessous du seuil.
 */
export function ScoreFiabilite({ score, totalMissionsTerminees, variant = 'badge', noTooltip }: Props) {
  // Si la RPC nous renvoie déjà NULL, le score est masqué côté serveur (safe).
  // On garde la double condition pour le cas où le composant est appelé avec
  // les deux valeurs (rétrocompat avec l'existant qui passait score brut + count).
  const masque =
    score == null
    || (totalMissionsTerminees != null && totalMissionsTerminees < SEUIL_MISSIONS);

  const tooltipMsg = `Score disponible après ${SEUIL_MISSIONS} missions terminées`;

  if (masque) {
    if (variant === 'jauge') {
      return (
        <div className="text-center">
          <p className="text-sm font-medium text-foreground">Pas encore d'évaluation</p>
          <p className="text-xs text-muted-foreground mt-0.5">{tooltipMsg}</p>
        </div>
      );
    }
    const content = (
      <span className="inline-flex items-center gap-1 rounded-full bg-muted text-muted-foreground px-2 py-0.5 text-[10px] font-medium">
        Non noté
        {!noTooltip && <HelpCircle className="h-3 w-3" />}
      </span>
    );
    if (noTooltip) return content;
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>{content}</TooltipTrigger>
          <TooltipContent side="top" className="text-xs">{tooltipMsg}</TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  const num = Math.round(Number(score));
  if (variant === 'inline') {
    return (
      <span className="inline-flex items-center gap-1 text-primary font-semibold">
        <ShieldCheck className="h-3.5 w-3.5" /> {num}/100
      </span>
    );
  }
  if (variant === 'jauge') {
    return <span className="font-bold text-foreground">{num}/100</span>;
  }
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary px-2 py-0.5 text-[10px] font-semibold">
      <ShieldCheck className="h-3 w-3" /> {num}/100
    </span>
  );
}

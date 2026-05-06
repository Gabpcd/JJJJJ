import React from 'react';

type Niveau = 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE';

interface Props {
  niveau?: Niveau | null;
  /** Pour <3 missions terminées : afficher "Non noté" */
  nonNote?: boolean;
  compact?: boolean;
}

/**
 * BadgeNiveauV2 — 4 niveaux Bronze/Argent/Or/Platine, sens correct (Bronze=bas, Platine=haut).
 *
 * Aligné sur fn_calculer_score_fiabilite_v2 :
 *   <50 BRONZE / 50-69 ARGENT / 70-89 OR / >=90 PLATINE
 *
 * Cohérent avec niveaux étabs (fn_calculer_score_etablissement) — même mapping seuils.
 *
 * Remplace progressivement BadgeNiveau (5 niveaux Diamant/Platine/Or/Argent/Bronze, déprécié 2026-07).
 */
const STYLES: Record<Niveau, { label: string; classes: string; emoji: string }> = {
  BRONZE: { label: 'Bronze', classes: 'bg-gradient-to-r from-amber-100 to-orange-100 text-amber-900 border-amber-300', emoji: '🥉' },
  ARGENT: { label: 'Argent', classes: 'bg-gradient-to-r from-slate-100 to-slate-200 text-slate-800 border-slate-300', emoji: '🥈' },
  OR: { label: 'Or', classes: 'bg-gradient-to-r from-yellow-100 to-amber-200 text-yellow-900 border-yellow-300', emoji: '🥇' },
  PLATINE: { label: 'Platine', classes: 'bg-gradient-to-r from-emerald-100 via-cyan-100 to-violet-100 text-emerald-900 border-emerald-300 animate-shimmer', emoji: '💎' },
};

export function BadgeNiveauV2({ niveau, nonNote, compact }: Props) {
  if (nonNote || !niveau) {
    return (
      <span
        className={`inline-flex items-center border rounded-full font-semibold bg-muted text-muted-foreground border-border ${compact ? 'px-2 py-0.5 text-[10px]' : 'px-3 py-1 text-xs'}`}
        title="Score disponible après 3 missions terminées"
      >
        Non noté
      </span>
    );
  }

  const s = STYLES[niveau];
  return (
    <span className={`inline-flex items-center border rounded-full font-semibold ${compact ? 'px-2 py-0.5 text-[10px]' : 'px-3 py-1 text-xs'} ${s.classes}`}>
      {s.emoji} {s.label}
    </span>
  );
}

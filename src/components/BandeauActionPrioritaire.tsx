import { BoutonY2K } from '@/components/y2k/BoutonY2K';

/* Bandeau « À faire maintenant » — hiérarchisation des pages de détail mission.
   Affiche LA prochaine action attendue de l'utilisateur (une seule, la plus
   prioritaire) en tête de page, avec un CTA qui scrolle vers le bloc concerné
   (mis en surbrillance 2 s) ou déclenche directement l'action. */

export interface ActionPrioritaire {
  titre: string;
  description?: string;
  cta: string;
  /** id de l'élément cible — scroll + surbrillance. Ignoré si onClick fourni. */
  cibleId?: string;
  onClick?: () => void;
  variante?: 'primary' | 'warning' | 'destructive';
}

const BORDURES: Record<NonNullable<ActionPrioritaire['variante']>, string> = {
  primary: 'border-primary/40',
  warning: 'border-warning/50',
  destructive: 'border-destructive/50',
};

export function BandeauActionPrioritaire({ titre, description, cta, cibleId, onClick, variante = 'primary' }: ActionPrioritaire) {
  const aller = () => {
    if (onClick) { onClick(); return; }
    const el = cibleId ? document.getElementById(cibleId) : null;
    if (!el) return;
    // Scroll vers section (autorisé — pas un focus input, cf. CLAUDE.md Safari iOS)
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.classList.add('ring-2', 'ring-primary', 'rounded-xl', 'transition-shadow');
    setTimeout(() => el.classList.remove('ring-2', 'ring-primary'), 2000);
  };

  return (
    <div className={`card-base border-2 ${BORDURES[variante]} bg-gradient-soft mb-4 flex items-center justify-between gap-3 flex-wrap`}>
      <div className="min-w-0 flex-1">
        <p className="text-[10px] font-bold uppercase tracking-wide text-primary">→ À faire maintenant</p>
        <p className="text-sm font-semibold text-foreground mt-0.5">{titre}</p>
        {description && <p className="text-xs text-muted-foreground mt-0.5">{description}</p>}
      </div>
      <BoutonY2K size="sm" onClick={aller} className="shrink-0">
        {cta}
      </BoutonY2K>
    </div>
  );
}

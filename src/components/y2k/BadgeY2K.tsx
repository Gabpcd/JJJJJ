/**
 * BadgeY2K — Sprint 9-B PR 4
 *
 * Badge Y2K Gen Z avec 5 variants sémantiques :
 *  - success  : jolene-cyan (réussite, état vert)
 *  - warning  : jolene-butter (avertissement bienveillant)
 *  - error    : destructive (erreur, palette existante)
 *  - info     : jolene-mauve (information)
 *  - premium  : gradient holographique (récompense, achievement)
 *
 * Petits badges arrondis avec optionnellement icône à gauche.
 *
 * Usage :
 *   <BadgeY2K variant="premium" icone={<Star />}>Niveau PLATINE</BadgeY2K>
 */
import { HTMLAttributes } from 'react';
import { useAdminInterface } from '@/contexts/AdminInterfaceContext';
import { cn } from '@/lib/utils';

type Variant = 'success' | 'warning' | 'error' | 'info' | 'premium';
type Taille = 'sm' | 'md';

interface Props extends HTMLAttributes<HTMLSpanElement> {
  variant?: Variant;
  size?: Taille;
  icone?: React.ReactNode;
}

const TAILLES: Record<Taille, string> = {
  sm: 'text-[10px] px-2 py-0.5',
  md: 'text-xs px-2.5 py-1',
};

const VARIANTS: Record<Variant, string> = {
  success: cn(
    'bg-jolene-cyan-100 text-jolene-cyan-800',
    'border border-jolene-cyan-300',
  ),
  warning: cn(
    'bg-jolene-butter-100 text-jolene-butter-800',
    'border border-jolene-butter-400',
  ),
  error: cn(
    'bg-destructive/10 text-destructive',
    'border border-destructive/30',
    // Le rouge de la palette sombre est volontairement vif. Sur son fond
    // translucide, il ne passe toutefois pas le contraste AA pour un petit
    // libellé : on éclaircit explicitement le texte dans ce contexte.
    'dark:bg-destructive/20 dark:text-red-100 dark:border-destructive/50',
  ),
  info: cn(
    'bg-jolene-mauve-100 text-jolene-mauve-800',
    'border border-jolene-mauve-300',
  ),
  premium: cn(
    'bg-gradient-celebrate text-white font-semibold',
    'border border-white/30',
    'shadow-[0_2px_8px_hsl(var(--jolene-rose)/0.3)]',
  ),
};

export function BadgeY2K({ variant = 'info', size = 'md', icone, className, children, ...rest }: Props) {
  const admin = useAdminInterface();
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 font-medium whitespace-nowrap',
        admin ? 'rounded-md shadow-none' : 'rounded-full',
        TAILLES[size],
        admin && variant === 'premium'
          ? 'border border-primary/25 bg-primary/10 text-primary'
          : VARIANTS[variant],
        className,
      )}
      {...rest}
    >
      {icone && <span className="shrink-0 inline-flex items-center" aria-hidden="true">{icone}</span>}
      {children}
    </span>
  );
}

export default BadgeY2K;

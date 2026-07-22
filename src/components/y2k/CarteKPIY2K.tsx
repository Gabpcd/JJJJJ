/**
 * CarteKPIY2K — Sprint 9-C PR 1
 *
 * Carte KPI Y2K Gen Z avec dégradé optionnel, icône, valeur grande tabular,
 * variation (delta % ou flèche).
 *
 * Variants :
 *  - default     : surface cloud + border rose subtile
 *  - holographic : background gradient hero (texte blanc)
 *  - soft        : background gradient soft (lavender → rose pâle)
 *
 * Usage :
 *   <CarteKPIY2K
 *     icone={<Briefcase />}
 *     label="Missions ce mois"
 *     valeur={12}
 *     variation={{ pct: 25, sens: 'up' }}
 *     variant="default"
 *   />
 */
import { HTMLAttributes } from 'react';
import { ArrowDown, ArrowUp, Minus } from 'lucide-react';
import { useAdminInterface } from '@/contexts/AdminInterfaceContext';
import { cn } from '@/lib/utils';

type Variant = 'default' | 'holographic' | 'soft';

interface Props extends Omit<HTMLAttributes<HTMLDivElement>, 'children'> {
  /** Label sous la valeur (ex. "Missions ce mois") */
  label: string;
  /** Valeur principale (number ou string formatée comme "1 250 €") */
  valeur: number | string;
  /** Icône optionnelle à gauche du label (lucide ou autre) */
  icone?: React.ReactNode;
  /** Variation : delta pct + sens (up = positive, down = negative, neutral = flat) */
  variation?: {
    pct?: number;
    sens?: 'up' | 'down' | 'neutral';
    label?: string;
  };
  /** Sous-texte optionnel (ex. "vs mois dernier") */
  contexte?: string;
  variant?: Variant;
  onClick?: () => void;
}

const VARIANTS: Record<Variant, string> = {
  default: cn(
    'bg-jolene-cloud',
    'border-2 border-jolene-rose-200',
    'shadow-[0_4px_24px_hsl(var(--jolene-rose)/0.08)]',
  ),
  holographic: cn(
    'text-white',
    'bg-gradient-hero',
    'border-2 border-white/30',
    'shadow-holographic',
  ),
  soft: cn(
    'text-jolene-midnight',
    'bg-gradient-soft',
    'border-2 border-jolene-mauve-200',
  ),
};

const ADMIN_VARIANTS: Record<Variant, string> = {
  default: 'border border-border bg-card text-foreground shadow-sm',
  holographic: 'border border-primary/25 bg-primary/[0.04] text-foreground shadow-sm',
  soft: 'border border-border bg-muted/30 text-foreground shadow-sm',
};

const SENS_STYLES: Record<NonNullable<NonNullable<Props['variation']>['sens']>, { icone: typeof ArrowUp; color: string }> = {
  up: { icone: ArrowUp, color: 'text-jolene-cyan-700' },
  down: { icone: ArrowDown, color: 'text-destructive' },
  neutral: { icone: Minus, color: 'text-jolene-bubblegum' },
};

export function CarteKPIY2K({
  label,
  valeur,
  icone,
  variation,
  contexte,
  variant = 'default',
  onClick,
  className,
  ...rest
}: Props) {
  const admin = useAdminInterface();
  const sens = variation?.sens ?? 'neutral';
  const SensIcone = SENS_STYLES[sens].icone;
  const sensColor = !admin && variant === 'holographic' ? 'text-white/90' : SENS_STYLES[sens].color;
  const Component = onClick ? 'button' : 'div';

  return (
    <Component
      type={onClick ? 'button' : undefined}
      onClick={onClick}
      className={cn(
        // Sprint 12-D : transition-bouncy (cubic-bezier overshoot doux) pour KPIs cliquables.
        // prefers-reduced-motion géré dans .transition-bouncy (src/index.css).
        admin ? 'rounded-xl p-3 text-left transition-colors' : 'rounded-2xl md:rounded-3xl p-4 md:p-5 text-left transition-bouncy',
        onClick && (admin ? 'cursor-pointer hover:border-primary/35' : 'hover:-translate-y-1 hover:shadow-holographic motion-reduce:hover:translate-y-0 cursor-pointer'),
        onClick && 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-jolene-rose focus-visible:ring-offset-2',
        admin ? ADMIN_VARIANTS[variant] : VARIANTS[variant],
        className,
      )}
      {...(rest as any)}
    >
      <div className="flex items-center gap-2 mb-2">
        {icone && (
          <span
            className={cn(
              'inline-flex items-center justify-center',
              admin ? 'rounded-lg bg-muted p-1.5 text-muted-foreground' : 'rounded-xl p-2',
              !admin && (variant === 'holographic' ? 'bg-white/20' : 'bg-jolene-rose-100 text-jolene-rose-700'),
            )}
            aria-hidden="true"
          >
            {icone}
          </span>
        )}
        <span
          className={cn(
            'text-xs font-medium',
            admin ? 'text-muted-foreground' : variant === 'holographic' ? 'text-white/90' : 'text-jolene-bubblegum',
          )}
        >
          {label}
        </span>
      </div>

      <p
        className={cn(
          admin ? 'text-2xl font-semibold tabular-nums leading-tight text-foreground' : 'text-2xl md:text-3xl font-bold tabular-nums leading-tight',
          !admin && (variant === 'holographic' ? 'text-white' : 'text-jolene-midnight'),
        )}
      >
        {valeur}
      </p>

      {(variation || contexte) && (
        <div className="mt-2 flex items-center gap-2 text-xs">
          {variation && (
            <span className={cn('inline-flex items-center gap-0.5 font-semibold', sensColor)}>
              <SensIcone className="h-3.5 w-3.5" aria-hidden="true" />
              {variation.pct != null && (
                <span>
                  {variation.pct > 0 ? '+' : ''}
                  {variation.pct}%
                </span>
              )}
              {variation.label && <span>{variation.label}</span>}
            </span>
          )}
          {contexte && (
            <span
              className={cn(
                admin ? 'text-muted-foreground' : variant === 'holographic' ? 'text-white/70' : 'text-jolene-bubblegum',
              )}
            >
              {contexte}
            </span>
          )}
        </div>
      )}
    </Component>
  );
}

export default CarteKPIY2K;

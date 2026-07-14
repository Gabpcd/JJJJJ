/**
 * BoutonY2K — Sprint 9-B PR 2
 *
 * Bouton Y2K Gen Z signature avec dégradés holographiques + hover scale.
 * Variants :
 *  - primary     : gradient rose→mauve, shadow holographique, hover scale
 *  - secondary   : surface neutre, border rose subtile
 *  - ghost       : transparent, hover bg-soft
 *  - destructive : gradient rouge→rose holographique pour actions irréversibles
 *
 * Touch targets 44px min (mobile-first). `prefers-reduced-motion` respecté.
 *
 * Usage :
 *   <BoutonY2K variant="primary" size="lg" onClick={...}>
 *     Continuer
 *   </BoutonY2K>
 */
import { ButtonHTMLAttributes, forwardRef } from 'react';
import { cn } from '@/lib/utils';

type Variant = 'primary' | 'secondary' | 'ghost' | 'destructive';
type Taille = 'sm' | 'md' | 'lg';

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Taille;
  /** Affiche un état chargement avec spinner */
  loading?: boolean;
  /** Icône à gauche du label */
  iconeGauche?: React.ReactNode;
  /** Icône à droite du label */
  iconeDroite?: React.ReactNode;
}

const TAILLES: Record<Taille, string> = {
  sm: 'min-h-[44px] px-3 py-1.5 text-xs',
  md: 'min-h-[44px] px-5 py-2.5 text-sm',
  lg: 'min-h-[52px] px-7 py-3 text-base',
};

const VARIANTS: Record<Variant, string> = {
  primary: cn(
    'text-white font-semibold',
    'bg-gradient-hero shadow-holographic',
    'hover:scale-[1.03] active:scale-[0.98]',
    'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
    'focus-visible:ring-2 focus-visible:ring-jolene-rose focus-visible:ring-offset-2',
  ),
  secondary: cn(
    'text-jolene-midnight font-semibold',
    'bg-jolene-cloud border-2 border-jolene-rose-300',
    'hover:bg-jolene-rose-50 hover:border-jolene-rose-500',
    'active:scale-[0.98] motion-reduce:active:scale-100',
    'focus-visible:ring-2 focus-visible:ring-jolene-rose focus-visible:ring-offset-2',
  ),
  ghost: cn(
    'text-jolene-rose-700 font-medium',
    'bg-transparent',
    'hover:bg-jolene-rose-50',
    'active:scale-[0.98] motion-reduce:active:scale-100',
    'focus-visible:ring-2 focus-visible:ring-jolene-rose focus-visible:ring-offset-2',
  ),
  destructive: cn(
    'text-white font-semibold',
    'bg-gradient-to-br from-[#FF4D6B] to-[#FF6BBE] shadow-[0_8px_24px_-4px_rgba(255,77,107,0.45)]',
    'hover:scale-[1.03] hover:shadow-[0_12px_32px_-4px_rgba(255,77,107,0.6)] active:scale-[0.98]',
    'motion-reduce:hover:scale-100 motion-reduce:active:scale-100',
    'focus-visible:ring-2 focus-visible:ring-[#FF4D6B] focus-visible:ring-offset-2',
  ),
};

export const BoutonY2K = forwardRef<HTMLButtonElement, Props>(function BoutonY2K(
  { variant = 'primary', size = 'md', loading, iconeGauche, iconeDroite, className, children, disabled, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={rest.type ?? 'button'}
      disabled={disabled || loading}
      className={cn(
        'inline-flex items-center justify-center gap-2 rounded-2xl',
        // Sprint 12-D : transition-snap (cubic-bezier overshoot court) pour boutons.
        // prefers-reduced-motion géré dans .transition-snap (src/index.css).
        'transition-snap',
        'disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100',
        TAILLES[size],
        VARIANTS[variant],
        className,
      )}
      {...rest}
    >
      {loading ? (
        <Spinner />
      ) : (
        iconeGauche && <span className="shrink-0">{iconeGauche}</span>
      )}
      <span>{children}</span>
      {!loading && iconeDroite && <span className="shrink-0">{iconeDroite}</span>}
    </button>
  );
});

function Spinner() {
  return (
    <svg
      className="h-4 w-4 animate-spin shrink-0"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
    </svg>
  );
}

export default BoutonY2K;

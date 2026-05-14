/**
 * CardY2K — Sprint 9-B PR 3
 *
 * Card Y2K Gen Z avec 3 variants :
 *  - default      : surface jolene-cloud + border subtile rose
 *  - holographic  : background dégradé holographique animé (titres/heros)
 *  - glass        : glassmorphism (backdrop-blur + bg semi-transparent)
 *
 * Border-radius généreuse (rounded-3xl), shadow Y2K, hover lift subtle.
 * `prefers-reduced-motion` respecté.
 *
 * Usage :
 *   <CardY2K variant="glass" className="p-6">
 *     <h2>Bienvenue</h2>
 *     <p>...</p>
 *   </CardY2K>
 */
import { HTMLAttributes, forwardRef } from 'react';
import { cn } from '@/lib/utils';

type Variant = 'default' | 'holographic' | 'glass';

interface Props extends HTMLAttributes<HTMLDivElement> {
  variant?: Variant;
  /** Si true (défaut), hover lift effect */
  hoverLift?: boolean;
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
  glass: cn(
    'bg-jolene-cloud/75 backdrop-blur-xl',
    'border border-white/40',
    'shadow-[0_8px_32px_hsl(var(--jolene-mauve)/0.15)]',
  ),
};

export const CardY2K = forwardRef<HTMLDivElement, Props>(function CardY2K(
  { variant = 'default', hoverLift = true, className, children, ...rest },
  ref,
) {
  return (
    <div
      ref={ref}
      className={cn(
        'rounded-3xl p-5',
        'transition-all duration-300 motion-reduce:transition-none',
        hoverLift && 'hover:-translate-y-1 hover:shadow-holographic motion-reduce:hover:translate-y-0',
        VARIANTS[variant],
        className,
      )}
      {...rest}
    >
      {children}
    </div>
  );
});

export default CardY2K;

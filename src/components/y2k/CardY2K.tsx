/**
 * CardY2K — Sprint 9-B PR 3 + Sprint 12-F (sous-composants drop-in shadcn)
 *
 * Card Y2K Gen Z avec 3 variants :
 *  - default      : surface jolene-cloud + border subtile rose
 *  - holographic  : background dégradé holographique animé (titres/heros)
 *  - glass        : glassmorphism (backdrop-blur + bg semi-transparent)
 *
 * Border-radius généreuse (rounded-3xl), shadow Y2K, hover lift subtle.
 * `prefers-reduced-motion` respecté.
 *
 * Usage simple :
 *   <CardY2K variant="glass" className="p-6">
 *     <h2>Bienvenue</h2>
 *   </CardY2K>
 *
 * Usage avec sous-composants (drop-in shadcn) — Sprint 12-F :
 *   <CardY2K>
 *     <CardY2KHeader>
 *       <CardY2KTitle>Titre</CardY2KTitle>
 *       <CardY2KDescription>Sous-titre</CardY2KDescription>
 *     </CardY2KHeader>
 *     <CardY2KContent>Contenu</CardY2KContent>
 *     <CardY2KFooter>Actions</CardY2KFooter>
 *   </CardY2K>
 *
 * Note Sprint 12-F : si des sous-composants sont utilisés, le padding par défaut
 * du wrapper CardY2K (`p-5`) DOIT être désactivé via `noPadding` pour éviter
 * le double padding (sous-composants ont leur propre `p-6`).
 */
import { HTMLAttributes, KeyboardEvent, forwardRef } from 'react';
import { useAdminInterface } from '@/contexts/AdminInterfaceContext';
import { cn } from '@/lib/utils';

type Variant = 'default' | 'holographic' | 'glass';

interface Props extends HTMLAttributes<HTMLDivElement> {
  variant?: Variant;
  /** Si true (défaut), hover lift effect */
  hoverLift?: boolean;
  /** Si true, désactive le padding par défaut `p-5` (à utiliser avec les sous-composants CardY2KHeader/Content/Footer qui apportent leur propre padding). */
  noPadding?: boolean;
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

const ADMIN_VARIANTS: Record<Variant, string> = {
  default: 'border border-border bg-card text-foreground shadow-sm',
  holographic: 'border border-primary/25 bg-primary/[0.04] text-foreground shadow-sm',
  glass: 'border border-border bg-card/95 text-foreground shadow-sm',
};

export const CardY2K = forwardRef<HTMLDivElement, Props>(function CardY2K(
  {
    variant = 'default',
    hoverLift = true,
    noPadding = false,
    className,
    children,
    onClick,
    onKeyDown,
    role,
    tabIndex,
    ...rest
  },
  ref,
) {
  const admin = useAdminInterface();
  const estInteractive = Boolean(onClick);

  const gererClavier = (event: KeyboardEvent<HTMLDivElement>) => {
    onKeyDown?.(event);
    if (event.defaultPrevented || !estInteractive) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      event.currentTarget.click();
    }
  };

  return (
    <div
      ref={ref}
      role={role ?? (estInteractive ? 'button' : undefined)}
      tabIndex={tabIndex ?? (estInteractive ? 0 : undefined)}
      onClick={onClick}
      onKeyDown={gererClavier}
      className={cn(
        admin ? 'rounded-xl' : 'rounded-3xl',
        !noPadding && (admin ? 'p-4' : 'p-5'),
        // Sprint 12-D : transition-bouncy (cubic-bezier overshoot doux) pour cards.
        // prefers-reduced-motion géré dans .transition-bouncy (src/index.css).
        admin ? 'transition-colors' : 'transition-bouncy',
        hoverLift && (admin
          ? 'hover:border-primary/30'
          : 'hover:-translate-y-1 hover:shadow-holographic motion-reduce:hover:translate-y-0'),
        estInteractive && 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2',
        admin ? ADMIN_VARIANTS[variant] : VARIANTS[variant],
        className,
      )}
      {...rest}
    >
      {children}
    </div>
  );
});

/* ─── Sous-composants drop-in shadcn (Sprint 12-F) ────────────────────────── */

export const CardY2KHeader = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  function CardY2KHeader({ className, ...rest }, ref) {
    const admin = useAdminInterface();
    return <div ref={ref} className={cn('flex flex-col space-y-1.5', admin ? 'p-4' : 'p-6', className)} {...rest} />;
  },
);

export const CardY2KTitle = forwardRef<HTMLHeadingElement, HTMLAttributes<HTMLHeadingElement>>(
  function CardY2KTitle({ className, ...rest }, ref) {
    const admin = useAdminInterface();
    return (
      <h3
        ref={ref}
        className={cn(admin ? 'text-base font-semibold leading-snug' : 'text-2xl font-semibold leading-none tracking-tight', className)}
        {...rest}
      />
    );
  },
);

export const CardY2KDescription = forwardRef<HTMLParagraphElement, HTMLAttributes<HTMLParagraphElement>>(
  function CardY2KDescription({ className, ...rest }, ref) {
    const admin = useAdminInterface();
    return <p ref={ref} className={cn('text-sm', admin ? 'text-muted-foreground' : 'text-jolene-bubblegum', className)} {...rest} />;
  },
);

export const CardY2KContent = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  function CardY2KContent({ className, ...rest }, ref) {
    const admin = useAdminInterface();
    return <div ref={ref} className={cn(admin ? 'p-4 pt-0' : 'p-6 pt-0', className)} {...rest} />;
  },
);

export const CardY2KFooter = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  function CardY2KFooter({ className, ...rest }, ref) {
    const admin = useAdminInterface();
    return <div ref={ref} className={cn('flex items-center', admin ? 'p-4 pt-0' : 'p-6 pt-0', className)} {...rest} />;
  },
);

export default CardY2K;

/**
 * `<DialogResponsive />` Sprint 8 BIS PR 1 (chantier 3.1).
 *
 * Wrap @radix-ui/react-dialog avec rendu fullscreen mobile / centered desktop.
 *
 * Usage :
 *   <DialogResponsive open={open} onOpenChange={setOpen}>
 *     <DialogResponsiveContent maxWidth="lg">
 *       <DialogResponsiveHeader>
 *         <DialogResponsiveTitle>Titre</DialogResponsiveTitle>
 *         <DialogResponsiveDescription>Description optionnelle</DialogResponsiveDescription>
 *       </DialogResponsiveHeader>
 *       <DialogResponsiveBody>...</DialogResponsiveBody>
 *       <DialogResponsiveFooter>
 *         <Button onClick={() => setOpen(false)}>Annuler</Button>
 *         <Button onClick={confirmer}>Confirmer</Button>
 *       </DialogResponsiveFooter>
 *     </DialogResponsiveContent>
 *   </DialogResponsive>
 *
 * Mobile (< 768px) : fullscreen avec header sticky + footer sticky + scroll interne body.
 * Desktop (>= 768px) : modal centered max-w configurable.
 */
import * as React from 'react';
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { cn } from '@/lib/utils';

const DialogResponsive = DialogPrimitive.Root;
const DialogResponsiveTrigger = DialogPrimitive.Trigger;
const DialogResponsiveClose = DialogPrimitive.Close;
const DialogResponsivePortal = DialogPrimitive.Portal;

const DialogResponsiveOverlay = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Overlay>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      // Sprint 9-D : glassmorphism subtle (dégradé jolene-midnight semi-transparent + backdrop-blur)
      'fixed inset-0 z-50 bg-jolene-midnight/40 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0',
      className,
    )}
    {...props}
  />
));
DialogResponsiveOverlay.displayName = 'DialogResponsiveOverlay';

type ContentProps = React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content> & {
  /** max-width desktop (defaut: lg = 32rem) */
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | '2xl';
};

const MAX_WIDTH_CLASS: Record<NonNullable<ContentProps['maxWidth']>, string> = {
  sm: 'md:max-w-sm',
  md: 'md:max-w-md',
  lg: 'md:max-w-lg',
  xl: 'md:max-w-xl',
  '2xl': 'md:max-w-2xl',
};

const DialogResponsiveContent = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Content>,
  ContentProps
>(({ className, maxWidth = 'lg', children, ...props }, ref) => (
  <DialogResponsivePortal>
    <DialogResponsiveOverlay />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        // Mobile (< md) : fullscreen
        'fixed inset-0 z-50 flex flex-col bg-background',
        'data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom-4 data-[state=open]:fade-in-0',
        'data-[state=closed]:animate-out data-[state=closed]:slide-out-to-bottom-4 data-[state=closed]:fade-out-0',
        // Desktop (>= md) : centered modal Y2K avec border subtle + shadow holographique
        'md:inset-auto md:top-1/2 md:left-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:rounded-3xl md:max-h-[85vh]',
        'md:border md:border-jolene-rose-200/60 md:shadow-holographic',
        MAX_WIDTH_CLASS[maxWidth],
        'duration-200',
        className,
      )}
      {...props}
    >
      {children}
    </DialogPrimitive.Content>
  </DialogResponsivePortal>
));
DialogResponsiveContent.displayName = 'DialogResponsiveContent';

const DialogResponsiveHeader = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, children, ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      // Sticky en mobile (fullscreen), normal en desktop
      'flex items-start justify-between gap-4 border-b border-border px-4 py-3 md:px-6 md:py-4',
      'sticky top-0 z-10 bg-background md:static',
      'pt-[calc(0.75rem+env(safe-area-inset-top))] md:pt-4',
      className,
    )}
    {...props}
  >
    <div className="flex-1 min-w-0">{children}</div>
    <DialogPrimitive.Close
      aria-label="Fermer"
      className="rounded-lg p-1 text-muted-foreground hover:text-foreground hover:bg-muted focus:outline-none focus-visible:ring-2 focus-visible:ring-primary min-h-[32px] min-w-[32px] flex items-center justify-center"
    >
      <X className="h-4 w-4" aria-hidden="true" />
    </DialogPrimitive.Close>
  </div>
));
DialogResponsiveHeader.displayName = 'DialogResponsiveHeader';

const DialogResponsiveTitle = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Title>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Title>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Title
    ref={ref}
    className={cn('text-base md:text-lg font-semibold text-foreground', className)}
    {...props}
  />
));
DialogResponsiveTitle.displayName = 'DialogResponsiveTitle';

const DialogResponsiveDescription = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Description>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Description>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Description
    ref={ref}
    className={cn('text-sm text-muted-foreground mt-1', className)}
    {...props}
  />
));
DialogResponsiveDescription.displayName = 'DialogResponsiveDescription';

const DialogResponsiveBody = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    // overscroll-contain (Lot 6b.2) : le scroll interne de la sheet ne doit
    // jamais partir en scroll chaining sur la page derrière (iOS Safari).
    className={cn('flex-1 overflow-y-auto overscroll-contain px-4 py-4 md:px-6 md:py-5', className)}
    {...props}
  />
));
DialogResponsiveBody.displayName = 'DialogResponsiveBody';

const DialogResponsiveFooter = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, children, ...props }, ref) => (
  <div
    ref={ref}
    className={cn(
      'flex flex-col-reverse sm:flex-row gap-2 sm:justify-end',
      'border-t border-border px-4 py-3 md:px-6 md:py-4',
      // Sticky en mobile fullscreen avec safe-area-inset-bottom
      'sticky bottom-0 z-10 bg-background md:static',
      'pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:pb-4',
      className,
    )}
    {...props}
  >
    {children}
  </div>
));
DialogResponsiveFooter.displayName = 'DialogResponsiveFooter';

export {
  DialogResponsive,
  DialogResponsiveTrigger,
  DialogResponsiveClose,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
};

import { useState, type ReactNode } from 'react';
import { ChevronDown, SlidersHorizontal } from 'lucide-react';
import { cn } from '@/lib/utils';

interface AdminFilterBarProps {
  children: ReactNode;
  advanced?: ReactNode;
  actions?: ReactNode;
  advancedLabel?: string;
  advancedActiveCount?: number;
  onResetAdvanced?: () => void;
  defaultAdvancedOpen?: boolean;
  ariaLabel?: string;
  className?: string;
}

export function AdminFilterBar({
  children,
  advanced,
  actions,
  advancedLabel = 'Filtres avancés',
  advancedActiveCount = 0,
  onResetAdvanced,
  defaultAdvancedOpen = false,
  ariaLabel = 'Filtres',
  className,
}: AdminFilterBarProps) {
  const [advancedOpen, setAdvancedOpen] = useState(defaultAdvancedOpen);

  return (
    <section
      aria-label={ariaLabel}
      className={cn('overflow-hidden rounded-xl border border-border bg-card', className)}
    >
      <div className="flex flex-col gap-3 p-3 sm:flex-row sm:items-end">
        <div className="flex min-w-0 flex-1 flex-wrap items-end gap-3">{children}</div>
        {actions ? (
          <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>
        ) : null}
      </div>

      {advanced != null ? (
        <details
          className="group border-t border-border"
          open={advancedOpen}
          onToggle={(event) => setAdvancedOpen(event.currentTarget.open)}
        >
          <summary className="flex min-h-[44px] cursor-pointer list-none items-center gap-2 px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary [&::-webkit-details-marker]:hidden">
            <SlidersHorizontal className="h-4 w-4" aria-hidden="true" />
            <span>{advancedLabel}</span>
            {advancedActiveCount > 0 ? (
              <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary">
                {advancedActiveCount} actif{advancedActiveCount > 1 ? 's' : ''}
              </span>
            ) : null}
            <ChevronDown
              className="ml-auto h-4 w-4 transition-transform group-open:rotate-180 motion-reduce:transition-none"
              aria-hidden="true"
            />
          </summary>
          <div className="flex flex-wrap items-end gap-3 border-t border-border bg-muted/20 p-3">
            <div className="flex min-w-0 flex-1 flex-wrap items-end gap-3">{advanced}</div>
            {advancedActiveCount > 0 && onResetAdvanced ? (
              <button
                type="button"
                onClick={onResetAdvanced}
                className="min-h-10 rounded-lg px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              >
                Réinitialiser
              </button>
            ) : null}
          </div>
        </details>
      ) : null}
    </section>
  );
}

import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export type AdminSummaryTone = 'default' | 'primary' | 'success' | 'warning' | 'danger';

export interface AdminSummaryItem {
  id: string;
  label: ReactNode;
  value: ReactNode;
  detail?: ReactNode;
  icon?: ReactNode;
  tone?: AdminSummaryTone;
}

interface AdminSummaryStripProps {
  items: readonly AdminSummaryItem[];
  ariaLabel?: string;
  className?: string;
}

const VALUE_TONE: Record<AdminSummaryTone, string> = {
  default: 'text-foreground',
  primary: 'text-primary',
  success: 'text-emerald-700 dark:text-emerald-400',
  warning: 'text-amber-700 dark:text-amber-400',
  danger: 'text-destructive',
};

export function AdminSummaryStrip({
  items,
  ariaLabel = 'Résumé',
  className,
}: AdminSummaryStripProps) {
  if (items.length === 0) return null;

  return (
    <section
      aria-label={ariaLabel}
      className={cn('overflow-hidden rounded-xl border border-border bg-border', className)}
    >
      <dl className="grid grid-cols-1 gap-px sm:[grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))]">
        {items.map((item) => {
          const tone = item.tone ?? 'default';
          return (
            <div key={item.id} className="min-w-0 bg-card p-4">
              <dt className="flex items-center gap-2 text-sm text-muted-foreground">
                {item.icon ? (
                  <span className="shrink-0" aria-hidden="true">
                    {item.icon}
                  </span>
                ) : null}
                <span className="min-w-0">{item.label}</span>
              </dt>
              <dd className={cn('mt-1 break-words text-2xl font-bold tabular-nums', VALUE_TONE[tone])}>
                {item.value}
              </dd>
              {item.detail ? (
                <dd className="mt-1 text-xs text-muted-foreground">{item.detail}</dd>
              ) : null}
            </div>
          );
        })}
      </dl>
    </section>
  );
}

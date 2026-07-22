import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

interface AdminPageHeaderProps {
  title: ReactNode;
  description?: ReactNode;
  eyebrow?: ReactNode;
  icon?: ReactNode;
  actions?: ReactNode;
  titleId?: string;
  className?: string;
}

export function AdminPageHeader({
  title,
  description,
  eyebrow,
  icon,
  actions,
  titleId,
  className,
}: AdminPageHeaderProps) {
  return (
    <header className={cn('flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between', className)}>
      <div className="min-w-0">
        {eyebrow ? (
          <div className="mb-1 text-sm font-medium text-primary">{eyebrow}</div>
        ) : null}
        <div className="flex items-center gap-2">
          {icon ? (
            <span className="shrink-0 text-primary" aria-hidden="true">
              {icon}
            </span>
          ) : null}
          <h1 id={titleId} className="text-2xl font-bold tracking-tight text-foreground">
            {title}
          </h1>
        </div>
        {description ? (
          <div className="mt-1 max-w-3xl text-sm text-muted-foreground">{description}</div>
        ) : null}
      </div>
      {actions ? (
        <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>
      ) : null}
    </header>
  );
}

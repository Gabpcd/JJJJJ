import * as React from 'react';
import { TabsList } from '@/components/ui/tabs';
import { cn } from '@/lib/utils';

type AdminTabsDisposition = 'scroll' | 'grid';
type AdminTabsColonnes = 2 | 3 | 4;

const CLASSES_COLONNES: Record<AdminTabsColonnes, string> = {
  2: 'grid-cols-2',
  3: 'grid-cols-3',
  4: 'grid-cols-4',
};

type AdminTabsListProps = React.ComponentPropsWithoutRef<typeof TabsList> & {
  /** Le scroll est le choix sûr pour des libellés longs sur mobile. */
  disposition?: AdminTabsDisposition;
  colonnes?: AdminTabsColonnes;
  containerClassName?: string;
};

/**
 * Bande d'onglets admin responsive. Radix conserve la navigation clavier et
 * les rôles ARIA ; ce wrapper évite que les libellés soient coupés en mobile.
 */
export const AdminTabsList = React.forwardRef<
  React.ElementRef<typeof TabsList>,
  AdminTabsListProps
>(function AdminTabsList(
  {
    disposition = 'scroll',
    colonnes = 2,
    containerClassName,
    className,
    ...props
  },
  ref,
) {
  const scrollable = disposition === 'scroll';

  return (
    <div
      className={cn(
        scrollable && '-mx-4 overflow-x-auto overscroll-x-contain px-4 pb-1 md:mx-0 md:px-0',
        containerClassName,
      )}
    >
      <TabsList
        ref={ref}
        className={cn(
          scrollable
            ? 'w-max min-w-full justify-start md:min-w-0'
            : `grid w-full ${CLASSES_COLONNES[colonnes]}`,
          className,
        )}
        {...props}
      />
    </div>
  );
});

AdminTabsList.displayName = 'AdminTabsList';

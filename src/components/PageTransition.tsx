import type { ReactNode } from 'react';

/** Navigation immédiate : aucune animation appliquée au cadre ni aux onglets. */
export function PageTransition({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

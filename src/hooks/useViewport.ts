/**
 * Hook `useViewport` Sprint 8 PR 5 (chantier 5.1).
 *
 * Retourne l'état du viewport pour rendu conditionnel mobile / tablette / desktop.
 *
 * Breakpoints alignés Tailwind :
 * - mobile : `< 768px`  (Tailwind `md`)
 * - tablette : `>= 768 && < 1024` (`md` à `lg`)
 * - desktop : `>= 1024px` (`lg`)
 *
 * Usage :
 *   const { estMobile, estTablette, estDesktop, largeur } = useViewport();
 *   return estMobile ? <CartesEmpilees /> : <Tableau />;
 */

import { useEffect, useState } from 'react';

type Viewport = {
  largeur: number;
  hauteur: number;
  estMobile: boolean;
  estTablette: boolean;
  estDesktop: boolean;
};

const BREAKPOINT_TABLETTE = 768;
const BREAKPOINT_DESKTOP = 1024;

function lireViewport(): Viewport {
  if (typeof window === 'undefined') {
    // SSR fallback : assume desktop
    return {
      largeur: BREAKPOINT_DESKTOP,
      hauteur: 768,
      estMobile: false,
      estTablette: false,
      estDesktop: true,
    };
  }
  const largeur = window.innerWidth;
  const hauteur = window.innerHeight;
  return {
    largeur,
    hauteur,
    estMobile: largeur < BREAKPOINT_TABLETTE,
    estTablette: largeur >= BREAKPOINT_TABLETTE && largeur < BREAKPOINT_DESKTOP,
    estDesktop: largeur >= BREAKPOINT_DESKTOP,
  };
}

export function useViewport(): Viewport {
  const [viewport, setViewport] = useState<Viewport>(lireViewport);

  useEffect(() => {
    let raf = 0;
    const onResize = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => setViewport(lireViewport()));
    };
    window.addEventListener('resize', onResize, { passive: true });
    window.addEventListener('orientationchange', onResize, { passive: true });
    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('orientationchange', onResize);
      cancelAnimationFrame(raf);
    };
  }, []);

  return viewport;
}

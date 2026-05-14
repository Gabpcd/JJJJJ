/**
 * `useScrollDirection` Sprint 8.5-A PR 1 (chantier nav admin mobile).
 *
 * Détecte la direction de scroll (up / down) avec un seuil minimum pour
 * éviter les déclenchements intempestifs au micro-scroll iOS.
 *
 * Usage typique :
 *   const direction = useScrollDirection();
 *   <header className={cn(
 *     'transition-transform duration-200',
 *     direction === 'down' ? '-translate-y-full' : 'translate-y-0',
 *   )}>...</header>
 *
 * - Au montage : direction = 'up' (header visible)
 * - Au scroll vers le bas (>10px) : direction = 'down' (header se cache)
 * - Au scroll vers le haut : direction = 'up' (header réapparaît)
 * - prefers-reduced-motion : pas de transformation côté CSS, à gérer dans le composant
 *
 * Listener `passive` pour ne pas bloquer le rendu.
 */
import { useEffect, useState } from 'react';

export type ScrollDirection = 'up' | 'down';

interface Options {
  /** Seuil de pixels avant de changer de direction (défaut 10) */
  threshold?: number;
  /** Désactive le hook (force 'up') si false (défaut true) */
  enabled?: boolean;
}

export function useScrollDirection({ threshold = 10, enabled = true }: Options = {}): ScrollDirection {
  const [direction, setDirection] = useState<ScrollDirection>('up');

  useEffect(() => {
    if (!enabled || typeof window === 'undefined') return;

    let lastY = window.scrollY;
    let ticking = false;

    const update = () => {
      const currentY = window.scrollY;
      const delta = currentY - lastY;

      if (Math.abs(delta) < threshold) {
        ticking = false;
        return;
      }

      // Toujours afficher le header en haut de page (évite le flicker initial)
      if (currentY < threshold) {
        setDirection('up');
      } else if (delta > 0) {
        setDirection('down');
      } else {
        setDirection('up');
      }

      lastY = currentY > 0 ? currentY : 0;
      ticking = false;
    };

    const onScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(update);
        ticking = true;
      }
    };

    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [threshold, enabled]);

  return direction;
}
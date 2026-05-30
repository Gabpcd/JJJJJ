import React, { useEffect, useState, useRef } from 'react';
import { useLocation } from 'react-router-dom';

interface PageTransitionProps {
  children: React.ReactNode;
}

/**
 * Platform-adaptive page transitions:
 * - iOS: horizontal slide (push/pop feel)
 * - Android: fast fade (Material Design)
 * - Web: instant or very light fade (150ms)
 */
export function PageTransition({ children }: PageTransitionProps) {
  const location = useLocation();
  const [displayChildren, setDisplayChildren] = useState(children);
  const [phase, setPhase] = useState<'enter' | 'exit'>('enter');
  const prevKey = useRef(location.key);

  useEffect(() => {
    if (location.key !== prevKey.current) {
      setPhase('exit');

      // Fade opacity court partout (plus de slide → plus de "saut" perçu).
      const exitDuration = 100;

      const timer = setTimeout(() => {
        prevKey.current = location.key;
        setDisplayChildren(children);
        setPhase('enter');
      }, exitDuration);
      return () => clearTimeout(timer);
    } else {
      setDisplayChildren(children);
    }
  }, [children, location.key]);

  // Determine CSS class based on platform and direction
  // CRITICAL: transform-based slide animations are ONLY used in Capacitor native,
  // because transform on a parent creates a containing block that breaks
  // position:fixed children (mobile header, bottom nav, modals).
  // Les anciennes animations slide iOS/Android laissaient un `transform`
  // résiduel (animation-fill-mode: both) sur le wrapper .page-transition →
  // containing block → la bottom nav et le header fixed/sticky scrollaient
  // avec le contenu, EN NATIF AUSSI. On utilise donc un simple fade opacity
  // partout (aucun transform sur le wrapper) : le positionnement fixed/sticky
  // reste intact sur les 3 interfaces, web comme natif.
  const getTransitionClass = () => {
    return phase === 'exit' ? 'page-exit' : 'page-enter';
  };

  return (
    <div className={`page-transition ${getTransitionClass()}`}>
      {displayChildren}
    </div>
  );
}

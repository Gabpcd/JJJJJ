import React, { useEffect, useState, useRef } from 'react';
import { useLocation, useNavigationType } from 'react-router-dom';
import { getPlatform, isNative } from '@/lib/platform';

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
  const navType = useNavigationType();
  const platform = getPlatform();
  const [displayChildren, setDisplayChildren] = useState(children);
  const [phase, setPhase] = useState<'enter' | 'exit'>('enter');
  const prevKey = useRef(location.key);
  const isBack = useRef(false);

  useEffect(() => {
    if (location.key !== prevKey.current) {
      isBack.current = navType === 'POP';
      setPhase('exit');

      const exitDuration = platform === 'ios' ? 250 : platform === 'android' ? 150 : 100;

      const timer = setTimeout(() => {
        prevKey.current = location.key;
        setDisplayChildren(children);
        setPhase('enter');
      }, exitDuration);
      return () => clearTimeout(timer);
    } else {
      setDisplayChildren(children);
    }
  }, [children, location.key, navType, platform]);

  // Determine CSS class based on platform and direction
  // CRITICAL: transform-based slide animations are ONLY used in Capacitor native,
  // because transform on a parent creates a containing block that breaks
  // position:fixed children (mobile header, bottom nav, modals) on Safari web.
  // Mobile browsers get a simple opacity fade, keeping fixed positioning intact.
  const useNativeSlides = isNative();
  const getTransitionClass = () => {
    if (phase === 'exit') {
      if (useNativeSlides && platform === 'ios') return isBack.current ? 'ios-exit-back' : 'ios-exit-forward';
      if (useNativeSlides && platform === 'android') return 'android-exit';
      return 'page-exit';
    }
    // enter
    if (useNativeSlides && platform === 'ios') return isBack.current ? 'ios-enter-back' : 'ios-enter-forward';
    if (useNativeSlides && platform === 'android') return 'android-enter';
    return 'page-enter';
  };

  return (
    <div className={`page-transition ${getTransitionClass()}`}>
      {displayChildren}
    </div>
  );
}

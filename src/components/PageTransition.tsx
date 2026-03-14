import React, { useEffect, useState, useRef } from 'react';
import { useLocation } from 'react-router-dom';

interface PageTransitionProps {
  children: React.ReactNode;
}

export function PageTransition({ children }: PageTransitionProps) {
  const location = useLocation();
  const [displayChildren, setDisplayChildren] = useState(children);
  const [phase, setPhase] = useState<'enter' | 'exit'>('enter');
  const prevKey = useRef(location.key);

  useEffect(() => {
    if (location.key !== prevKey.current) {
      setPhase('exit');
      const timer = setTimeout(() => {
        prevKey.current = location.key;
        setDisplayChildren(children);
        setPhase('enter');
      }, 150);
      return () => clearTimeout(timer);
    } else {
      setDisplayChildren(children);
    }
  }, [children, location.key]);

  return (
    <div
      className={`page-transition ${phase === 'exit' ? 'page-exit' : 'page-enter'}`}
    >
      {displayChildren}
    </div>
  );
}

import React, { useEffect, useState } from 'react';

interface CheckAnimationProps {
  active: boolean;
  duration?: number;
}

export function CheckAnimation({ active, duration = 2000 }: CheckAnimationProps) {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (active) {
      setShow(true);
      const timer = setTimeout(() => setShow(false), duration);
      return () => clearTimeout(timer);
    }
  }, [active, duration]);

  if (!show) return null;

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center pointer-events-none" aria-hidden="true">
      <div className="check-animation-circle">
        <svg className="check-animation-svg" viewBox="0 0 52 52" fill="none">
          <circle className="check-animation-ring" cx="26" cy="26" r="24" stroke="hsl(var(--success))" strokeWidth="2" />
          <path className="check-animation-path" d="M14 27l8 8 16-16" stroke="hsl(var(--success))" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
    </div>
  );
}

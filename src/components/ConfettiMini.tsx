import React, { useEffect, useState } from 'react';

interface ConfettiMiniProps {
  active: boolean;
  duration?: number;
  count?: number;
}

export function ConfettiMini({ active, duration = 1500, count = 6 }: ConfettiMiniProps) {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (active) {
      setShow(true);
      const timer = setTimeout(() => setShow(false), duration);
      return () => clearTimeout(timer);
    }
  }, [active, duration]);

  if (!show) return null;

  // Mix of brand colors: rose + teal + success
  const CONFETTI_COLORS = [
    'hsl(var(--primary))',
    'hsl(var(--teal))',
    'hsl(var(--success))',
    'hsl(var(--warning))',
    'hsl(var(--info))',
    '#FFD700',
  ];

  return (
    <div className="confetti-mini-container" aria-hidden="true">
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className="confetti-mini-particle"
          style={{
            left: `${30 + Math.random() * 40}%`,
            animationDelay: `${Math.random() * 0.4}s`,
            animationDuration: `${1 + Math.random() * 0.5}s`,
            backgroundColor: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
            width: `${4 + Math.random() * 4}px`,
            height: `${4 + Math.random() * 4}px`,
          }}
        />
      ))}
    </div>
  );
}

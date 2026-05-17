/**
 * ConfettiSwipe — Sprint 13-B PR 3
 *
 * Animation confetti CSS pour célébrer un SUPER_LIKE ou un match.
 * 30 particules colorées Y2K (rose, mauve, cyan, butter) avec trajectoires
 * aléatoires + rotation + fade-out.
 *
 * Usage :
 *   {showConfetti && <ConfettiSwipe key={Date.now()} onComplete={() => setShowConfetti(false)} />}
 *
 * Pure CSS via keyframes définies dans index.css (animate-confetti-pop).
 * `prefers-reduced-motion: reduce` → rendu skipped.
 */
import { useEffect, useMemo } from 'react';

const COLORS = [
  'hsl(var(--jolene-rose))',
  'hsl(var(--jolene-mauve))',
  'hsl(var(--jolene-cyan))',
  'hsl(var(--jolene-butter))',
];

interface Props {
  /** Callback déclenché ~1.8s après le mount (fin animation). */
  onComplete?: () => void;
  /** Nombre de particules (défaut 30). */
  count?: number;
}

export function ConfettiSwipe({ onComplete, count = 30 }: Props) {
  const particles = useMemo(() => {
    return Array.from({ length: count }).map((_, i) => ({
      id: i,
      color: COLORS[i % COLORS.length],
      left: Math.random() * 100,
      delay: Math.random() * 0.4,
      duration: 1.2 + Math.random() * 0.6,
      tx: -40 + Math.random() * 80,
      rotation: Math.random() * 720,
      size: 8 + Math.random() * 8,
    }));
  }, [count]);

  useEffect(() => {
    if (!onComplete) return;
    const t = setTimeout(onComplete, 1800);
    return () => clearTimeout(t);
  }, [onComplete]);

  // Respecter prefers-reduced-motion : rendu sans animation
  if (typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
    return null;
  }

  return (
    <div
      className="pointer-events-none fixed inset-0 z-50 overflow-hidden"
      aria-hidden="true"
      role="presentation"
    >
      {particles.map((p) => (
        <span
          key={p.id}
          className="absolute top-1/3 animate-confetti-pop"
          style={{
            left: `${p.left}%`,
            width: `${p.size}px`,
            height: `${p.size}px`,
            backgroundColor: p.color,
            borderRadius: p.id % 3 === 0 ? '50%' : '2px',
            animationDelay: `${p.delay}s`,
            animationDuration: `${p.duration}s`,
            ['--confetti-tx' as string]: `${p.tx}vw`,
            ['--confetti-rot' as string]: `${p.rotation}deg`,
          }}
        />
      ))}
    </div>
  );
}

export default ConfettiSwipe;

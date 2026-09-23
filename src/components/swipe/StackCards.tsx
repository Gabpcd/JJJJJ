/**
 * StackCards — Sprint 13-B PR 2
 *
 * Stack de 3 cards visibles (top + 2 background parallax) avec swipe gestures
 * touch/mouse. Spring physics via animations.ts (transition-bouncy).
 *
 * Comportement :
 * - Drag horizontal : translation + rotation max 15deg
 * - Threshold 30% largeur → trigger onSwipe(direction)
 * - Bounce back si swipe pas assez fort
 * - Indicateurs VÉRIFIER (rose) / SUIVANT (gris) selon la direction
 *
 * Pas de framer-motion : transform inline + transition CSS (perf léger bundle).
 * `prefers-reduced-motion` respecté.
 */
import { useState, useRef, useCallback, useEffect, type ReactNode } from 'react';
import { CalendarCheck2, X } from 'lucide-react';
import { cn } from '@/lib/utils';

export type SwipeDirection = 'left' | 'right';

interface CardItem {
  key: string;
  content: ReactNode;
}

interface Props {
  items: CardItem[];
  onSwipe: (direction: SwipeDirection, itemKey: string) => void;
  /** Largeur en pixels au-delà de laquelle un swipe est validé. Défaut 30% du container. */
  thresholdRatio?: number;
  className?: string;
}

export function StackCards({ items, onSwipe, thresholdRatio = 0.3, className }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [dragX, setDragX] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [exitDirection, setExitDirection] = useState<SwipeDirection | null>(null);
  const dragStartRef = useRef<{ x: number; y: number; pointerId: number; active: boolean } | null>(null);
  const dragXRef = useRef(0);
  const frameRef = useRef<number>();
  const exitTimerRef = useRef<ReturnType<typeof setTimeout>>();
  const suppressClickRef = useRef(false);

  const topCard = items[0];
  const bgCards = items.slice(1, 3); // 2 cards en background

  const reset = useCallback(() => {
    setDragX(0);
    setIsDragging(false);
    setExitDirection(null);
    dragStartRef.current = null;
    dragXRef.current = 0;
    if (frameRef.current !== undefined) cancelAnimationFrame(frameRef.current);
    if (exitTimerRef.current !== undefined) clearTimeout(exitTimerRef.current);
  }, []);

  useEffect(() => {
    // Reset quand la card top change (nouveau swipe en attente)
    reset();
    return () => {
      if (frameRef.current !== undefined) cancelAnimationFrame(frameRef.current);
      if (exitTimerRef.current !== undefined) clearTimeout(exitTimerRef.current);
    };
  }, [topCard?.key, reset]);

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!topCard || exitDirection || e.button !== 0 || e.isPrimary === false) return;
    if ((e.target as HTMLElement).closest('button, a, input, select, textarea')) return;
    // Laisser le clic natif atteindre la carte tant qu'un drag n'est pas établi.
    suppressClickRef.current = false;
    dragStartRef.current = { x: e.clientX, y: e.clientY, pointerId: e.pointerId, active: false };
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    const start = dragStartRef.current;
    if (!start || start.pointerId !== e.pointerId) return;
    const x = e.clientX - start.x;
    const y = e.clientY - start.y;
    if (!start.active) {
      if (Math.max(Math.abs(x), Math.abs(y)) < 8) return;
      if (Math.abs(y) >= Math.abs(x)) { dragStartRef.current = null; return; }
      start.active = true;
      suppressClickRef.current = true;
      setIsDragging(true);
      e.currentTarget.setPointerCapture(e.pointerId);
    }
    dragXRef.current = x;
    if (frameRef.current !== undefined) cancelAnimationFrame(frameRef.current);
    frameRef.current = requestAnimationFrame(() => setDragX(dragXRef.current));
  };

  const releasePointer = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
  };

  const handlePointerEnd = (e: React.PointerEvent<HTMLDivElement>) => {
    const start = dragStartRef.current;
    if (!start || start.pointerId !== e.pointerId) return;
    dragStartRef.current = null;
    releasePointer(e);
    if (!start.active) return;
    if (frameRef.current !== undefined) cancelAnimationFrame(frameRef.current);
    const x = e.clientX - start.x;
    const threshold = (containerRef.current?.offsetWidth || 320) * thresholdRatio;
    setIsDragging(false);
    if (Math.abs(x) >= threshold && topCard) {
      const direction: SwipeDirection = x > 0 ? 'right' : 'left';
      setExitDirection(direction);
      const delay = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 280;
      exitTimerRef.current = setTimeout(() => onSwipe(direction, topCard.key), delay);
    } else {
      setDragX(0);
    }
  };

  const handlePointerCancel = (e: React.PointerEvent<HTMLDivElement>) => {
    if (dragStartRef.current?.pointerId !== e.pointerId) return;
    releasePointer(e);
    reset(); // Une interruption système ne valide jamais une mission.
  };

  // Calculer transform pour la card top
  const rotation = Math.max(-15, Math.min(15, dragX / 14));
  const exitTranslate = exitDirection === 'right' ? 800 : exitDirection === 'left' ? -800 : 0;
  const topTransform = exitDirection
    ? `translate(${exitTranslate}px, 0) rotate(${exitDirection === 'right' ? 25 : -25}deg)`
    : `translate(${dragX}px, 0) rotate(${rotation}deg)`;

  // Opacity indicateurs
  const likeOpacity = Math.max(0, Math.min(1, dragX / 80));
  const dislikeOpacity = Math.max(0, Math.min(1, -dragX / 80));

  if (!topCard) {
    return null;
  }

  return (
    <div ref={containerRef} className={cn('relative w-full h-full', className)}>
      {/* Background cards (sous la card top) — scale + opacity parallax */}
      {bgCards.map((item, idx) => {
        const offset = idx + 1;
        const scale = 1 - offset * 0.04;
        const translateY = offset * 8;
        const opacity = 1 - offset * 0.2;
        return (
          <div
            key={item.key}
            className="absolute inset-0 pointer-events-none"
            style={{
              transform: `scale(${scale}) translateY(${translateY}px)`,
              opacity,
              zIndex: 10 - offset,
            }}
            aria-hidden="true"
          >
            {item.content}
          </div>
        );
      })}

      {/* Card top : drag-enabled */}
      <div
        className={cn(
          'relative h-full touch-pan-y select-none',
          !isDragging && 'transition-bouncy',
        )}
        style={{
          transform: topTransform,
          zIndex: 20,
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerEnd}
        onPointerCancel={handlePointerCancel}
        onLostPointerCapture={handlePointerCancel}
        onClickCapture={(event) => {
          if (suppressClickRef.current && event.detail !== 0) {
            event.preventDefault();
            event.stopPropagation();
            suppressClickRef.current = false;
          }
        }}
      >
        {topCard.content}

        {/* Overlay indicateurs planning / suivant */}
        <div
          className="pointer-events-none absolute top-8 left-8 rounded-2xl border-4 border-jolene-rose-500 bg-jolene-rose-100/90 px-4 py-2 transition-snap"
          style={{ opacity: likeOpacity, transform: `rotate(-12deg) scale(${0.8 + likeOpacity * 0.2})` }}
          aria-hidden="true"
        >
          <span className="flex items-center gap-2 text-2xl font-extrabold text-jolene-rose-700">
            <CalendarCheck2 className="h-7 w-7" />
            VÉRIFIER
          </span>
        </div>
        <div
          className="pointer-events-none absolute top-8 right-8 rounded-2xl border-4 border-jolene-bubblegum bg-jolene-cloud/90 px-4 py-2 transition-snap"
          style={{ opacity: dislikeOpacity, transform: `rotate(12deg) scale(${0.8 + dislikeOpacity * 0.2})` }}
          aria-hidden="true"
        >
          <span className="flex items-center gap-2 text-2xl font-extrabold text-jolene-bubblegum">
            <X className="h-7 w-7" />
            SUIVANT
          </span>
        </div>
      </div>
    </div>
  );
}

export default StackCards;

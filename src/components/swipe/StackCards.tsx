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
 * - Indicateurs LIKE (rose) / DISLIKE (gris) overlay selon direction
 *
 * Pas de framer-motion : transform inline + transition CSS (perf léger bundle).
 * `prefers-reduced-motion` respecté.
 */
import { useState, useRef, useCallback, useEffect, type ReactNode } from 'react';
import { Heart, X } from 'lucide-react';
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
  const dragStartRef = useRef<{ x: number; pointerId: number | null }>({ x: 0, pointerId: null });

  const topCard = items[0];
  const bgCards = items.slice(1, 3); // 2 cards en background

  const reset = useCallback(() => {
    setDragX(0);
    setIsDragging(false);
    setExitDirection(null);
    dragStartRef.current = { x: 0, pointerId: null };
  }, []);

  useEffect(() => {
    // Reset quand la card top change (nouveau swipe en attente)
    reset();
  }, [topCard?.key, reset]);

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!topCard || exitDirection) return;
    dragStartRef.current = { x: e.clientX, pointerId: e.pointerId };
    setIsDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isDragging || dragStartRef.current.pointerId !== e.pointerId) return;
    setDragX(e.clientX - dragStartRef.current.x);
  };

  const handlePointerEnd = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isDragging || dragStartRef.current.pointerId !== e.pointerId) return;
    e.currentTarget.releasePointerCapture(e.pointerId);

    const width = containerRef.current?.offsetWidth ?? 320;
    const threshold = width * thresholdRatio;

    if (Math.abs(dragX) >= threshold && topCard) {
      const direction: SwipeDirection = dragX > 0 ? 'right' : 'left';
      setExitDirection(direction);
      setIsDragging(false);
      // Animation exit puis trigger onSwipe
      setTimeout(() => {
        onSwipe(direction, topCard.key);
      }, 280);
    } else {
      // Bounce back
      setDragX(0);
      setIsDragging(false);
    }
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
          'relative h-full touch-none select-none',
          !isDragging && 'transition-bouncy',
        )}
        style={{
          transform: topTransform,
          zIndex: 20,
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerEnd}
        onPointerCancel={handlePointerEnd}
      >
        {topCard.content}

        {/* Overlay indicateurs LIKE / DISLIKE */}
        <div
          className="pointer-events-none absolute top-8 left-8 rounded-2xl border-4 border-jolene-rose-500 bg-jolene-rose-100/90 px-4 py-2 transition-snap"
          style={{ opacity: likeOpacity, transform: `rotate(-12deg) scale(${0.8 + likeOpacity * 0.2})` }}
          aria-hidden="true"
        >
          <span className="flex items-center gap-2 text-2xl font-extrabold text-jolene-rose-700">
            <Heart className="h-7 w-7 fill-current" />
            J'AIME
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

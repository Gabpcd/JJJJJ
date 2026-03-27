import React, { useState, useCallback, useRef } from 'react';
import { Loader2 } from 'lucide-react';
import { usePlatform } from '@/hooks/usePlatform';

interface PullToRefreshProps {
  onRefresh: () => Promise<void>;
  children: React.ReactNode;
}

const THRESHOLD = 70;

/**
 * Pull-to-refresh wrapper. Active only on iOS/Android native.
 * On web, children are rendered without the pull gesture.
 */
export function PullToRefresh({ onRefresh, children }: PullToRefreshProps) {
  const platform = usePlatform();
  const [pulling, setPulling] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  const startY = useRef(0);
  const containerRef = useRef<HTMLDivElement>(null);

  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    if (refreshing) return;
    const el = containerRef.current;
    if (!el || el.scrollTop > 0) return;
    startY.current = e.touches[0].clientY;
    setPulling(true);
  }, [refreshing]);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    if (!pulling || refreshing) return;
    const diff = e.touches[0].clientY - startY.current;
    if (diff < 0) {
      setPullDistance(0);
      return;
    }
    setPullDistance(Math.min(diff * 0.5, THRESHOLD * 1.5));
  }, [pulling, refreshing]);

  const handleTouchEnd = useCallback(async () => {
    if (!pulling) return;
    setPulling(false);

    if (pullDistance >= THRESHOLD) {
      setRefreshing(true);
      try {
        await onRefresh();
      } finally {
        setRefreshing(false);
      }
    }
    setPullDistance(0);
  }, [pulling, pullDistance, onRefresh]);

  // On web, just render children without touch handlers
  if (platform === 'web') {
    return <>{children}</>;
  }

  return (
    <div
      ref={containerRef}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      className="relative"
    >
      {/* Pull indicator */}
      <div
        className="flex items-center justify-center overflow-hidden transition-all duration-200"
        style={{
          height: refreshing ? 48 : pullDistance,
          opacity: refreshing ? 1 : Math.min(pullDistance / THRESHOLD, 1),
        }}
      >
        <Loader2
          className={`h-5 w-5 text-primary ${refreshing ? 'animate-spin' : ''}`}
          style={{
            transform: refreshing
              ? undefined
              : `rotate(${(pullDistance / THRESHOLD) * 360}deg)`,
          }}
          aria-hidden="true"
        />
      </div>

      {children}
    </div>
  );
}

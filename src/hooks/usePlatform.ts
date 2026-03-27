import { useMemo } from 'react';
import { Capacitor } from '@capacitor/core';

export type Platform = 'web' | 'ios' | 'android';

/**
 * Returns the current platform: 'web', 'ios', or 'android'.
 * Stable across renders (platform doesn't change at runtime).
 */
export function usePlatform(): Platform {
  return useMemo(() => {
    if (!Capacitor.isNativePlatform()) return 'web';
    return Capacitor.getPlatform() as 'ios' | 'android';
  }, []);
}

import { useCallback, useRef } from 'react';

/**
 * Prevents double-execution of an async action.
 * Returns a wrapped function that ignores calls while the previous one is still running.
 * Also enforces a minimum delay between calls (default 1s).
 */
export function useActionOnce<T extends (...args: any[]) => Promise<any>>(
  fn: T,
  minDelayMs = 1000
): [(...args: Parameters<T>) => Promise<ReturnType<T> | undefined>, boolean] {
  const running = useRef(false);
  const lastCall = useRef(0);

  const wrappedFn = useCallback(
    async (...args: Parameters<T>): Promise<ReturnType<T> | undefined> => {
      const now = Date.now();
      if (running.current || now - lastCall.current < minDelayMs) return undefined;
      running.current = true;
      lastCall.current = now;
      try {
        return await fn(...args);
      } finally {
        running.current = false;
      }
    },
    [fn, minDelayMs]
  );

  return [wrappedFn as any, running.current];
}

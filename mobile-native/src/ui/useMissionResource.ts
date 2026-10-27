import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useIsFocused } from '@react-navigation/native';

type Resource<T> = { key: string; data: T | null; loading: boolean; error: string | null };

/** Keep a screen's data and scroll position on back; cancel reads off screen. */
export function useMissionResource<T>(key: string, loader: (signal: AbortSignal) => Promise<T>, errorMessage = 'Les missions ne sont pas accessibles pour le moment. Réessayez dans un instant.') {
  const focused = useIsFocused();
  const [active, setActive] = useState(AppState.currentState === 'active');
  const [resource, setResource] = useState<Resource<T>>({ key, data: null, loading: true, error: null });
  const latestLoader = useRef(loader);
  latestLoader.current = loader;
  const request = useRef<AbortController | null>(null);
  const generation = useRef(0);
  const lastSuccess = useRef({ key: '', at: 0 });

  useEffect(() => {
    const listener = AppState.addEventListener('change', state => setActive(state === 'active'));
    return () => listener.remove();
  }, []);

  const refresh = useCallback(() => {
    if (!focused || !active) return;
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    const currentGeneration = ++generation.current;
    let timedOut = false;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeout = setTimeout(() => { timedOut = true; controller.abort(); reject(new Error('timeout')); }, 20_000);
    });
    setResource(previous => ({ key, data: previous.key === key ? previous.data : null, loading: true, error: null }));
    void Promise.race([latestLoader.current(controller.signal), timeoutPromise]).then(data => {
      if (currentGeneration !== generation.current || controller.signal.aborted) return;
      lastSuccess.current = { key, at: Date.now() };
      setResource({ key, data, loading: false, error: null });
    }).catch(() => {
      if (currentGeneration !== generation.current || (controller.signal.aborted && !timedOut)) return;
      setResource(previous => ({ ...previous, loading: false,
        error: timedOut ? 'La connexion prend trop de temps. Vérifiez votre réseau puis réessayez.'
          : errorMessage }));
    }).finally(() => {
      if (timeout) clearTimeout(timeout);
      if (currentGeneration === generation.current) request.current = null;
    });
  }, [key, focused, active, errorMessage]);

  useEffect(() => {
    if (focused && active && (lastSuccess.current.key !== key || Date.now() - lastSuccess.current.at > 30_000)) refresh();
    return () => {
      ++generation.current;
      request.current?.abort();
      request.current = null;
      setResource(previous => previous.loading ? { ...previous, loading: false } : previous);
    };
  }, [key, focused, active, refresh]);

  const current = resource.key === key ? resource : { key, data: null, loading: true, error: null };
  return { ...current, refresh };
}

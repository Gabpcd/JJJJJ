import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useIsFocused } from '@react-navigation/native';

type Resource<T> = { key: string; data: T | null; loading: boolean; error: string | null };

/** Reads are invalidated on scope changes, refocused screens and app resume.
 * An access/network failure removes the old result rather than retaining it as current. */
export function useEstablishmentResource<T>(key: string, loader: (signal: AbortSignal) => Promise<T>) {
  const focused = useIsFocused();
  const [active, setActive] = useState(AppState.currentState === 'active');
  const [resource, setResource] = useState<Resource<T>>({ key, data: null, loading: true, error: null });
  const currentLoader = useRef(loader);
  currentLoader.current = loader;
  const generation = useRef(0);
  const pending = useRef<{ controller: AbortController; cancelTimer: () => void } | null>(null);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', state => setActive(state === 'active'));
    return () => subscription.remove();
  }, []);

  const refresh = useCallback(() => {
    if (!focused || !active) return;
    pending.current?.controller.abort();
    pending.current?.cancelTimer();
    const controller = new AbortController();
    const requestId = ++generation.current;
    let expired = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => { expired = true; controller.abort(); reject(new Error('timeout')); }, 20_000);
    });
    pending.current = { controller, cancelTimer: () => { if (timer) clearTimeout(timer); } };
    setResource(previous => ({ key, data: previous.key === key ? previous.data : null, loading: true, error: null }));
    void Promise.race([currentLoader.current(controller.signal), timeout]).then(data => {
      if (requestId !== generation.current || controller.signal.aborted) return;
      setResource({ key, data, loading: false, error: null });
    }).catch(() => {
      if (requestId !== generation.current || (controller.signal.aborted && !expired)) return;
      setResource({ key, data: null, loading: false, error: expired
        ? 'La connexion prend trop de temps. Vérifiez votre réseau puis réessayez.'
        : 'Ces informations ne sont pas accessibles pour le moment. Réessayez pour vérifier votre accès.' });
    }).finally(() => {
      if (timer) clearTimeout(timer);
      if (requestId === generation.current) pending.current = null;
    });
  }, [key, focused, active]);

  useEffect(() => {
    if (focused && active) refresh();
    return () => {
      ++generation.current;
      pending.current?.controller.abort();
      pending.current?.cancelTimer();
      pending.current = null;
      setResource(previous => previous.loading ? { ...previous, loading: false } : previous);
    };
  }, [key, focused, active, refresh]);

  const current = resource.key === key ? resource : { key, data: null, loading: true, error: null };
  return { ...current, refresh };
}

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { advancePresenceVisibility, type PresenceVisibility } from './transitions';

export function usePresenceVisibility() {
  const focused = useIsFocused();
  const [activity, setActivity] = useState<PresenceVisibility>({ active: AppState.currentState === 'active', revision: 0 });
  const available = useRef(false);
  const latestActivity = useRef(activity);
  useLayoutEffect(() => {
    available.current = focused && activity.active;
    const subscription = AppState.addEventListener('change', value => {
      const next = advancePresenceVisibility(latestActivity.current, value === 'active');
      if (next === latestActivity.current) return;
      latestActivity.current = next; available.current = false; setActivity(next);
    });
    return () => { available.current = false; subscription.remove(); };
  }, [focused, activity]);
  return { visible: focused && activity.active, revision: activity.revision, available };
}

export function usePresenceResource<T>(key: string, loader: (signal: AbortSignal) => Promise<T>, pollMs?: number) {
  const visibility = usePresenceVisibility();
  const [state, setState] = useState<{ key: string; data: T | null; loading: boolean; error: string | null }>({ key, data: null, loading: true, error: null });
  const load = useRef(loader); load.current = loader;
  const sequence = useRef(0); const request = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    if (!visibility.available.current) return;
    request.current?.abort(); const controller = new AbortController(); request.current = controller;
    const generation = ++sequence.current;
    let timer: ReturnType<typeof setTimeout> | undefined;
    setState(previous => ({ key, data: previous.key === key ? previous.data : null, loading: true, error: null }));
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('timeout')); }, 20_000); });
      const data = await Promise.race([load.current(controller.signal), timeout]);
      if (!visibility.available.current || controller.signal.aborted || generation !== sequence.current) return;
      setState({ key, data, loading: false, error: null });
    } catch {
      if (visibility.available.current && generation === sequence.current) setState({ key, data: null, loading: false,
        error: 'Le pointage ne peut pas être chargé pour le moment. Vérifiez votre connexion puis actualisez.' });
    } finally { if (timer) clearTimeout(timer); if (request.current === controller) request.current = null; }
  }, [key, visibility.available]);
  useLayoutEffect(() => {
    ++sequence.current; request.current?.abort(); request.current = null;
    setState({ key, data: null, loading: visibility.visible, error: null });
    return () => { ++sequence.current; request.current?.abort(); request.current = null; };
  }, [key, visibility.visible, visibility.revision]);
  useEffect(() => {
    if (!visibility.visible) return;
    void refresh();
    if (pollMs) {
      const interval = setInterval(() => { if (!request.current) void refresh(); }, pollMs);
      return () => clearInterval(interval);
    }
  }, [visibility.visible, visibility.revision, refresh, pollMs]);
  const current = state.key === key && visibility.visible ? state : { key, data: null, loading: visibility.visible, error: null };
  return { ...current, refresh, visible: visibility.visible };
}

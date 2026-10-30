import { useCallback, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import type { NativePresenceSession } from '../../presence/runtime';

/** A permission sheet is inactive, not a loss of consent. Blur/background invalidates immediately. */
export function usePresenceGpsConsent(session: NativePresenceSession) {
  const [state, setState] = useState({ session, loading: true, data: false, error: false });
  const latest = useRef(session); latest.current = session;
  useFocusEffect(useCallback(() => {
    let alive = true; let background = AppState.currentState === 'background'; let sequence = 0;
    let request: AbortController | null = null;
    const invalidate = () => { ++sequence; request?.abort(); request = null;
      if (alive) setState({ session, loading: true, data: false, error: false }); };
    const read = async () => {
      invalidate(); if (!alive || background) return;
      const generation = sequence; const controller = new AbortController(); request = controller;
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('timeout')); }, 20_000); });
        const value = await Promise.race([session.readGpsConsent(controller.signal), timeout]);
        if (alive && !background && generation === sequence && latest.current === session && !controller.signal.aborted)
          setState({ session, loading: false, data: value === true, error: false });
      } catch {
        if (alive && !background && generation === sequence && latest.current === session)
          setState({ session, loading: false, data: false, error: true });
      } finally { if (timer) clearTimeout(timer); if (request === controller) request = null; }
    };
    void read();
    const subscription = AppState.addEventListener('change', value => {
      if (value === 'background') { background = true; invalidate(); }
      else if (value === 'active' && background) { background = false; void read(); }
    });
    return () => { alive = false; ++sequence; request?.abort(); subscription.remove(); };
  }, [session]));
  return state.session === session ? state : { session, loading: true, data: false, error: false };
}

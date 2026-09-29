import { useEffect, useRef } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { ABSENCE_LONGUE_MS, dashboardPourRole, navigationNativeRecente, routeProtegeeAuRetour } from '@/lib/nativeResume';

function RepriseSessionConnectee({ userId }: { userId: string }) {
  const { role, parcours } = useRole();
  const dashboard = dashboardPourRole(role, parcours);
  const navigate = useNavigate();
  const location = useLocation();
  const route = useRef(location);
  const formulaireModifie = useRef(false);
  useEffect(() => { route.current = location; formulaireModifie.current = false; }, [location]);

  useEffect(() => {
    if (!dashboard) return;
    const key = `jolene.native.background.${userId}`;
    let disposed = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let background: number | null = null;
    try {
      const saved = Number(localStorage.getItem(key));
      if (Number.isFinite(saved) && saved > 0) background = saved;
    } catch { /* memory fallback */ }
    const change = (event: Event) => {
      if (event.target instanceof HTMLElement && event.target.closest('form,[role="dialog"]')) formulaireModifie.current = true;
    };
    const onState = (active: boolean) => {
      if (!active) {
        clearTimeout(timer);
        background ??= Date.now();
        try { localStorage.setItem(key, String(background)); } catch { /* memory fallback */ }
        return;
      }
      // visibilitychange + appStateChange can both announce the same resume.
      if (background === null) return;
      const absence = Date.now() - background;
      background = null;
      if (absence < ABSENCE_LONGUE_MS) {
        try { localStorage.removeItem(key); } catch { /* memory fallback */ }
        return;
      }
      timer = setTimeout(() => {
        const { pathname, search, hash } = route.current;
        if (disposed) return;
        // Keep the saved absence until this decision actually executes. Auth
        // restoration can temporarily change the role and restart this effect.
        try { localStorage.removeItem(key); } catch { /* memory fallback */ }
        if (navigationNativeRecente() || formulaireModifie.current
          || document.querySelector('[role="dialog"][data-state="open"]')
          || routeProtegeeAuRetour(pathname, search, hash)) return;
        navigate(dashboard, { replace: true });
      }, 350);
    };
    const visibility = () => onState(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', visibility);
    document.addEventListener('input', change);
    document.addEventListener('change', change);
    const listener = App.addListener('appStateChange', ({ isActive }) => onState(isActive));
    if (document.visibilityState === 'visible') onState(true);
    return () => {
      disposed = true;
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', visibility);
      document.removeEventListener('input', change);
      document.removeEventListener('change', change);
      void listener.then(handle => handle.remove()).catch(() => undefined);
    };
  }, [userId, dashboard, navigate]);
  return null;
}

export function NativeSessionResume() {
  const { user, loading } = useAuth();
  return Capacitor.isNativePlatform() && !loading && user
    ? <RepriseSessionConnectee key={user.id} userId={user.id} /> : null;
}

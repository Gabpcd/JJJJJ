import { useEffect, useRef } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { ABSENCE_LONGUE_MS, dashboardPourRole, navigationNativeDepuis, routeProtegeeAuRetour } from '@/lib/nativeResume';

function dialogueVisible(): boolean {
  return Array.from(document.querySelectorAll<HTMLElement>('[role="dialog"], [role="alertdialog"], dialog[open]'))
    .some(dialogue => dialogue.getClientRects().length > 0 && getComputedStyle(dialogue).visibility !== 'hidden');
}

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
      if (event.target instanceof HTMLElement && event.target.closest('input,textarea,select,[contenteditable],form,[role="dialog"]')) formulaireModifie.current = true;
    };
    const signature = (event: Event) => {
      if (event.target instanceof HTMLCanvasElement) formulaireModifie.current = true;
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
      const debutAbsence = background;
      const absence = Date.now() - debutAbsence;
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
        if (navigationNativeDepuis(debutAbsence) || formulaireModifie.current
          || dialogueVisible()
          || routeProtegeeAuRetour(pathname, search, hash)) return;
        navigate(dashboard, { replace: true });
      }, 350);
    };
    const visibility = () => onState(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', visibility);
    document.addEventListener('input', change);
    document.addEventListener('change', change);
    document.addEventListener('pointerdown', signature, true);
    const listener = App.addListener('appStateChange', ({ isActive }) => onState(isActive));
    if (document.visibilityState === 'visible') onState(true);
    return () => {
      disposed = true;
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', visibility);
      document.removeEventListener('input', change);
      document.removeEventListener('change', change);
      document.removeEventListener('pointerdown', signature, true);
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

import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Capacitor } from '@capacitor/core';
import { prepareMobileUpdate } from '@/lib/mobileUpdates';

/** Mounted inside the route Suspense boundary once its content can render. */
export function NativeUpdateReady() {
  const { pathname } = useLocation();
  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return;
    let frame = 0;
    let disposed = false;
    // Guards can render ChargementPage without suspending. Wait until that
    // placeholder disappears, then allow redirects/render errors to commit.
    const check = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        if (disposed || document.querySelector('[data-native-route-loading]')) return;
        frame = requestAnimationFrame(() => {
          if (disposed || document.querySelector('[data-native-route-loading]')) return;
          void prepareMobileUpdate().catch(() => {
            console.info('[mobile-update] La version installée reste active.');
          });
          observer.disconnect();
        });
      });
    };
    const observer = new MutationObserver(check);
    observer.observe(document.body, { childList: true, subtree: true });
    check();
    return () => { disposed = true; cancelAnimationFrame(frame); observer.disconnect(); };
  }, [pathname]);
  return null;
}

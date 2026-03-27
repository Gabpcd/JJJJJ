import { createRoot } from "react-dom/client";
import * as Sentry from "@sentry/react";
import { Capacitor } from "@capacitor/core";
import App from "./App.tsx";
import "./index.css";

// ─── Sentry Initialization ───
const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN;
if (SENTRY_DSN) {
  Sentry.init({
    dsn: SENTRY_DSN,
    environment: import.meta.env.VITE_ENV || import.meta.env.MODE,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: false, blockAllMedia: false }),
    ],
    tracesSampleRate: 0.1,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 1.0,
  });
}

// Apply theme before render to avoid flash
const stored = localStorage.getItem('theme');
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
if (stored === 'dark' || (!stored && prefersDark)) {
  document.documentElement.classList.add('dark');
}

// ─── Service Worker Registration ───
if ('serviceWorker' in navigator) {
  window.addEventListener('load', async () => {
    try {
      const reg = await navigator.serviceWorker.register('/firebase-messaging-sw.js');

      // Listen for SW update messages
      navigator.serviceWorker.addEventListener('message', (event) => {
        if (event.data?.type === 'SW_UPDATED') {
          showUpdateBanner();
        }
      });

      // Also detect waiting SW (classic update flow)
      reg.addEventListener('updatefound', () => {
        const newWorker = reg.installing;
        if (!newWorker) return;
        newWorker.addEventListener('statechange', () => {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            showUpdateBanner();
          }
        });
      });
    } catch (e) {
      console.warn('SW registration failed:', e);
    }
  });
}

function showUpdateBanner() {
  if (document.getElementById('sw-update-banner')) return;

  const banner = document.createElement('div');
  banner.id = 'sw-update-banner';
  banner.setAttribute('role', 'alert');
  Object.assign(banner.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    right: '0',
    zIndex: '9999',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '12px',
    padding: '10px 16px',
    paddingTop: 'calc(10px + env(safe-area-inset-top))',
    background: '#17a2b8',
    color: '#fff',
    fontSize: '14px',
    fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    boxShadow: '0 2px 8px rgba(0,0,0,0.15)',
  });

  const text = document.createElement('span');
  text.textContent = 'Nouvelle version disponible';

  const btn = document.createElement('button');
  btn.textContent = 'Mettre à jour';
  Object.assign(btn.style, {
    background: '#fff',
    color: '#17a2b8',
    border: 'none',
    borderRadius: '6px',
    padding: '6px 14px',
    fontWeight: '600',
    fontSize: '13px',
    cursor: 'pointer',
    minHeight: '44px',
    minWidth: '44px',
  });
  btn.addEventListener('click', () => {
    window.location.reload();
  });

  const close = document.createElement('button');
  close.textContent = '✕';
  close.setAttribute('aria-label', 'Fermer');
  Object.assign(close.style, {
    background: 'none',
    border: 'none',
    color: '#fff',
    fontSize: '16px',
    cursor: 'pointer',
    padding: '10px',
    minHeight: '44px',
    minWidth: '44px',
    opacity: '0.8',
  });
  close.addEventListener('click', () => banner.remove());

  banner.append(text, btn, close);
  document.body.prepend(banner);
}

import { SentryErrorFallback } from "./components/SentryErrorFallback";

// ─── Capacitor Native Init (deep links + push + back button + splash) ───
async function initNativePlugins() {
  if (!Capacitor.isNativePlatform()) return;

  const { App: CapApp } = await import("@capacitor/app");

  // Deep links — route appUrlOpen events to React Router
  CapApp.addListener("appUrlOpen", (event) => {
    const url = new URL(event.url);
    const path = url.pathname + url.search;
    if (path) {
      window.location.hash = "";
      window.history.replaceState(null, "", path);
      window.dispatchEvent(new PopStateEvent("popstate"));
    }
  });

  // Android hardware back button
  let lastBackPress = 0;
  const MAIN_ROUTES = [
    '/soignant/tableau-de-bord',
    '/etablissement/tableau-de-bord',
    '/groupe/tableau-de-bord',
    '/admin',
    '/',
  ];

  CapApp.addListener("backButton", ({ canGoBack }) => {
    const currentPath = window.location.pathname;
    const isMainRoute = MAIN_ROUTES.some(r => currentPath === r || currentPath.startsWith(r + '/'));

    if (canGoBack && !isMainRoute) {
      window.history.back();
    } else {
      const now = Date.now();
      if (now - lastBackPress < 2000) {
        CapApp.exitApp();
      } else {
        lastBackPress = now;
        import('sonner').then(({ toast }) => {
          toast.info('Appuyez à nouveau pour quitter');
        });
      }
    }
  });

  // StatusBar configuration
  try {
    const { StatusBar, Style } = await import("@capacitor/status-bar");
    await StatusBar.setStyle({ style: Style.Dark });
    if (Capacitor.getPlatform() === 'android') {
      await StatusBar.setBackgroundColor({ color: '#FFFFFF' });
    }
  } catch {}

  // Splash screen: check session, then hide
  // This prevents white screen between splash and content
  try {
    const { SplashScreen } = await import("@capacitor/splash-screen");
    const { supabase } = await import("./integrations/supabase/client");

    // Check for existing session while splash is still showing
    const { data: { session } } = await supabase.auth.getSession();

    if (session) {
      // User is logged in — navigate to their dashboard
      // The role check will happen in RouteProtegee, but we pre-navigate
      try {
        const { data: roleData } = await supabase.rpc('fn_get_my_role');
        const role = typeof roleData === 'string' ? roleData : (roleData as any)?.role;
        let target = '/connexion';
        if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') target = '/admin';
        else if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') target = '/etablissement/tableau-de-bord';
        else if (role === 'ADMIN_GROUPE') target = '/groupe/tableau-de-bord';
        else if (role === 'SOIGNANT') target = '/soignant/tableau-de-bord';

        if (window.location.pathname === '/' || window.location.pathname === '/connexion') {
          window.history.replaceState(null, '', target);
        }
      } catch {
        // If role check fails, let normal auth flow handle it
      }
    }

    // Hide splash after session check (max 1.5s enforced by config)
    await SplashScreen.hide();
  } catch {}
}

initNativePlugins();

// Configure keyboard behavior per-platform
import { configurerClavier } from './lib/platform';
configurerClavier();

createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={({ resetError }) => <SentryErrorFallback resetError={resetError} />}>
    <App />
  </Sentry.ErrorBoundary>
);

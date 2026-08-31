import { createRoot } from "react-dom/client";
import * as Sentry from "@sentry/react";
import { Capacitor } from "@capacitor/core";
import App from "./App.tsx";
import "./index.css";
import { normaliserLienJolene } from './lib/nativeLinks';
import { fermerNavigateurPsc } from './lib/pscNavigation';
import { installVitePreloadRecovery } from './lib/chunkRecovery';

// ─── Sentry Initialization ───
const SENTRY_DSN = import.meta.env.VITE_SENTRY_DSN;

// Release injectée par Vite (vite.config.ts → define) — match les sourcemaps
// uploadées par sentryVitePlugin pour désobfusquer les stack traces.
declare const __APP_VERSION__: string;
const RELEASE = typeof __APP_VERSION__ !== 'undefined' ? __APP_VERSION__ : 'dev-unknown';

// Safari/Vite peut signaler un modulepreload obsolète avant que React.lazy et
// les ErrorBoundary n'aient la main. Installer la récupération avant Sentry
// évite de transformer un simple déploiement en régression remontée aux ops.
installVitePreloadRecovery(RELEASE);

const SENTRY_IGNORE_ERRORS: (string | RegExp)[] = [
  'ResizeObserver loop limit exceeded',
  'ResizeObserver loop completed with undelivered notifications',
  'Non-Error promise rejection captured',
  'AbortError',
  'The user aborted a request',
  'NetworkError when attempting to fetch',
  'Failed to fetch',
  'Load failed',
  'NetworkError',
  /Script error\.?$/i,
  /gtag/i,
];

const SENTRY_DENY_URLS: (string | RegExp)[] = [
  /^chrome-extension:\/\//i,
  /^moz-extension:\/\//i,
  /^safari-extension:\/\//i,
  /^safari-web-extension:\/\//i,
  /^https?:\/\/localhost(:\d+)?\//i,
  /^https?:\/\/127\.0\.0\.1(:\d+)?\//i,
];

const PII_PATTERNS: { regex: RegExp; replacement: string }[] = [
  { regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, replacement: '[email-redacted]' },
  { regex: /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, replacement: '[jwt-redacted]' },
  { regex: /\b\d{11}\b/g, replacement: '[rpps-redacted]' },
];
const SENSITIVE_QUERY_PARAMS = [
  'email', 'token', 'token_hash', 'code', 'access_token', 'refresh_token',
  'recovery_token', 'confirmation_url', 'rpps',
];

function scrubString(s: string | undefined): string | undefined {
  if (!s) return s;
  let out = s;
  for (const { regex, replacement } of PII_PATTERNS) out = out.replace(regex, replacement);
  return out;
}

function scrubUrl(url: string | undefined): string | undefined {
  if (!url) return url;
  try {
    const u = new URL(url, 'http://x');
    for (const k of SENSITIVE_QUERY_PARAMS) {
      if (u.searchParams.has(k)) u.searchParams.set(k, '[redacted]');
    }
    if (u.hash && /access_token|refresh_token|token_hash|recovery|code/i.test(u.hash)) {
      u.hash = '#[redacted]';
    }
    return scrubString(u.toString());
  } catch {
    return scrubString(url);
  }
}

if (SENTRY_DSN) {
  Sentry.init({
    dsn: SENTRY_DSN,
    environment: import.meta.env.VITE_ENV || import.meta.env.MODE,
    release: RELEASE,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({
        // RGPD-friendly : la structure DOM est capturée mais pas le contenu
        // (emails, RPPS, montants, messages chat ne fuitent pas dans Sentry).
        maskAllText: true,
        maskAllInputs: true,
        blockAllMedia: true,
      }),
    ],
    // Sample adaptatif : pages publiques 5 %, pages auth 20 %, erreurs 100 %.
    tracesSampler: (samplingContext) => {
      const path = (samplingContext.location?.pathname ?? '');
      if (path.startsWith('/inscription') || path.startsWith('/aide') || path === '/' || path === '/connexion') return 0.05;
      return 0.2;
    },
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 1.0,
    ignoreErrors: SENTRY_IGNORE_ERRORS,
    denyUrls: SENTRY_DENY_URLS,
    beforeSend(event) {
      if (event.request?.url) event.request.url = scrubUrl(event.request.url);
      if (event.request?.headers) {
        delete (event.request.headers as Record<string, unknown>).Authorization;
        delete (event.request.headers as Record<string, unknown>).authorization;
        delete (event.request.headers as Record<string, unknown>).Cookie;
        delete (event.request.headers as Record<string, unknown>).cookie;
      }
      if (event.exception?.values) {
        for (const ex of event.exception.values) {
          if (ex.value) ex.value = scrubString(ex.value);
        }
      }
      if (event.message) event.message = scrubString(event.message) ?? event.message;
      if (event.breadcrumbs) {
        for (const bc of event.breadcrumbs) {
          if (bc.data && typeof bc.data === 'object') {
            const d = bc.data as Record<string, unknown>;
            if (typeof d.url === 'string') d.url = scrubUrl(d.url);
            if (typeof d.from === 'string') d.from = scrubUrl(d.from);
            if (typeof d.to === 'string') d.to = scrubUrl(d.to);
          }
          if (bc.message) bc.message = scrubString(bc.message);
        }
      }
      return event;
    },
  });
}

// Apply theme before render to avoid flash
const stored = localStorage.getItem('theme');
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
if (stored === 'dark' || (!stored && prefersDark)) {
  document.documentElement.classList.add('dark');
}

// Apply platform class on body for platform-specific CSS
import { getPlatform } from './lib/platform';
const platform = getPlatform();
document.body.classList.add(`platform-${platform}`);

// Capacitor keyboard: add/remove class when keyboard opens/closes
if (Capacitor.isNativePlatform()) {
  // 6d.2 : blocage du pinch-zoom UNIQUEMENT dans la coquille native (rendu
  // app). Appliqué au runtime — le HTML garde un viewport zoomable pour le
  // web (exigence d'accessibilité RGAA, texte agrandissable).
  document.querySelector('meta[name="viewport"]')?.setAttribute(
    'content',
    'viewport-fit=cover, width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no',
  );

  import('@capacitor/keyboard').then(({ Keyboard }) => {
    Keyboard.addListener('keyboardWillShow', () => {
      document.body.classList.add('keyboard-is-open');
    });
    Keyboard.addListener('keyboardWillHide', () => {
      document.body.classList.remove('keyboard-is-open');
    });
  }).catch(() => {});

  // Capacitor status bar: style adapté
  import('@capacitor/status-bar').then(({ StatusBar, Style }) => {
    const isDark = document.documentElement.classList.contains('dark');
    // Chez Capacitor, Dark = texte clair sur fond sombre et Light = texte
    // sombre sur fond clair.
    StatusBar.setStyle({ style: isDark ? Style.Dark : Style.Light }).catch(() => {});
    StatusBar.setBackgroundColor({ color: isDark ? '#1a1a2e' : '#ffffff' }).catch(() => {});
  }).catch(() => {});

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
    background: 'linear-gradient(90deg, #B91560 0%, #6E1F4F 100%)',
    color: '#fff',
    fontSize: '14px',
    fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    boxShadow: '0 2px 8px rgba(185,21,96,0.25)',
  });

  const text = document.createElement('span');
  text.textContent = 'Nouvelle version disponible';

  const btn = document.createElement('button');
  btn.textContent = 'Mettre à jour';
  Object.assign(btn.style, {
    background: '#fff',
    color: '#9B1456',
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
  const { SplashScreen } = await import('@capacitor/splash-screen');
  let deepLinkTraite = false;
  let splashMasque = false;

  const masquerSplash = async () => {
    if (splashMasque) return;
    splashMasque = true;
    await SplashScreen.hide().catch(() => {});
  };

  // Filet dur : un réseau lent ou absent ne doit jamais laisser le splash
  // natif bloqué. Les vérifications d'auth peuvent continuer dans React.
  const splashTimeout = window.setTimeout(() => { void masquerSplash(); }, 1_500);

  const appliquerLien = (rawUrl: string): boolean => {
    const route = normaliserLienJolene(rawUrl);
    if (!route) return false;
    deepLinkTraite = true;
    window.history.replaceState(null, '', route);
    window.dispatchEvent(new PopStateEvent('popstate'));
    return true;
  };

  // Deep links reçus lorsque l'app tourne. Le normaliseur conserve query +
  // fragment (recovery Supabase) et refuse toute origine externe.
  await CapApp.addListener('appUrlOpen', (event) => {
    const route = normaliserLienJolene(event.url);
    if (!route || !appliquerLien(event.url)) return;
    if (route.startsWith('/auth/psc/callback') || /^\/connexion\?.*\blogout=psc(?:&|$)/.test(route)) {
      void fermerNavigateurPsc();
    }
  });

  // Cold start : appUrlOpen n'est pas garanti avant le premier rendu sur les
  // deux plateformes, donc on consomme aussi explicitement l'URL de lancement.
  try {
    const launch = await CapApp.getLaunchUrl();
    if (launch?.url) appliquerLien(launch.url);
  } catch { /* aucune URL de lancement — flux normal */ }

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
    const rawPath = window.location.pathname;
    const currentPath = rawPath.length > 1 ? rawPath.replace(/\/+$/, '') : rawPath;
    const isMainRoute = MAIN_ROUTES.includes(currentPath);

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

  // StatusBar configuration — adapt to current theme
  try {
    const { StatusBar, Style } = await import("@capacitor/status-bar");
    const isDark = document.documentElement.classList.contains('dark');
    await StatusBar.setStyle({ style: isDark ? Style.Dark : Style.Light });
    if (Capacitor.getPlatform() === 'android') {
      await StatusBar.setBackgroundColor({ color: isDark ? '#6B3FA0' : '#FFFFFF' });
    }
  } catch { /* plugin StatusBar indisponible (web) — non bloquant */ }

  // Splash screen : la session locale est lue immédiatement. L'appel réseau
  // de rôle est borné et sauté hors-ligne afin de ne jamais bloquer le launch.
  try {
    const { supabase } = await import("./integrations/supabase/client");
    const dansDelai = async <T,>(promise: PromiseLike<T>, timeoutMs: number): Promise<T | null> => {
      let timer: number | undefined;
      try {
        return await Promise.race([
          Promise.resolve(promise),
          new Promise<null>((resolve) => {
            timer = window.setTimeout(() => resolve(null), timeoutMs);
          }),
        ]);
      } catch {
        return null;
      } finally {
        if (timer !== undefined) window.clearTimeout(timer);
      }
    };

    const sessionResult = await dansDelai(supabase.auth.getSession(), 600);
    const session = sessionResult?.data.session ?? null;

    if (session) {
      // User is logged in — navigate to their dashboard
      // The role check will happen in RouteProtegee, but we pre-navigate
      try {
        const { Network } = await import('@capacitor/network');
        const network = await dansDelai(Network.getStatus(), 250);
        if (!network?.connected || deepLinkTraite) return;

        const roleResult = await dansDelai(supabase.rpc('fn_get_my_role'), 850);
        const roleData = roleResult?.data;
        const role = typeof roleData === 'string'
          ? roleData
          : typeof roleData === 'object' && roleData !== null && 'role' in roleData && typeof roleData.role === 'string'
            ? roleData.role
            : undefined;
        let target: string | null = null;
        if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') target = '/admin';
        else if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') target = '/etablissement/tableau-de-bord';
        else if (role === 'ADMIN_GROUPE') target = '/groupe/tableau-de-bord';
        else if (role === 'SOIGNANT') target = '/soignant/tableau-de-bord';

        if (target && (window.location.pathname === '/' || window.location.pathname === '/connexion')) {
          window.history.replaceState(null, '', target);
        }
      } catch {
        // If role check fails, let normal auth flow handle it
      }
    }
  } catch { /* le flux auth React prend le relais */ }
  finally {
    window.clearTimeout(splashTimeout);
    await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()));
    await masquerSplash();
  }
}

void initNativePlugins().catch(() => {
  // Le filet 1,8 s masque malgré tout le splash si un plugin natif échoue.
});

// Configure keyboard behavior per-platform
import { configurerClavier } from './lib/platform';
configurerClavier();

// Session G5 — incrémente le compteur de sessions AVANT le premier rendu, pour
// que les prompts non urgents (push, installation PWA) lisent une valeur à jour
// (les effets enfants s'exécutent avant ceux du parent en React).
import { incrementerSession } from './lib/session-count';
incrementerSession();

createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={({ resetError }) => <SentryErrorFallback resetError={resetError} />}>
    <App />
  </Sentry.ErrorBoundary>
);

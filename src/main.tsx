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
    padding: '4px',
    opacity: '0.8',
  });
  close.addEventListener('click', () => banner.remove());

  banner.append(text, btn, close);
  document.body.prepend(banner);
}

import { SentryErrorFallback } from "./components/SentryErrorFallback";

createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={({ resetError }) => <SentryErrorFallback resetError={resetError} />}>
    <App />
  </Sentry.ErrorBoundary>
);

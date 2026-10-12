import { describe, expect, it } from 'vitest';
import type { ErrorEvent } from '@sentry/react';
import { isInjectedBrowserCspProbe } from './sentryInjectedScript';

// Signature minimale expurgée des deux événements du 12/10/2026 :
// 7e9a931f… (/connexion) et 47af7256… (/aide/pro-sante-connect).
const incident = (): ErrorEvent => ({
  type: undefined,
  timestamp: 100,
  exception: { values: [{
    type: 'EvalError',
    value: "Refused to evaluate a string as JavaScript because 'unsafe-eval' is not an allowed source of script in the following Content Security Policy directive: \"script-src 'self'\".",
    mechanism: { type: 'auto.browser.global_handlers.onunhandledrejection', handled: false },
    stacktrace: { frames: [
      { filename: '<anonymous>', function: 'next', lineno: 234, colno: 30 },
      { filename: '<anonymous>', function: 'predicate', lineno: 234, colno: 30 },
      { filename: '<anonymous>', function: 'eval' },
    ] },
  }] },
  breadcrumbs: [{ category: 'console', timestamp: 99.995, message: 'backpack: secure-background FromContentScriptTransportSender: Request [object Object]' }],
});

describe('sonde CSP injectée dans le navigateur', () => {
  it('reconnaît uniquement la signature observée avec son transport récent', () => {
    expect(isInjectedBrowserCspProbe(incident())).toBe(true);
  });
  it.each([
    ['fichier applicatif', (e: ErrorEvent) => { e.exception!.values![0].stacktrace!.frames![0].filename = 'https://jolene.app/assets/Connexion.js'; }],
    ['chemin applicatif absolu', (e: ErrorEvent) => { e.exception!.values![0].stacktrace!.frames![0].abs_path = 'https://jolene.app/assets/Connexion.js'; }],
    ['frame applicative ajoutée', (e: ErrorEvent) => { e.exception!.values![0].stacktrace!.frames!.push({ filename: '/src/main.tsx', function: 'login' }); }],
    ['autre sonde anonyme', (e: ErrorEvent) => { e.exception!.values![0].stacktrace!.frames![0].lineno = 235; }],
    ['autre erreur', (e: ErrorEvent) => { e.exception!.values![0].type = 'TypeError'; }],
    ['autre erreur CSP', (e: ErrorEvent) => { e.exception!.values![0].value = 'Refused to load script'; }],
    ['erreur capturée explicitement', (e: ErrorEvent) => { e.exception!.values![0].mechanism!.type = 'generic'; }],
    ['erreur traitée', (e: ErrorEvent) => { e.exception!.values![0].mechanism!.handled = true; }],
    ['erreur chaînée', (e: ErrorEvent) => { e.exception!.values!.push({ type: 'Error', value: 'échec métier' }); }],
    ['pas de pile', (e: ErrorEvent) => { delete e.exception!.values![0].stacktrace; }],
    ['pas de transport externe', (e: ErrorEvent) => { e.breadcrumbs = []; }],
    ['transport ancien', (e: ErrorEvent) => { e.breadcrumbs![0].timestamp = 94; }],
    ['transport ultérieur', (e: ErrorEvent) => { e.breadcrumbs![0].timestamp = 101; }],
    ['date inconnue', (e: ErrorEvent) => { delete e.timestamp; }],
    ['date transport inconnue', (e: ErrorEvent) => { delete e.breadcrumbs![0].timestamp; }],
  ])('conserve %s pour ne pas masquer une régression', (_label, modifier) => {
    const event = incident(); modifier(event);
    expect(isInjectedBrowserCspProbe(event)).toBe(false);
  });
});

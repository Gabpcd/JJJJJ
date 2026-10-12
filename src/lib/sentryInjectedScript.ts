import type { ErrorEvent } from '@sentry/react';

/**
 * JOLENE-APP-19 : sonde injectée par un navigateur, refusée par notre CSP.
 * Ne jamais ignorer tous les EvalError : un eval venant de Jolene doit rester
 * visible. On exige ensemble la pile exacte et la trace du transport externe.
 * Une preuve absente ou une pile enrichie reste envoyée à Sentry.
 */
export function isInjectedBrowserCspProbe(event: ErrorEvent): boolean {
  const values = event.exception?.values;
  if (values?.length !== 1) return false;
  const exception = values[0];
  if (exception.type !== 'EvalError'
    || !exception.value?.startsWith("Refused to evaluate a string as JavaScript because 'unsafe-eval' is not an allowed source of script in the following Content Security Policy directive:")
    || exception.mechanism?.type !== 'auto.browser.global_handlers.onunhandledrejection'
    || exception.mechanism.handled !== false) return false;

  const frames = exception.stacktrace?.frames;
  if (frames?.length !== 3) return false;
  if (frames.some(frame => [frame.filename, frame.abs_path].some(path => path && path !== '<anonymous>'))) return false;
  if (frames.map(frame => frame.function).join(',') !== 'next,predicate,eval') return false;
  if (frames.slice(0, 2).some(frame => frame.lineno !== 234 || frame.colno !== 30)) return false;

  // Une extension simplement installée ne suffit pas : son transport doit
  // avoir été observé dans les cinq secondes précédant cette sonde précise.
  if (typeof event.timestamp !== 'number') return false;
  return event.breadcrumbs?.some(breadcrumb =>
    breadcrumb.category === 'console'
    && /^backpack: secure-background FromContentScriptTransportSender: (Request|Response)\b/.test(breadcrumb.message ?? '')
    && typeof breadcrumb.timestamp === 'number'
    && event.timestamp! - breadcrumb.timestamp >= 0
    && event.timestamp! - breadcrumb.timestamp <= 5
  ) ?? false;
}

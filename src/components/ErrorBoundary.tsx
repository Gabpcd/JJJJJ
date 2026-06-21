import React from "react";
import * as Sentry from "@sentry/react";

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: React.ErrorInfo | null;
}

export class ErrorBoundary extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error, errorInfo: null };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // Console uniquement (PAS via logger) : on capture l'exception UNE SEULE
    // fois ci-dessous, avec le component stack en CONTEXTE. Avant, les deux
    // logger.error créaient des issues Sentry parasites en doublon
    // ("ErrorBoundary a intercepté…" + "Component stack:: <route>") en plus de
    // la vraie exception → 1 bug = jusqu'à 3 entrées dans le feed.
    console.error("[ErrorBoundary]", error, info.componentStack);
    // Capture unique avec le component stack attaché en contexte React.
    try {
      Sentry.captureException(error, {
        contexts: { react: { componentStack: info.componentStack } },
        tags: { boundary: 'AppErrorBoundary' },
      });
    } catch { /* noop */ }
    this.setState({ errorInfo: info });

    // Chunk load failure après déploiement : auto-reload UNE fois.
    const msg = (error?.message || '').toLowerCase();
    if (
      (msg.includes('importing a module script failed') ||
       msg.includes('failed to fetch dynamically imported module') ||
       msg.includes('loading chunk') ||
       msg.includes('loading css chunk')) &&
      sessionStorage.getItem('chunk-boundary-retry') !== '1'
    ) {
      sessionStorage.setItem('chunk-boundary-retry', '1');
      window.location.reload();
    }
  }

  render() {
    if (this.state.hasError) {
      const error = this.state.error;
      const errMsg = error?.message || String(error) || 'Erreur inconnue';
      // Afficher les détails techniques en dev OU si ?debug=1 dans l'URL
      // (pour permettre à l'équipe de diagnostiquer sans pousser un build dev).
      const showDetails = import.meta.env.DEV ||
        (typeof window !== 'undefined' && window.location.search.includes('debug=1'));
      return (
        <div className="min-h-[100dvh] flex items-center justify-center bg-background p-6">
          <div className="text-center max-w-2xl space-y-4">
            <h1 className="text-2xl font-bold text-foreground">
              Une erreur est survenue
            </h1>
            <p className="text-muted-foreground">
              L'application a rencontré un problème inattendu. Veuillez rafraîchir la page.
            </p>
            {showDetails && (
              <details className="text-left bg-destructive/5 border border-destructive/30 rounded-lg p-4 mt-4">
                <summary className="cursor-pointer text-sm font-semibold text-destructive">
                  Détails techniques
                </summary>
                <pre className="text-xs text-foreground mt-2 whitespace-pre-wrap break-words font-mono">{errMsg}</pre>
                {error?.stack && (
                  <pre className="text-[10px] text-muted-foreground mt-2 whitespace-pre-wrap break-words font-mono max-h-64 overflow-auto">{error.stack}</pre>
                )}
                {this.state.errorInfo?.componentStack && (
                  <pre className="text-[10px] text-muted-foreground mt-2 whitespace-pre-wrap break-words font-mono max-h-64 overflow-auto">{this.state.errorInfo.componentStack}</pre>
                )}
              </details>
            )}
            <button
              onClick={() => window.location.reload()}
              className="inline-flex items-center justify-center rounded-md bg-primary px-6 py-3 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 transition-colors"
            >
              Rafraîchir la page
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

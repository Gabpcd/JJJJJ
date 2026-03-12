import React from "react";
import { logger } from "@/lib/logger";

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
}

export class ErrorBoundary extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    if (import.meta.env.DEV) {
      logger.error("ErrorBoundary a intercepté une erreur", error);
      logger.debug("Component stack:", info.componentStack);
    }
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-background p-6">
          <div className="text-center max-w-md space-y-4">
            <h1 className="text-2xl font-bold text-foreground">
              Une erreur est survenue
            </h1>
            <p className="text-muted-foreground">
              L'application a rencontré un problème inattendu. Veuillez rafraîchir la page.
            </p>
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

import { Component, ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  section?: string;
}

interface State {
  hasError: boolean;
}

export class SectionErrorBoundary extends Component<Props, State> {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error) {
    console.error(`[${this.props.section || 'Section'}] Error:`, error);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="card-base text-center py-8">
          <p className="text-sm text-muted-foreground">Cette section n'a pas pu se charger.</p>
          <button
            onClick={() => this.setState({ hasError: false })}
            className="text-primary text-sm mt-2 hover:underline"
          >
            Réessayer
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

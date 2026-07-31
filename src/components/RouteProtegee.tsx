import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { ChargementPage } from '@/components/ChargementPage';

interface RouteProtegeeProps {
  rolesAutorises: string[];
  children: React.ReactNode;
}

export function RouteProtegee({ rolesAutorises, children }: RouteProtegeeProps) {
  const { user, session, loading: authLoading, deconnexion } = useAuth();
  const {
    role: roleServeur,
    loading: roleLoading,
    error: erreurRole,
    retry: reessayerRole,
  } = useRole();

  if (authLoading || roleLoading) return <ChargementPage />;
  if (!user || !session) return <Navigate to="/connexion" replace />;

  // C2: Vérifier que l'email est confirmé
  if (!session.user.email_confirmed_at) {
    return <Navigate to="/confirmer-email" replace />;
  }

  if (erreurRole) {
    return (
      <main className="min-h-[100dvh] flex items-center justify-center bg-background px-4">
        <div className="card-base max-w-md w-full text-center space-y-4" role="alert" aria-live="assertive">
          <h1 className="text-xl font-bold text-foreground">Votre espace est momentanément indisponible</h1>
          <p className="text-sm text-muted-foreground">
            Votre session est toujours active. Réessayez dans un instant.
          </p>
          <button type="button" className="btn-primary w-full" onClick={reessayerRole}>
            Réessayer
          </button>
        </div>
      </main>
    );
  }

  if (!roleServeur || roleServeur === 'INCONNU') {
    return (
      <main className="min-h-[100dvh] flex items-center justify-center bg-background px-4">
        <div className="card-base max-w-md w-full text-center space-y-4" role="alert" aria-live="assertive">
          <h1 className="text-xl font-bold text-foreground">Accès à cet espace non autorisé</h1>
          <p className="text-sm text-muted-foreground">
            Votre session ne correspond plus à un compte actif pour cet espace.
          </p>
          <button type="button" className="btn-primary w-full" onClick={() => void deconnexion()}>
            Se reconnecter
          </button>
        </div>
      </main>
    );
  }

  if (!rolesAutorises.includes(roleServeur)) {
    // Redirect to the user's own dashboard
    switch (roleServeur) {
      case 'SOIGNANT': return <Navigate to="/soignant/tableau-de-bord" replace />;
      case 'ADMIN_ETABLISSEMENT': return <Navigate to="/etablissement/tableau-de-bord" replace />;
      case 'ADMIN_GROUPE': return <Navigate to="/groupe/tableau-de-bord" replace />;
      case 'ADMIN_PLATEFORME': return <Navigate to="/admin" replace />;
      default: return <Navigate to="/" replace />;
    }
  }

  return <>{children}</>;
}

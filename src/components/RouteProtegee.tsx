import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ChargementPage } from '@/components/ChargementPage';

interface RouteProtegeeProps {
  rolesAutorises: string[];
  children: React.ReactNode;
}

export function RouteProtegee({ rolesAutorises, children }: RouteProtegeeProps) {
  const { user, session, loading } = useAuth();

  if (loading) return <ChargementPage />;
  if (!user || !session) return <Navigate to="/connexion" replace />;

  // Lire le rôle depuis app_metadata (non modifiable côté client)
  // Fallback sur user_metadata uniquement si app_metadata pas encore défini
  const roleServeur = session.user.app_metadata?.role || user.role;

  if (!roleServeur || !rolesAutorises.includes(roleServeur)) {
    switch (roleServeur) {
      case 'SOIGNANT': return <Navigate to="/soignant/tableau-de-bord" replace />;
      case 'ETABLISSEMENT': return <Navigate to="/etablissement/tableau-de-bord" replace />;
      case 'ADMIN_GROUPE': return <Navigate to="/groupe/tableau-de-bord" replace />;
      default: return <Navigate to="/" replace />;
    }
  }

  return <>{children}</>;
}

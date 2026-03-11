import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ChargementPage } from '@/components/ChargementPage';

interface RouteProtegeeProps {
  rolesAutorises: string[];
  children: React.ReactNode;
}

export function RouteProtegee({ rolesAutorises, children }: RouteProtegeeProps) {
  const { user, loading } = useAuth();

  if (loading) return <ChargementPage />;
  if (!user) return <Navigate to="/connexion" replace />;

  if (!rolesAutorises.includes(user.role)) {
    switch (user.role) {
      case 'SOIGNANT': return <Navigate to="/soignant/tableau-de-bord" replace />;
      case 'ETABLISSEMENT': return <Navigate to="/etablissement/tableau-de-bord" replace />;
      case 'ADMIN_GROUPE': return <Navigate to="/groupe/tableau-de-bord" replace />;
      default: return <Navigate to="/" replace />;
    }
  }

  return <>{children}</>;
}

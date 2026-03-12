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
  const { user, session, loading: authLoading } = useAuth();
  const { role: roleServeur, loading: roleLoading } = useRole();

  if (authLoading || roleLoading) return <ChargementPage />;
  if (!user || !session) return <Navigate to="/connexion" replace />;

  if (!roleServeur || roleServeur === 'INCONNU' || !rolesAutorises.includes(roleServeur)) {
    switch (roleServeur) {
      case 'SOIGNANT': return <Navigate to="/soignant/tableau-de-bord" replace />;
      case 'ETABLISSEMENT': return <Navigate to="/etablissement/tableau-de-bord" replace />;
      case 'ADMIN_GROUPE': return <Navigate to="/groupe/tableau-de-bord" replace />;
      default: return <Navigate to="/" replace />;
    }
  }

  return <>{children}</>;
}

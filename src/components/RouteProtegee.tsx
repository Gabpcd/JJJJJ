import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { ChargementPage } from '@/components/ChargementPage';
import { AdminMfaGate } from '@/components/admin/AdminMfaGate';

interface RouteProtegeeProps {
  rolesAutorises: string[];
  children: React.ReactNode;
}

const ADMIN_EMAILS_SANS_MFA = new Set([
  'admin@jolene.app',
  'gabrielle.pcd@outlook.com',
]);

export function RouteProtegee({ rolesAutorises, children }: RouteProtegeeProps) {
  const { user, session, loading: authLoading } = useAuth();
  const { role: roleServeur, loading: roleLoading } = useRole();

  if (authLoading || roleLoading) return <ChargementPage />;
  if (!user || !session) return <Navigate to="/connexion" replace />;

  // C2: Vérifier que l'email est confirmé
  if (!session.user.email_confirmed_at) {
    return <Navigate to="/confirmer-email" replace />;
  }

  if (!roleServeur || roleServeur === 'INCONNU') {
    return <Navigate to="/" replace />;
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

  // Les deux comptes fondateurs nominatifs sont les seules exceptions sans
  // second facteur. Les autres comptes administrateur conservent le gate TOTP.
  if (
    roleServeur === 'ADMIN_PLATEFORME'
    && !ADMIN_EMAILS_SANS_MFA.has(user.email?.trim().toLowerCase() ?? '')
  ) {
    return <AdminMfaGate>{children}</AdminMfaGate>;
  }

  return <>{children}</>;
}

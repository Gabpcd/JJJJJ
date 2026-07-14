import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { ChargementPage } from '@/components/ChargementPage';
import { RouteProtegee } from '@/components/RouteProtegee';
import { useAccesAdmin } from '@/hooks/useAccesAdmin';
import type { AdminAccessGroup } from '@/lib/adminAccess';

interface AdminAccessGateProps {
  accesRequis: AdminAccessGroup;
  children: ReactNode;
}

function AdminAccessGate({ accesRequis, children }: AdminAccessGateProps) {
  const { loading, aAcces } = useAccesAdmin();

  if (loading) return <ChargementPage />;
  if (!aAcces(accesRequis)) {
    return <Navigate to="/acces-admin-indisponible" replace />;
  }

  return <>{children}</>;
}

export function RouteAdminProtegee({ accesRequis, children }: AdminAccessGateProps) {
  return (
    <RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}>
      <AdminAccessGate accesRequis={accesRequis}>{children}</AdminAccessGate>
    </RouteProtegee>
  );
}

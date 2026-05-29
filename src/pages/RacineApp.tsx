import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { isNative } from '@/lib/platform';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ChargementPage } from '@/components/ChargementPage';
import PageAccueil from '@/pages/PageAccueil';
import PageConnexion from '@/pages/PageConnexion';

/**
 * Point d'entrée racine "/" :
 * - Web (desktop + Safari mobile) : landing marketing (PageAccueil).
 * - App native (Capacitor iOS/Android) : pas de vitrine marketing.
 *   → si session active, redirige vers le dashboard du rôle ;
 *   → sinon, affiche directement l'écran de connexion.
 */
export default function RacineApp() {
  const { session, loading } = useAuth();
  const [rolePath, setRolePath] = useState<string | null>(null);
  const [resolvingRole, setResolvingRole] = useState(false);

  const native = isNative();

  useEffect(() => {
    if (!native) return;
    if (loading) return;
    if (!session) {
      setRolePath(null);
      return;
    }
    let cancelled = false;
    setResolvingRole(true);
    (async () => {
      try {
        const { data } = await supabase.rpc('fn_get_my_role' as any);
        const role = typeof data === 'string' ? data : (data as any)?.role;
        if (cancelled) return;
        if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') setRolePath('/admin');
        else if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') setRolePath('/etablissement/tableau-de-bord');
        else if (role === 'ADMIN_GROUPE') setRolePath('/groupe/tableau-de-bord');
        else if (role === 'SOIGNANT') setRolePath('/soignant/tableau-de-bord');
        else setRolePath(null);
      } catch {
        if (!cancelled) setRolePath(null);
      } finally {
        if (!cancelled) setResolvingRole(false);
      }
    })();
    return () => { cancelled = true; };
  }, [native, session, loading]);

  // Web : landing marketing classique
  if (!native) return <PageAccueil />;

  // Natif : attendre la résolution session/rôle
  if (loading || resolvingRole) return <ChargementPage />;

  // Natif + session + rôle résolu → dashboard
  if (session && rolePath) return <Navigate to={rolePath} replace />;

  // Natif sans session → écran de connexion direct
  return <PageConnexion />;
}

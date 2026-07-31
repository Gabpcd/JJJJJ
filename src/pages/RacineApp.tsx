import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { isNative } from '@/lib/platform';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ChargementPage } from '@/components/ChargementPage';
import PageAccueil from '@/pages/PageAccueil';
import PageConnexion from '@/pages/PageConnexion';
import { logger } from '@/lib/logger';
import { avecDelai } from '@/lib/avecDelai';

type EtatResolutionRole = {
  sessionId: string | null;
  statut: 'inactif' | 'chargement' | 'resolu' | 'absent' | 'erreur';
  chemin: string | null;
};

function cheminPourRole(role: unknown): string | null {
  if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') return '/admin';
  if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') return '/etablissement/tableau-de-bord';
  if (role === 'ADMIN_GROUPE') return '/groupe/tableau-de-bord';
  if (role === 'SOIGNANT') return '/soignant/tableau-de-bord';
  return null;
}

/**
 * Point d'entrée racine "/" :
 * - Web (desktop + Safari mobile) : landing marketing (PageAccueil).
 * - App native (Capacitor iOS/Android) : pas de vitrine marketing.
 *   → si session active, redirige vers le dashboard du rôle ;
 *   → sinon, affiche directement l'écran de connexion.
 */
export default function RacineApp() {
  const { session, loading } = useAuth();
  const [resolutionRole, setResolutionRole] = useState<EtatResolutionRole>({
    sessionId: null,
    statut: 'inactif',
    chemin: null,
  });
  const [tentativeRole, setTentativeRole] = useState(0);

  const native = isNative();
  const sessionId = session?.user.id ?? null;

  useEffect(() => {
    if (!native) return;
    if (loading) return;
    if (!session) {
      setResolutionRole({ sessionId: null, statut: 'inactif', chemin: null });
      return;
    }
    let cancelled = false;
    const sessionEnCours = session.user.id;
    setResolutionRole({ sessionId: sessionEnCours, statut: 'chargement', chemin: null });

    // Le rôle placé dans app_metadata est signé par Supabase Auth et ne
    // peut pas être modifié par l'utilisateur. Il suffit pour choisir la route
    // d'interface ; les données et actions restent protégées par RLS/RPC.
    // Surtout, une indisponibilité momentanée de la base ne doit pas bloquer
    // une session native déjà authentifiée (cas constaté pendant l'App Review).
    const cheminRoleSigne = cheminPourRole(session.user.app_metadata?.role);
    if (cheminRoleSigne) {
      setResolutionRole({
        sessionId: sessionEnCours,
        statut: 'resolu',
        chemin: cheminRoleSigne,
      });
      return;
    }

    // Compatibilité avec les comptes anciens qui n'ont pas encore de rôle
    // signé dans app_metadata.
    (async () => {
      try {
        const { data, error } = await avecDelai(
          supabase.rpc('fn_get_my_role' as any),
          10_000,
          'La résolution de votre espace a pris trop de temps',
        );
        if (error) {
          if (!cancelled) {
            logger.error('[RACINE_APP] Résolution du rôle indisponible, session conservée', error);
            setResolutionRole({ sessionId: sessionEnCours, statut: 'erreur', chemin: null });
          }
          return;
        }
        const role = typeof data === 'string' ? data : (data as any)?.role;
        if (cancelled) return;
        const chemin = cheminPourRole(role);
        setResolutionRole({
          sessionId: sessionEnCours,
          statut: chemin ? 'resolu' : 'absent',
          chemin,
        });
      } catch (error) {
        if (!cancelled) {
          logger.error('[RACINE_APP] Échec inattendu de résolution du rôle, session conservée', error);
          setResolutionRole({ sessionId: sessionEnCours, statut: 'erreur', chemin: null });
        }
      }
    })();
    return () => { cancelled = true; };
  }, [native, session, loading, tentativeRole]);

  // Web : landing marketing classique
  if (!native) return <PageAccueil />;

  const resolutionSessionCourante = resolutionRole.sessionId === sessionId;

  // Natif : attendre la résolution de la session puis du rôle correspondant
  // précisément à cette session (évite une redirection avec un rôle périmé).
  if (
    loading
    || (session && (!resolutionSessionCourante || resolutionRole.statut === 'inactif' || resolutionRole.statut === 'chargement'))
  ) {
    return <ChargementPage />;
  }

  // Natif + session + rôle résolu → dashboard
  if (session && resolutionSessionCourante && resolutionRole.statut === 'resolu' && resolutionRole.chemin) {
    return <Navigate to={resolutionRole.chemin} replace />;
  }

  // L'appel serveur a échoué : ne jamais afficher la connexion (ni laisser
  // croire à un compte incomplet). La session reste active et l'utilisateur
  // peut relancer uniquement la résolution du rôle.
  if (session && resolutionSessionCourante && resolutionRole.statut === 'erreur') {
    return (
      <main className="min-h-[100dvh] flex items-center justify-center bg-background px-4">
        <div className="card-base max-w-md w-full text-center space-y-4" role="alert" aria-live="assertive">
          <h1 className="text-xl font-bold text-foreground">Votre espace est momentanément indisponible</h1>
          <p className="text-sm text-muted-foreground">
            Votre session est toujours active. Vérifiez votre connexion puis réessayez.
          </p>
          <button
            type="button"
            className="btn-primary w-full"
            onClick={() => setTentativeRole((tentative) => tentative + 1)}
          >
            Réessayer
          </button>
        </div>
      </main>
    );
  }

  // Natif sans session, ou RPC réussie sans rôle réel → écran de connexion.
  return <PageConnexion />;
}

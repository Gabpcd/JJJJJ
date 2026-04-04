import { toast } from "sonner";

/**
 * Détecte les erreurs réseau et session expirée sur les réponses Supabase.
 * À appeler dans les blocs catch des requêtes Supabase critiques.
 * Retourne true si l'erreur a été gérée (réseau ou auth), false sinon.
 */
export function gererErreurSupabase(error: unknown, retryFn?: () => void): boolean {
  if (!error) return false;

  const msg = typeof error === 'object' && error !== null
    ? (error as any).message || (error as any).details || ''
    : String(error);
  const status = typeof error === 'object' && error !== null
    ? (error as any).status || (error as any).code
    : undefined;

  // Session expirée (401/403)
  if (status === 401 || status === 403 || msg.includes('JWT expired') || msg.includes('invalid claim') || msg.includes('session_not_found')) {
    toast.error('Votre session a expiré — Veuillez vous reconnecter', {
      duration: 5000,
    });
    // Redirect after a short delay so user sees the toast
    setTimeout(() => {
      window.location.replace('/connexion');
    }, 1500);
    return true;
  }

  // Erreur réseau
  if (msg.includes('Failed to fetch') || msg.includes('NetworkError') || msg.includes('ERR_NETWORK') || msg.includes('net::') || msg.includes('ECONNREFUSED') || msg.includes('Load failed')) {
    toast.error('Erreur de connexion — Vérifiez votre connexion internet', {
      action: retryFn ? { label: 'Réessayer', onClick: retryFn } : undefined,
      duration: 8000,
    });
    return true;
  }

  return false;
}

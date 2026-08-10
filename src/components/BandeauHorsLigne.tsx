import React, { useCallback, useEffect, useRef, useState } from 'react';
import { WifiOff, RefreshCw } from 'lucide-react';

const DELAI_VERIFICATION_MS = 5_000;

/**
 * `navigator.onLine` est seulement un indice (Safari et certaines WebViews
 * Capacitor peuvent le laisser à `false` alors que les requêtes aboutissent).
 * Une réponse HTTP, même non-2xx, prouve que le réseau est joignable.
 */
async function connexionReellementDisponible(): Promise<boolean> {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), DELAI_VERIFICATION_MS);
  try {
    const response = await fetch('/manifest.webmanifest', {
      method: 'HEAD',
      cache: 'no-store',
      credentials: 'same-origin',
      signal: controller.signal,
    });
    return response.status > 0;
  } catch {
    return false;
  } finally {
    window.clearTimeout(timeout);
  }
}

export function BandeauHorsLigne() {
  // Pas de flash « hors-ligne » au montage : on confirme d'abord par une vraie
  // requête lorsque le navigateur prétend être déconnecté.
  const [horsLigne, setHorsLigne] = useState(false);
  const [verificationEnCours, setVerificationEnCours] = useState(false);
  const monteRef = useRef(true);

  const verifier = useCallback(async () => {
    setVerificationEnCours(true);
    const disponible = await connexionReellementDisponible();
    if (monteRef.current) {
      setHorsLigne(!disponible);
      setVerificationEnCours(false);
    }
    return disponible;
  }, []);

  useEffect(() => {
    monteRef.current = true;
    // Un événement `offline` doit lui aussi être confirmé : il peut être émis
    // pendant un changement d'interface réseau sans perte de connectivité.
    const goOffline = () => { void verifier(); };
    const goOnline = () => setHorsLigne(false);
    window.addEventListener('offline', goOffline);
    window.addEventListener('online', goOnline);
    if (!navigator.onLine) void verifier();
    return () => {
      monteRef.current = false;
      window.removeEventListener('offline', goOffline);
      window.removeEventListener('online', goOnline);
    };
  }, [verifier]);

  if (!horsLigne) return null;

  return (
    <div
      className="pointer-events-none fixed top-0 left-0 right-0 bg-warning text-warning-foreground text-sm z-[45] flex items-center justify-center flex-wrap gap-1 sm:gap-2"
      style={{ paddingTop: 'calc(0.5rem + env(safe-area-inset-top))', paddingBottom: '0.5rem' }}
      role="alert"
    >
      <WifiOff className="h-4 w-4 flex-shrink-0" aria-hidden="true" />
      <span>Pas de connexion internet</span>
      <button
        type="button"
        onClick={() => { void verifier(); }}
        disabled={verificationEnCours}
        className="pointer-events-auto ml-2 inline-flex items-center gap-1 min-h-[44px] min-w-[44px] px-3 py-1 rounded-lg bg-warning-foreground/10 text-warning-foreground text-xs font-medium hover:bg-warning-foreground/20 transition-colors disabled:opacity-60"
        aria-label="Réessayer la connexion"
      >
        <RefreshCw className={`h-3.5 w-3.5 ${verificationEnCours ? 'animate-spin' : ''}`} aria-hidden="true" />
        {verificationEnCours ? 'Vérification…' : 'Réessayer'}
      </button>
    </div>
  );
}

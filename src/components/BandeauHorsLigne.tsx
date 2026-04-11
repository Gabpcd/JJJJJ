import React, { useState, useEffect } from 'react';
import { WifiOff, RefreshCw } from 'lucide-react';

export function BandeauHorsLigne() {
  const [horsLigne, setHorsLigne] = useState(!navigator.onLine);

  useEffect(() => {
    const goOffline = () => setHorsLigne(true);
    const goOnline = () => setHorsLigne(false);
    window.addEventListener('offline', goOffline);
    window.addEventListener('online', goOnline);
    return () => {
      window.removeEventListener('offline', goOffline);
      window.removeEventListener('online', goOnline);
    };
  }, []);

  if (!horsLigne) return null;

  return (
    <div
      className="fixed top-0 left-0 right-0 bg-warning text-warning-foreground text-sm z-[9998] flex items-center justify-center flex-wrap gap-1 sm:gap-2"
      style={{ paddingTop: 'calc(0.5rem + env(safe-area-inset-top))', paddingBottom: '0.5rem' }}
      role="alert"
    >
      <WifiOff className="h-4 w-4 flex-shrink-0" aria-hidden="true" />
      <span>Pas de connexion internet</span>
      <button
        onClick={() => window.location.reload()}
        className="ml-2 inline-flex items-center gap-1 min-h-[44px] min-w-[44px] px-3 py-1 rounded-lg bg-warning-foreground/10 text-warning-foreground text-xs font-medium hover:bg-warning-foreground/20 transition-colors"
        aria-label="Réessayer la connexion"
      >
        <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
        Réessayer
      </button>
    </div>
  );
}

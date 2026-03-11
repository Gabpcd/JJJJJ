import React, { useState, useEffect } from 'react';
import { WifiOff } from 'lucide-react';

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
    <div className="fixed top-0 left-0 right-0 bg-warning text-warning-foreground text-center text-sm py-2 z-50 flex items-center justify-center gap-2">
      <WifiOff className="h-4 w-4" />
      📡 Vous êtes hors-ligne — les pointages seront synchronisés automatiquement
    </div>
  );
}

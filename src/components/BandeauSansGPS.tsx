import React from 'react';
import { AlertTriangle } from 'lucide-react';

export function BandeauSansGPS() {
  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2">
      <AlertTriangle className="h-4 w-4 text-warning flex-shrink-0" />
      <p className="text-sm text-warning font-medium">
        Ton pointage est bien pris en compte. Sans localisation, l'établissement le validera manuellement — rien à faire de ton côté.
      </p>
    </div>
  );
}

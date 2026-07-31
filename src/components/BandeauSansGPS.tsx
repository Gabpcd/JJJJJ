import React from 'react';
import { AlertTriangle } from 'lucide-react';

export function BandeauSansGPS() {
  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 flex items-center gap-2">
      <AlertTriangle className="h-4 w-4 text-warning flex-shrink-0" />
      <p className="text-sm text-warning font-medium">
        Pointage sans localisation activé. Lorsque tu pointeras, l'établissement validera manuellement ta présence.
      </p>
    </div>
  );
}

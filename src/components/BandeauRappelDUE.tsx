import React from 'react';
import { AlertTriangle, ExternalLink } from 'lucide-react';

export function BandeauRappelDUE() {
  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 flex items-start gap-3">
      <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
      <div>
        <p className="text-sm font-semibold text-warning">
          ⚠️ Rappel légal : effectuez la Déclaration Unique d'Embauche (DUE) sur net-entreprises.fr avant le début de la mission.
        </p>
        <a
          href="https://www.net-entreprises.fr"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-2"
        >
          Accéder à net-entreprises.fr <ExternalLink className="h-3 w-3" />
        </a>
      </div>
    </div>
  );
}

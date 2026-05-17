import React from 'react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { AlertTriangle } from 'lucide-react';

type Props = {
  count: number;
  onVoir: () => void;
};

/**
 * CP-LITIGES-7b-3 — Banner litiges en médiation > 7 jours.
 *
 * Le count est calculé en amont (dans AdminModeration) via COUNT SQL :
 *   statut='EN_MEDIATION' AND escalade_auto_le < now() - 7 jours.
 * Le bouton "Voir" préfiltre la liste côté parent.
 */
export function MediationBanner({ count, onVoir }: Props) {
  if (count <= 0) return null;
  return (
    <div
      role="alert"
      className="flex flex-wrap items-center gap-3 rounded-lg border border-orange-300 bg-orange-50 p-3 text-sm"
      data-testid="mediation-banner"
      data-count={count}
    >
      <AlertTriangle className="h-5 w-5 shrink-0 text-orange-600" aria-hidden />
      <p className="flex-1 font-medium text-orange-900">
        {count} litige{count > 1 ? 's' : ''} en médiation depuis plus de 7
        jours nécessite{count > 1 ? 'nt' : ''} votre attention.
      </p>
      <BoutonY2K
        size="sm"
        variant="secondary"
        onClick={onVoir}
        className="border-orange-400 text-orange-900"
      >
        Voir
      </BoutonY2K>
    </div>
  );
}

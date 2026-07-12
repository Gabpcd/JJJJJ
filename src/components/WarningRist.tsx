import { PLAFONDS_RIST } from '@/constantes/loi';
import { getLabelProfession } from '@/lib/constantes';

interface WarningRistProps {
  profession: string;
  tauxSaisi: number;
  ristPlafondActif: boolean;
  estSecteurPublic?: boolean;
}

export function WarningRist({ profession, tauxSaisi, ristPlafondActif, estSecteurPublic }: WarningRistProps) {
  if (!ristPlafondActif || !estSecteurPublic) return null;
  const plafond = PLAFONDS_RIST[profession];
  if (!plafond || tauxSaisi <= plafond) return null;

  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 text-warning">
      <p className="font-semibold text-sm mb-1">⚠️ Attention — Loi Rist (Décret 2023-920)</p>
      <p className="text-xs">
        Le taux saisi ({tauxSaisi.toFixed(2)} €/h) dépasse le plafond légal de{' '}
        <strong>{plafond.toFixed(2)} €/h</strong> pour les {getLabelProfession(profession)} en CDD, y compris court.
      </p>
      <p className="text-xs mt-1">
        Le taux sera automatiquement plafonné à {plafond.toFixed(2)} €/h par le système lors de la création.
      </p>
    </div>
  );
}

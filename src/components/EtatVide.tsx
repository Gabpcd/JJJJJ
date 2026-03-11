import { LucideIcon } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface EtatVideProps {
  icone: LucideIcon;
  titre: string;
  sousTitre: string;
  boutonLabel?: string;
  boutonRoute?: string;
  boutonDisabled?: boolean;
}

export function EtatVide({ icone: Icone, titre, sousTitre, boutonLabel, boutonRoute, boutonDisabled }: EtatVideProps) {
  const navigate = useNavigate();

  return (
    <div className="flex flex-col items-center justify-center py-12 px-4 text-center">
      <Icone className="h-16 w-16 text-primary/30 mb-4" />
      <h3 className="text-lg font-semibold text-foreground mb-2">{titre}</h3>
      <p className="text-sm text-muted-foreground max-w-sm mb-6">{sousTitre}</p>
      {boutonLabel && boutonRoute && (
        <button
          onClick={() => navigate(boutonRoute)}
          disabled={boutonDisabled}
          className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {boutonLabel}
        </button>
      )}
    </div>
  );
}

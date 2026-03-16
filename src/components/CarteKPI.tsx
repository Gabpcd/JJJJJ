import React from 'react';
import { LucideIcon } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface CarteKPIProps {
  icone: LucideIcon;
  valeur: string | number;
  label: string;
  sousLabel?: string;
  couleurIcone: string;
  couleurFond: string;
  lien?: string;
}

export function CarteKPI({ icone: Icone, valeur, label, sousLabel, couleurIcone, couleurFond, lien }: CarteKPIProps) {
  const navigate = useNavigate();
  const isClickable = !!lien;

  return (
    <div
      className={`card-kpi ${isClickable ? 'cursor-pointer hover:shadow-md hover:ring-1 hover:ring-primary/20 transition-all' : ''}`}
      onClick={isClickable ? () => navigate(lien!) : undefined}
    >
      <div className="flex items-start gap-3">
        <div className={`rounded-xl p-2.5 ${couleurFond}`}>
          <Icone className={`h-5 w-5 ${couleurIcone}`} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-2xl font-bold text-foreground">{valeur || '—'}</p>
          <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
          {sousLabel && <p className="text-[10px] text-muted-foreground mt-0.5">{sousLabel}</p>}
        </div>
      </div>
    </div>
  );
}

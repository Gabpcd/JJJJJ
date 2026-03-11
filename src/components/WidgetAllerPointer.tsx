import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Clock, MapPin } from 'lucide-react';
import { differenceInMinutes, format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface WidgetAllerPointerProps {
  mission: any;
}

export function WidgetAllerPointer({ mission }: WidgetAllerPointerProps) {
  const navigate = useNavigate();
  const minutes = differenceInMinutes(new Date(mission.debut_le), new Date());
  if (minutes > 60 || minutes < -30) return null;

  const etabNom = mission.etablissements?.nom || 'Établissement';

  return (
    <div className="bg-primary/5 border-2 border-primary/30 rounded-2xl p-4 mb-4">
      <div className="flex items-center gap-2 text-primary text-sm font-semibold mb-2">
        <Clock className="h-4 w-4" />
        🕐 Mission dans {minutes > 0 ? `${minutes} min` : 'maintenant'}
      </div>
      <h3 className="font-semibold text-foreground text-sm">{mission.intitule} — {etabNom}</h3>
      <p className="text-xs text-muted-foreground mt-1">
        {format(new Date(mission.debut_le), "HH:mm", { locale: fr })} → {format(new Date(mission.fin_le), "HH:mm", { locale: fr })}
      </p>
      <button
        onClick={() => navigate('/soignant/presences')}
        className="mt-3 w-full inline-flex items-center justify-center gap-2 bg-primary text-primary-foreground text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-primary/90 transition-colors"
      >
        <MapPin className="h-4 w-4" /> Aller pointer →
      </button>
    </div>
  );
}

import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Clock, MapPin } from 'lucide-react';
import { differenceInMinutes } from 'date-fns';
import { formatParis, memeJourParis } from '@/lib/date-heure-paris';

interface WidgetAllerPointerProps {
  mission: any;
}

export function WidgetAllerPointer({ mission }: WidgetAllerPointerProps) {
  const navigate = useNavigate();
  const debutReference = mission.prochainCreneau?.debut || mission.debut_affiche || mission.debut_le;
  const minutes = differenceInMinutes(new Date(debutReference), new Date());
  const estEnCours = mission.statut === 'EN_COURS';
  if (!mission.creneauActuel && !estEnCours && (minutes > 60 || minutes < -30)) return null;

  const etabNom = mission.etablissements?.nom || mission.etab_nom || 'Établissement';
  const debut = new Date(mission.debut_le);
  const fin = new Date(mission.fin_le);
  const prochainDebut = mission.prochainCreneau?.debut
    ? new Date(mission.prochainCreneau.debut)
    : null;
  const prochaineFin = mission.prochainCreneau?.fin
    ? new Date(mission.prochainCreneau.fin)
    : null;

  return (
    <div className="bg-primary/5 border-2 border-primary/30 rounded-2xl p-4 mb-4">
      <div className="flex items-center gap-2 text-primary text-sm font-semibold mb-2">
        <Clock className="h-4 w-4" />
        {mission.creneauActuel
          ? 'Créneau de travail actuel'
          : estEnCours
          ? (prochainDebut ? 'Mission active · prochain créneau' : 'Mission active · planning à confirmer')
          : `Mission dans ${minutes > 0 ? `${minutes} min` : 'maintenant'}`}
      </div>
      <h3 className="font-semibold text-foreground text-sm">{mission.intitule} — {etabNom}</h3>
      <p className="text-xs text-muted-foreground mt-1">
        {prochainDebut && prochaineFin
          ? `${formatParis(prochainDebut, 'EEEE d MMMM')} · ${formatParis(prochainDebut, 'HH:mm')} → ${formatParis(prochaineFin, 'HH:mm')}`
          : memeJourParis(debut, fin)
          ? `${formatParis(debut, 'HH:mm')} → ${formatParis(fin, 'HH:mm')}`
          : `${formatParis(debut, 'd MMM')} → ${formatParis(fin, 'd MMM yyyy')}`}
      </p>
      <button
        onClick={() => navigate(mission.creneauActuel || !estEnCours ? '/soignant/presences?tab=aujourdhui' : '/soignant/presences?tab=encours')}
        className="mt-3 w-full inline-flex items-center justify-center gap-2 bg-primary text-primary-foreground text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-primary/90 transition-colors"
      >
        <MapPin className="h-4 w-4" /> {mission.creneauActuel ? 'Aller pointer' : 'Voir horaires et présences'} →
      </button>
    </div>
  );
}

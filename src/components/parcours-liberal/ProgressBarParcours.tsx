import { CheckCircle2, Clock, Circle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Props {
  etapesTotales: number;
  etapesValidees: number;
  parcoursDemarre?: string;
  parcoursTermine?: string | null;
}

export function ProgressBarParcours({ etapesTotales, etapesValidees, parcoursDemarre, parcoursTermine }: Props) {
  const pct = etapesTotales === 0 ? 0 : Math.round((etapesValidees / etapesTotales) * 100);
  const termine = parcoursTermine !== undefined && parcoursTermine !== null;
  const allDone = etapesValidees === etapesTotales && etapesTotales > 0;
  const etat = termine || allDone ? 'termine' : etapesValidees > 0 ? 'en_cours' : 'debutant';

  const badges = {
    debutant: { label: 'Débutant', cls: 'bg-muted text-muted-foreground', Icon: Circle },
    en_cours: { label: 'En cours', cls: 'bg-warning/15 text-warning', Icon: Clock },
    termine: { label: 'Terminé', cls: 'bg-success/15 text-success', Icon: CheckCircle2 },
  };
  const badge = badges[etat];

  return (
    <div className="card-base">
      <div className="flex items-start sm:items-center justify-between gap-3 flex-col sm:flex-row">
        <div className="flex-1 w-full">
          <div className="flex items-baseline justify-between gap-2 mb-2">
            <span className="text-sm font-semibold text-foreground">
              {etapesValidees} / {etapesTotales} étapes complétées
            </span>
            <span className="text-xs text-muted-foreground">{pct}%</span>
          </div>
          <div className="h-2.5 w-full rounded-full bg-muted overflow-hidden">
            <div
              className={`h-full transition-all duration-500 ${etat === 'termine' ? 'bg-success' : 'bg-primary'}`}
              style={{ width: `${pct}%` }}
            />
          </div>
          {parcoursDemarre && (
            <p className="text-[11px] text-muted-foreground mt-2">
              Démarré le {format(new Date(parcoursDemarre), 'd MMMM yyyy', { locale: fr })}
              {parcoursTermine && (
                <> · Terminé le {format(new Date(parcoursTermine), 'd MMMM yyyy', { locale: fr })}</>
              )}
            </p>
          )}
        </div>
        <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium shrink-0 ${badge.cls}`}>
          <badge.Icon className="h-3.5 w-3.5" />
          {badge.label}
        </span>
      </div>
    </div>
  );
}

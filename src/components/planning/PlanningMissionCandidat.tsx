import { AlertTriangle, CalendarDays, Clock3 } from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  ajouterJoursCivilsParis,
  cleJourParis,
  formatParis,
  instantJolene,
  memeJourParis,
} from '@/lib/date-heure-paris';
import {
  construirePlanningCandidat,
  type MissionPlanningCandidat,
} from './planning-candidat';

interface PlanningMissionCandidatProps {
  mission: MissionPlanningCandidat;
  className?: string;
  compact?: boolean;
  limite?: number;
  afficherMentionJoursNonTravailles?: boolean;
}

function formatHeures(heures: number): string {
  return heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 });
}

function formatFin(creneau: { debut: string; fin: string | null }): string {
  if (!creneau.fin) return 'fin à confirmer';
  if (memeJourParis(creneau.debut, creneau.fin)) return formatParis(creneau.fin, "HH'h'mm");
  const estLendemain = cleJourParis(creneau.fin) === cleJourParis(ajouterJoursCivilsParis(creneau.debut, 1));
  return `${formatParis(creneau.fin, "EEEE d MMMM yyyy · HH'h'mm")}${estLendemain ? ' (lendemain)' : ''}`;
}

export function PlanningMissionCandidat({
  mission,
  className,
  compact = false,
  limite = Number.POSITIVE_INFINITY,
  afficherMentionJoursNonTravailles = true,
}: PlanningMissionCandidatProps) {
  const planning = construirePlanningCandidat(mission);

  if (!planning.exact) {
    return (
      <div className={cn('rounded-xl border border-warning/30 bg-warning/5 p-3', className)} role="alert">
        <p className="flex items-start gap-2 text-sm font-semibold text-warning">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          Planning exact à confirmer
        </p>
        <p className="mt-1 text-xs text-muted-foreground">{planning.messageBlocage}</p>
      </div>
    );
  }

  const visibles = planning.creneaux.slice(0, limite);
  const restants = planning.creneaux.length - visibles.length;

  return (
    <section className={cn('space-y-2', className)} aria-label="Planning exact de la mission">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm font-semibold text-foreground">
        <span className="inline-flex items-center gap-1.5">
          <CalendarDays className="h-4 w-4 text-primary" aria-hidden="true" />
          {planning.creneaux.length} créneau{planning.creneaux.length > 1 ? 'x' : ''}
        </span>
        <span className="inline-flex items-center gap-1.5">
          <Clock3 className="h-4 w-4 text-primary" aria-hidden="true" />
          {formatHeures(planning.totalHeures)} h au total
        </span>
      </div>
      <ul className={cn('space-y-1.5', compact && 'text-xs')} aria-label="Jours et horaires travaillés">
        {visibles.map((creneau) => {
          const duree = creneau.fin
            ? Math.max(0, (instantJolene(creneau.fin).getTime() - instantJolene(creneau.debut).getTime()) / 3_600_000)
            : 0;
          return (
            <li
              key={creneau.id ?? creneau.debut}
              className="rounded-xl bg-muted/40 px-3 py-2 text-foreground"
            >
              <span className="block font-medium capitalize">
                {formatParis(creneau.debut, 'EEEE d MMMM yyyy')}
              </span>
              <span className="block text-muted-foreground">
                {formatParis(creneau.debut, "HH'h'mm")} → {formatFin(creneau)}
                {duree > 0 ? ` · ${formatHeures(duree)} h` : ''}
              </span>
            </li>
          );
        })}
      </ul>
      {restants > 0 && (
        <p className="text-xs font-medium text-primary">
          + {restants} autre{restants > 1 ? 's' : ''} créneau{restants > 1 ? 'x' : ''} dans le récapitulatif complet
        </p>
      )}
      {afficherMentionJoursNonTravailles && planning.periodeEtendue && (
        <p className="text-xs text-muted-foreground">
          Seuls les créneaux listés sont travaillés. Les autres jours de la période ne sont pas travaillés.
        </p>
      )}
    </section>
  );
}

export default PlanningMissionCandidat;

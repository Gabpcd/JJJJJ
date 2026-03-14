import { CalendarClock, User } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface MissionProchaine {
  id: string;
  intitule: string;
  debut_le: string;
  statut: string;
  soignant_nom?: string | null;
}

interface Props {
  missions: MissionProchaine[];
}

const statutConfig: Record<string, { label: string; classe: string }> = {
  OUVERTE: { label: 'Ouverte', classe: 'bg-primary' },
  ASSIGNEE: { label: 'Assignée', classe: 'bg-info' },
  EN_COURS: { label: 'En cours', classe: 'bg-warning' },
  TERMINEE: { label: 'Terminée', classe: 'bg-success' },
  ANNULEE: { label: 'Annulée', classe: 'bg-destructive' },
};

export function ProchaineMissions({ missions }: Props) {
  const navigate = useNavigate();

  if (missions.length === 0) return null;

  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-2 mb-3">
        <CalendarClock className="h-4 w-4 text-primary" />
        <h3 className="text-sm font-semibold text-foreground">Prochaines missions</h3>
      </div>
      <div className="space-y-2">
        {missions.map((m) => {
          const cfg = statutConfig[m.statut] || statutConfig.OUVERTE;
          const date = new Date(m.debut_le);
          return (
            <button
              key={m.id}
              onClick={() => navigate(`/etablissement/missions/${m.id}`)}
              className="w-full flex items-center gap-3 p-2.5 rounded-lg hover:bg-muted/50 transition-colors text-left"
            >
              <span className={`w-2 h-2 rounded-full shrink-0 ${cfg.classe}`} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-foreground truncate">{m.intitule}</p>
                <p className="text-xs text-muted-foreground">
                  {date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })} à{' '}
                  {date.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                </p>
              </div>
              <div className="text-right shrink-0">
                {m.soignant_nom ? (
                  <span className="text-xs text-foreground flex items-center gap-1">
                    <User className="h-3 w-3" /> {m.soignant_nom}
                  </span>
                ) : (
                  <span className="text-xs text-warning font-medium">En attente</span>
                )}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

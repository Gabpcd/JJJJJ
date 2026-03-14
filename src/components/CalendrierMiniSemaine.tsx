import { useNavigate } from 'react-router-dom';
import { format, startOfWeek, addDays, isSameDay } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Props {
  missions: { debut_le: string; statut: string }[];
}

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

export function CalendrierMiniSemaine({ missions }: Props) {
  const navigate = useNavigate();
  const lundi = startOfWeek(new Date(), { weekStartsOn: 1 });

  const jours = Array.from({ length: 7 }, (_, i) => {
    const date = addDays(lundi, i);
    const missionsJour = missions.filter(m => isSameDay(new Date(m.debut_le), date));
    const estAujourdhui = isSameDay(date, new Date());
    return { date, missionsJour, estAujourdhui, label: JOURS[i] };
  });

  return (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-base font-semibold text-foreground">📅 Cette semaine</h2>
        <button onClick={() => navigate('/soignant/planning')} className="text-xs text-primary font-medium hover:underline">Planning →</button>
      </div>
      <div className="grid grid-cols-7 gap-1">
        {jours.map(j => (
          <button
            key={j.label}
            onClick={() => navigate('/soignant/planning')}
            className={`flex flex-col items-center py-2 px-1 rounded-lg transition-colors ${
              j.estAujourdhui ? 'bg-primary/10 ring-1 ring-primary/30' : 'hover:bg-muted'
            }`}
          >
            <span className={`text-[10px] font-medium ${j.estAujourdhui ? 'text-primary' : 'text-muted-foreground'}`}>
              {j.label}
            </span>
            <span className={`text-sm font-semibold mt-0.5 ${j.estAujourdhui ? 'text-primary' : 'text-foreground'}`}>
              {format(j.date, 'd')}
            </span>
            <div className="flex gap-0.5 mt-1 h-2">
              {j.missionsJour.slice(0, 3).map((m, i) => (
                <div
                  key={i}
                  className={`h-1.5 w-1.5 rounded-full ${
                    m.statut === 'EN_COURS' ? 'bg-success' : 'bg-primary'
                  }`}
                />
              ))}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

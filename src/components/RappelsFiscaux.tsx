import { useMemo } from 'react';
import { Calendar } from 'lucide-react';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';

function getProchainTrimestreURSSAF(): Date {
  const now = new Date();
  const y = now.getFullYear();
  const echeances = [
    new Date(y, 0, 5), new Date(y, 3, 5), new Date(y, 6, 5), new Date(y, 9, 5),
  ];
  return echeances.find(d => d > now) || new Date(y + 1, 0, 5);
}

function getEcheanceCARPIMKO(): Date {
  const now = new Date();
  const avril = new Date(now.getFullYear(), 3, 1);
  return avril > now ? avril : new Date(now.getFullYear() + 1, 3, 1);
}

function getEcheance2035(): Date {
  const now = new Date();
  const mai = new Date(now.getFullYear(), 4, 15);
  return mai > now ? mai : new Date(now.getFullYear() + 1, 4, 15);
}

export function RappelsFiscaux() {
  const navigate = useNavigate();

  const echeances = useMemo(() => [
    {
      label: 'URSSAF — Déclaration trimestrielle',
      date: getProchainTrimestreURSSAF(),
      icon: '🏛️',
    },
    {
      label: 'CARPIMKO — Cotisation annuelle',
      date: getEcheanceCARPIMKO(),
      icon: '🛡️',
    },
    {
      label: 'Impôt sur le revenu — Déclaration 2035',
      date: getEcheance2035(),
      icon: '📋',
    },
  ], []);

  return (
    <div className="card-base mb-6 cursor-pointer hover:shadow-md transition-all" onClick={() => navigate('/soignant/charges')}>
      <div className="flex items-center gap-2 mb-3">
        <Calendar className="h-5 w-5 text-primary" />
        <h3 className="font-semibold text-foreground">📅 Prochaines échéances fiscales</h3>
      </div>
      <div className="space-y-2">
        {echeances.map(e => {
          const jours = differenceInDays(e.date, new Date());
          const color = jours <= 14 ? 'text-destructive' : jours <= 30 ? 'text-warning' : 'text-muted-foreground';
          return (
            <div key={e.label} className="flex items-center justify-between py-1.5 border-b border-border/50 last:border-0">
              <div className="flex items-center gap-2">
                <span>{e.icon}</span>
                <span className="text-sm text-foreground">{e.label}</span>
              </div>
              <div className="text-right">
                <p className="text-xs font-medium text-foreground">{format(e.date, 'd MMM yyyy', { locale: fr })}</p>
                <p className={`text-[10px] ${color}`}>
                  {jours <= 0 ? 'Échue' : `dans ${jours}j`}
                </p>
              </div>
            </div>
          );
        })}
      </div>
      <p className="text-xs text-primary mt-2 text-center">Voir mes charges détaillées →</p>
    </div>
  );
}
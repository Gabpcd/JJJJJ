import { ArrowDown, ArrowUp, Minus, Users } from 'lucide-react';

interface Props {
  soignantsCeMois: number;
  soignantsMoisPrecedent: number;
}

export function IndicateurTurnover({ soignantsCeMois, soignantsMoisPrecedent }: Props) {
  const diff = soignantsMoisPrecedent > 0
    ? Math.round(((soignantsCeMois - soignantsMoisPrecedent) / soignantsMoisPrecedent) * 100)
    : 0;
  const instable = diff > 20;
  const stable = diff <= 20 && diff >= -20;

  return (
    <div className="card-kpi">
      <div className="flex items-start gap-3">
        <div className={`rounded-xl p-2.5 ${instable ? 'bg-warning/10' : 'bg-success/10'}`}>
          <Users className={`h-5 w-5 ${instable ? 'text-warning' : 'text-success'}`} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5">
            <p className="text-2xl font-bold text-foreground">{soignantsCeMois}</p>
            {soignantsMoisPrecedent > 0 && (
              <span className={`flex items-center text-xs font-medium ${instable ? 'text-warning' : 'text-success'}`}>
                {diff > 0 ? <ArrowUp className="h-3 w-3" /> : diff < 0 ? <ArrowDown className="h-3 w-3" /> : <Minus className="h-3 w-3" />}
                {Math.abs(diff)}%
              </span>
            )}
          </div>
          <p className="text-xs text-muted-foreground mt-0.5">Soignants différents ce mois</p>
          {instable && <p className="text-[10px] text-warning mt-0.5">Turnover élevé</p>}
        </div>
      </div>
    </div>
  );
}

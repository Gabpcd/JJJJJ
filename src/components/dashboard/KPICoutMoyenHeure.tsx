import { DollarSign } from 'lucide-react';

interface Props {
  totalBrut: number;
  totalHeures: number;
}

export function KPICoutMoyenHeure({ totalBrut, totalHeures }: Props) {
  const moyenne = totalHeures > 0 ? totalBrut / totalHeures : 0;

  return (
    <div className="card-kpi">
      <div className="flex items-start gap-3">
        <div className="rounded-xl p-2.5 bg-info/10">
          <DollarSign className="h-5 w-5 text-info" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-2xl font-bold text-foreground">
            {moyenne > 0 ? `${moyenne.toFixed(2).replace('.', ',')}€` : '—'}
          </p>
          <p className="text-xs text-muted-foreground mt-0.5">/h en moyenne ce mois</p>
        </div>
      </div>
    </div>
  );
}

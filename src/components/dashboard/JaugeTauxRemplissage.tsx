import { useEffect, useState } from 'react';

interface Props {
  pourvues: number;
  total: number;
}

export function JaugeTauxRemplissage({ pourvues, total }: Props) {
  const [animated, setAnimated] = useState(0);
  const taux = total > 0 ? Math.round((pourvues / total) * 100) : 0;
  const rayon = 28;
  const circ = 2 * Math.PI * rayon;
  const offset = circ - (animated / 100) * circ;
  const couleur = taux >= 80 ? 'hsl(var(--success))' : taux >= 50 ? 'hsl(var(--warning))' : 'hsl(var(--destructive))';

  useEffect(() => {
    const t = setTimeout(() => setAnimated(taux), 100);
    return () => clearTimeout(t);
  }, [taux]);

  return (
    <div className="card-kpi">
      <div className="flex items-center gap-3">
        <svg width="70" height="70" viewBox="0 0 70 70" className="shrink-0">
          <circle cx="35" cy="35" r={rayon} fill="none" stroke="hsl(var(--muted))" strokeWidth="6" />
          <circle
            cx="35" cy="35" r={rayon} fill="none"
            stroke={couleur} strokeWidth="6" strokeLinecap="round"
            strokeDasharray={circ} strokeDashoffset={offset}
            transform="rotate(-90 35 35)"
            style={{ transition: 'stroke-dashoffset 1.2s ease-out' }}
          />
          <text x="35" y="38" textAnchor="middle" className="text-sm font-bold" fill="currentColor">
            {animated}%
          </text>
        </svg>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground">Missions pourvues</p>
          <p className="text-xs text-muted-foreground">{pourvues}/{total} ce mois</p>
        </div>
      </div>
    </div>
  );
}

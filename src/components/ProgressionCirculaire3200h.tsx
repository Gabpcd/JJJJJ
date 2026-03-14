import { useEffect, useState } from 'react';

interface Props {
  heures: number;
  objectif?: number;
}

function getCouleur(pct: number) {
  if (pct >= 80) return 'hsl(45, 93%, 47%)'; // gold
  if (pct >= 50) return 'hsl(152, 69%, 41%)'; // emerald
  return 'hsl(var(--primary))'; // teal
}

export function ProgressionCirculaire3200h({ heures, objectif = 3200 }: Props) {
  const [animPct, setAnimPct] = useState(0);
  const pct = Math.min(100, (heures / objectif) * 100);
  const reste = Math.max(0, objectif - heures);

  const r = 58;
  const circ = 2 * Math.PI * r;
  const offset = circ - (animPct / 100) * circ;
  const couleur = getCouleur(pct);

  useEffect(() => {
    const t = setTimeout(() => setAnimPct(pct), 80);
    return () => clearTimeout(t);
  }, [pct]);

  return (
    <div className="card-base mb-6 flex flex-col items-center py-6">
      <svg width="160" height="160" viewBox="0 0 160 160" className="mb-3">
        <circle cx="80" cy="80" r={r} fill="none" stroke="hsl(var(--muted))" strokeWidth="10" />
        <circle
          cx="80" cy="80" r={r} fill="none"
          stroke={couleur} strokeWidth="10" strokeLinecap="round"
          strokeDasharray={circ} strokeDashoffset={offset}
          transform="rotate(-90 80 80)"
          style={{ transition: 'stroke-dashoffset 1.5s ease-out, stroke 0.5s' }}
        />
        <text x="80" y="72" textAnchor="middle" className="text-lg font-bold" fill="currentColor" style={{ fontSize: 16 }}>
          {heures.toLocaleString('fr-FR')}h
        </text>
        <text x="80" y="92" textAnchor="middle" fill="hsl(var(--muted-foreground))" style={{ fontSize: 11 }}>
          / {objectif.toLocaleString('fr-FR')}h
        </text>
      </svg>
      <p className="text-sm text-foreground font-semibold">{Math.round(pct)}%</p>
      <p className="text-xs text-muted-foreground mt-1">
        Plus que {reste.toLocaleString('fr-FR')}h pour le libéral
      </p>
    </div>
  );
}

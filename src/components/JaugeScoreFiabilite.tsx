import { useEffect, useState } from 'react';

interface JaugeScoreFiabiliteProps {
  score: number;
}

function getConfig(score: number) {
  if (score >= 90) return { couleur: '#059669', label: 'Excellent' };
  if (score >= 70) return { couleur: '#17A2B8', label: 'Fiable' };
  if (score >= 50) return { couleur: '#D97706', label: 'Correct' };
  if (score >= 30) return { couleur: '#D97706', label: 'À améliorer' };
  return { couleur: '#DC2626', label: 'Critique' };
}

export function JaugeScoreFiabilite({ score }: JaugeScoreFiabiliteProps) {
  const [animatedScore, setAnimatedScore] = useState(0);
  const { couleur, label } = getConfig(score);
  const rayon = 70;
  const circ = 2 * Math.PI * rayon;
  const offset = circ - (animatedScore / 100) * circ;

  useEffect(() => {
    const timer = setTimeout(() => setAnimatedScore(score), 100);
    return () => clearTimeout(timer);
  }, [score]);

  return (
    <div className="flex flex-col items-center">
      <svg width="180" height="180" viewBox="0 0 180 180">
        <circle cx="90" cy="90" r={rayon} fill="none" stroke="hsl(var(--muted))" strokeWidth="12" />
        <circle
          cx="90" cy="90" r={rayon} fill="none"
          stroke={couleur} strokeWidth="12" strokeLinecap="round"
          strokeDasharray={circ} strokeDashoffset={offset}
          transform="rotate(-90 90 90)"
          style={{ transition: 'stroke-dashoffset 1.5s ease-out' }}
        />
        <text x="90" y="82" textAnchor="middle" className="text-3xl font-bold" fill="currentColor">{Math.round(animatedScore)}</text>
        <text x="90" y="100" textAnchor="middle" className="text-sm" fill="hsl(var(--muted-foreground))">/100</text>
        <text x="90" y="122" textAnchor="middle" className="text-xs font-semibold" fill={couleur}>{label}</text>
      </svg>
    </div>
  );
}

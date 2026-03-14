import { useEffect, useState } from 'react';

interface Props {
  score: number;
  onClick?: () => void;
}

function getColor(score: number) {
  if (score >= 80) return 'hsl(45, 93%, 47%)'; // gold
  if (score >= 60) return 'hsl(142, 71%, 45%)'; // green
  if (score >= 40) return 'hsl(25, 95%, 53%)'; // orange
  return 'hsl(0, 84%, 60%)'; // red
}

function getLabel(score: number) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Fiable';
  if (score >= 40) return 'Correct';
  return 'Critique';
}

export function JaugeSpeedometer({ score, onClick }: Props) {
  const [anim, setAnim] = useState(0);

  useEffect(() => {
    const t = setTimeout(() => setAnim(score), 100);
    return () => clearTimeout(t);
  }, [score]);

  // Semi-circle: arc from 180° to 0° (left to right)
  const r = 52;
  const cx = 70, cy = 65;
  const startAngle = 180;
  const endAngle = 0;
  const totalAngle = 180;

  // Background arc segments: red(0-40), orange(40-60), green(60-80), gold(80-100)
  const segments = [
    { from: 0, to: 40, color: 'hsl(0, 84%, 60%)' },
    { from: 40, to: 60, color: 'hsl(25, 95%, 53%)' },
    { from: 60, to: 80, color: 'hsl(142, 71%, 45%)' },
    { from: 80, to: 100, color: 'hsl(45, 93%, 47%)' },
  ];

  function arcPath(fromPct: number, toPct: number) {
    const a1 = startAngle - (fromPct / 100) * totalAngle;
    const a2 = startAngle - (toPct / 100) * totalAngle;
    const x1 = cx + r * Math.cos((a1 * Math.PI) / 180);
    const y1 = cy - r * Math.sin((a1 * Math.PI) / 180);
    const x2 = cx + r * Math.cos((a2 * Math.PI) / 180);
    const y2 = cy - r * Math.sin((a2 * Math.PI) / 180);
    const large = (a1 - a2) > 180 ? 1 : 0;
    return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2}`;
  }

  // Needle
  const needleAngle = startAngle - (anim / 100) * totalAngle;
  const needleLen = r - 8;
  const nx = cx + needleLen * Math.cos((needleAngle * Math.PI) / 180);
  const ny = cy - needleLen * Math.sin((needleAngle * Math.PI) / 180);

  return (
    <div className="card-kpi cursor-pointer" onClick={onClick}>
      <div className="flex flex-col items-center">
        <svg width="140" height="85" viewBox="0 0 140 85">
          {segments.map((s, i) => (
            <path key={i} d={arcPath(s.from, s.to)} fill="none" stroke={s.color} strokeWidth="8" strokeLinecap="round" opacity="0.25" />
          ))}
          <path d={arcPath(0, Math.min(anim, 100))} fill="none" stroke={getColor(anim)} strokeWidth="8" strokeLinecap="round"
            style={{ transition: 'all 1.5s ease-out' }} />
          <line x1={cx} y1={cy} x2={nx} y2={ny} stroke="hsl(var(--foreground))" strokeWidth="2.5" strokeLinecap="round"
            style={{ transition: 'all 1.5s ease-out' }} />
          <circle cx={cx} cy={cy} r="4" fill="hsl(var(--foreground))" />
        </svg>
        <p className="text-2xl font-bold text-foreground -mt-1">{score}<span className="text-sm text-muted-foreground">/100</span></p>
        <p className="text-xs text-muted-foreground">Score · <span style={{ color: getColor(score) }} className="font-semibold">{getLabel(score)}</span></p>
        <p className="text-[10px] text-primary mt-0.5">Voir le détail →</p>
      </div>
    </div>
  );
}

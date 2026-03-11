interface DecompositionScoreProps {
  soignant: {
    score_fiabilite: number | null;
    total_missions_terminees: number | null;
    total_missions_annulees: number | null;
    total_absences: number | null;
    total_retards_pointage: number | null;
    prevoyance_inscrit: boolean | null;
  };
}

export function DecompositionScore({ soignant: s }: DecompositionScoreProps) {
  const mt = s.total_missions_terminees ?? 0;
  const ma = s.total_missions_annulees ?? 0;
  const ab = s.total_absences ?? 0;
  const rp = s.total_retards_pointage ?? 0;
  const prev = s.prevoyance_inscrit ?? false;

  const lignes = [
    { label: 'Base de départ', pts: 50, icone: '🎯' },
    { label: `Missions terminées (${mt} × 2)`, pts: mt * 2, icone: '✅' },
    { label: `Missions annulées (${ma} × -8)`, pts: -(ma * 8), icone: '❌' },
    { label: `Absences (${ab} × -25)`, pts: -(ab * 25), icone: '❌' },
    { label: `Retards pointage (${rp} × -3)`, pts: -(rp * 3), icone: '⚠️' },
  ];

  const bonus = [
    { label: 'Fidélité (> 20 missions)', pts: mt > 20 ? 10 : 0, actif: mt > 20, icone: '🏆' },
    { label: 'Zéro absence (> 5 missions)', pts: (ab === 0 && mt > 5) ? 5 : 0, actif: ab === 0 && mt > 5, icone: '✨' },
    { label: 'Prévoyance active', pts: prev ? 3 : 0, actif: prev, icone: '🛡️' },
  ];

  const total = lignes.reduce((s, l) => s + l.pts, 0) + bonus.reduce((s, b) => s + b.pts, 0);
  const plafonné = Math.max(0, Math.min(100, total));

  return (
    <div className="card-base">
      <h3 className="text-base font-bold text-foreground mb-4">🔍 Détail de votre score</h3>
      <div className="space-y-2">
        {lignes.map((l, i) => (
          <div key={i} className="flex justify-between items-center text-sm">
            <span className="text-muted-foreground">{l.icone} {l.label}</span>
            <span className={`font-semibold ${l.pts >= 0 ? 'text-emerald-600' : 'text-destructive'}`}>
              {l.pts >= 0 ? '+' : ''}{l.pts} pts
            </span>
          </div>
        ))}
        <div className="border-t border-border pt-2 mt-2">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">BONUS</p>
          {bonus.map((b, i) => (
            <div key={i} className="flex justify-between items-center text-sm">
              <span className={b.actif ? 'text-muted-foreground' : 'text-muted-foreground/40'}>
                {b.icone} {b.label}
              </span>
              <span className={`font-semibold ${b.actif ? 'text-emerald-600' : 'text-muted-foreground/40'}`}>
                +{b.pts} pts {!b.actif && '← Non débloqué'}
              </span>
            </div>
          ))}
        </div>
        <div className="border-t-2 border-primary/30 pt-3 mt-3 flex justify-between items-center">
          <span className="font-bold text-foreground">TOTAL</span>
          <span className="text-xl font-bold text-primary">{plafonné}/100</span>
        </div>
      </div>
    </div>
  );
}

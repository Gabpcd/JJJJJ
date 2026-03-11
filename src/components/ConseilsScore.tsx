import { useNavigate } from 'react-router-dom';

interface ConseilsScoreProps {
  soignant: {
    total_missions_terminees: number | null;
    total_missions_annulees: number | null;
    total_absences: number | null;
    total_retards_pointage: number | null;
    prevoyance_inscrit: boolean | null;
    score_fiabilite: number | null;
  };
}

export function ConseilsScore({ soignant: s }: ConseilsScoreProps) {
  const navigate = useNavigate();
  const conseils: { texte: string; icone: string }[] = [];

  if ((s.total_missions_annulees ?? 0) > 0) {
    conseils.push({ texte: 'Évitez d\'annuler des missions — chaque annulation coûte 8 points.', icone: '🎯' });
  }
  if ((s.total_retards_pointage ?? 0) > 0) {
    conseils.push({ texte: 'Pointez à l\'heure — chaque retard > 15 min coûte 3 points.', icone: '⏰' });
  }
  if ((s.total_missions_terminees ?? 0) <= 20) {
    const restant = 21 - (s.total_missions_terminees ?? 0);
    conseils.push({ texte: `Encore ${restant} mission${restant > 1 ? 's' : ''} pour le bonus fidélité (+10 pts).`, icone: '🏆' });
  }
  if (!s.prevoyance_inscrit) {
    conseils.push({ texte: 'Souscrivez à la prévoyance pour +3 points bonus.', icone: '🛡️' });
  }
  if ((s.score_fiabilite ?? 0) < 75) {
    conseils.push({ texte: 'Score ≥ 75 = accès prioritaire aux missions urgentes 🚀', icone: '🚀' });
  }

  if (conseils.length === 0) return null;

  return (
    <div className="card-base">
      <h3 className="text-base font-bold text-foreground mb-3">💡 Comment améliorer votre score</h3>
      <div className="space-y-2">
        {conseils.map((c, i) => (
          <div key={i} className="flex items-start gap-2 bg-primary/5 rounded-xl p-3">
            <span className="text-lg">{c.icone}</span>
            <p className="text-sm text-foreground">{c.texte}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

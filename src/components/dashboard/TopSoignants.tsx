import { Trophy, User } from 'lucide-react';
import { BoutonFavori } from '@/components/BoutonFavori';
import { JaugeScoreFiabilite } from '@/components/JaugeScoreFiabilite';

interface TopSoignant {
  id: string;
  prenom: string;
  nom: string;
  score_fiabilite: number;
  count: number;
  avatar_url?: string | null;
}

interface Props {
  soignants: TopSoignant[];
  etablissementId: string;
  onSelectSoignant?: (soignantId: string) => void;
}

const medalColors = ['text-warning', 'text-muted-foreground', 'text-primary'];

export function TopSoignants({ soignants, etablissementId, onSelectSoignant }: Props) {
  if (soignants.length === 0) return null;

  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-2 mb-3">
        <Trophy className="h-4 w-4 text-warning" />
        <h3 className="text-sm font-semibold text-foreground">Top soignants</h3>
      </div>
      <div className="space-y-3">
        {soignants.map((s, i) => (
          <div
            key={s.id}
            className={`flex items-center gap-3 ${onSelectSoignant ? 'cursor-pointer rounded-lg px-1 py-1 hover:bg-muted/40 transition-colors' : ''}`}
            onClick={onSelectSoignant ? () => onSelectSoignant(s.id) : undefined}
          >
            <span className={`text-lg font-bold w-6 text-center ${medalColors[i] || 'text-muted-foreground'}`}>
              {i + 1}
            </span>
            <div className="rounded-full bg-muted p-2 shrink-0">
              <User className="h-4 w-4 text-muted-foreground" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground truncate">{s.prenom} {s.nom}</p>
              <div className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground">{s.count} mission{s.count > 1 ? 's' : ''}</span>
                <span className="text-xs px-1.5 py-0.5 rounded-full bg-primary/10 text-primary font-medium">
                  {s.score_fiabilite}/100
                </span>
              </div>
            </div>
            <div onClick={(e) => e.stopPropagation()}>
              <BoutonFavori soignantId={s.id} etablissementId={etablissementId} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

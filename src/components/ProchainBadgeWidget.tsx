import { useNavigate } from 'react-router-dom';
import { Trophy, Shield, Star, Clock, XCircle, Moon, Calendar, Heart, Zap, Lock, LucideIcon } from 'lucide-react';
import type { BadgeStats } from '@/components/BadgesGamification';

interface BadgeDef {
  id: string; label: string; description: string; icone: LucideIcon;
  couleur: string;
  condition: (s: BadgeStats) => boolean;
  progression: (s: BadgeStats) => number;
  progressLabel: (s: BadgeStats) => string;
}

const BADGES: BadgeDef[] = [
  { id: 'premiere_mission', label: 'Première mission', description: '1 mission terminée', icone: Trophy, couleur: 'text-amber-500',
    condition: s => s.missionsTerminees >= 1, progression: s => Math.min(100, (s.missionsTerminees / 1) * 100),
    progressLabel: s => `${s.missionsTerminees}/1 mission` },
  { id: 'expert', label: 'Expert', description: '50 missions terminées', icone: Star, couleur: 'text-primary',
    condition: s => s.missionsTerminees >= 50, progression: s => Math.min(100, (s.missionsTerminees / 50) * 100),
    progressLabel: s => `${s.missionsTerminees}/50 missions` },
  { id: 'fiable', label: 'Fiable', description: 'Score fiabilité > 80', icone: Shield, couleur: 'text-emerald-500',
    condition: s => s.scoreFiabilite > 80, progression: s => Math.min(100, (s.scoreFiabilite / 80) * 100),
    progressLabel: s => `${s.scoreFiabilite}/80 score` },
  { id: 'marathonien', label: 'Marathonien', description: '1 000h cumulées', icone: Clock, couleur: 'text-violet-500',
    condition: s => s.heuresCumulees >= 1000, progression: s => Math.min(100, (s.heuresCumulees / 1000) * 100),
    progressLabel: s => `${s.heuresCumulees}/1000h` },
  { id: 'noctambule', label: 'Noctambule', description: '10 missions de nuit', icone: Moon, couleur: 'text-indigo-500',
    condition: s => s.missionsNuit >= 10, progression: s => Math.min(100, (s.missionsNuit / 10) * 100),
    progressLabel: s => `${s.missionsNuit}/10 nuits` },
  { id: 'weekender', label: 'Week-ender', description: '10 missions week-end', icone: Calendar, couleur: 'text-orange-500',
    condition: s => s.missionsWeekend >= 10, progression: s => Math.min(100, (s.missionsWeekend / 10) * 100),
    progressLabel: s => `${s.missionsWeekend}/10 WE` },
  { id: 'fidele', label: 'Fidèle', description: '10 missions même établissement', icone: Heart, couleur: 'text-rose-500',
    condition: s => s.maxMissionsMemeEtab >= 10, progression: s => Math.min(100, (s.maxMissionsMemeEtab / 10) * 100),
    progressLabel: s => `${s.maxMissionsMemeEtab}/10 fidèle` },
  { id: 'veloce', label: 'Véloce', description: '0 retard sur 10+ missions', icone: Zap, couleur: 'text-yellow-500',
    condition: s => s.retards === 0 && s.totalMissions >= 10, progression: s => s.totalMissions < 10 ? Math.min(99, (s.totalMissions / 10) * 100) : (s.retards === 0 ? 100 : 0),
    progressLabel: s => `${Math.min(s.totalMissions, 10)}/10 missions` },
];

interface Props { stats: BadgeStats }

export function ProchainBadgeWidget({ stats }: Props) {
  const navigate = useNavigate();

  // Find closest unlocked badge (highest progression < 100)
  const prochain = BADGES
    .filter(b => !b.condition(stats))
    .map(b => ({ ...b, pct: Math.round(b.progression(stats)) }))
    .sort((a, b) => b.pct - a.pct)[0];

  if (!prochain) return null;

  const Icone = prochain.icone;

  return (
    <div
      className="card-base mb-6 cursor-pointer hover:shadow-md transition-all"
      onClick={() => navigate('/soignant/fiabilite')}
    >
      <div className="flex items-center gap-3">
        <div className="rounded-xl p-2.5 bg-primary/10">
          <Icone className={`h-5 w-5 ${prochain.couleur}`} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-xs text-muted-foreground">Prochain objectif</p>
          <p className="text-sm font-semibold text-foreground">{prochain.label}</p>
          <p className="text-xs text-muted-foreground">{prochain.progressLabel(stats)}</p>
        </div>
        <span className="text-sm font-bold text-primary">{prochain.pct}%</span>
      </div>
      <div className="mt-2 h-1.5 bg-muted rounded-full overflow-hidden">
        <div className="h-full bg-primary rounded-full transition-all duration-1000" style={{ width: `${prochain.pct}%` }} />
      </div>
    </div>
  );
}

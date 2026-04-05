import { Trophy, Shield, Star, Clock, XCircle, Moon, Calendar, Heart, Zap, Lock } from 'lucide-react';
import { LucideIcon } from 'lucide-react';

interface BadgeDef {
  id: string;
  label: string;
  description: string;
  icone: LucideIcon;
  couleurDebloque: string;
  condition: (stats: BadgeStats) => boolean;
  progression: (stats: BadgeStats) => number; // 0-100
}

export interface BadgeStats {
  missionsTerminees: number;
  scoreFiabilite: number;
  heuresCumulees: number;
  annulations: number;
  missionsNuit: number;
  missionsWeekend: number;
  maxMissionsMemeEtab: number;
  retards: number;
  totalMissions: number;
}

const BADGES: BadgeDef[] = [
  {
    id: 'premiere_mission', label: 'Première mission', description: '1 mission terminée',
    icone: Trophy, couleurDebloque: 'from-amber-400 to-amber-600',
    condition: (s) => s.missionsTerminees >= 1,
    progression: (s) => Math.min(100, (s.missionsTerminees / 1) * 100),
  },
  {
    id: 'fiable', label: 'Fiable', description: 'Score fiabilité > 80',
    icone: Shield, couleurDebloque: 'from-emerald-400 to-emerald-600',
    condition: (s) => s.scoreFiabilite > 80,
    progression: (s) => Math.min(100, (s.scoreFiabilite / 80) * 100),
  },
  {
    id: 'expert', label: 'Expert', description: '50 missions terminées',
    icone: Star, couleurDebloque: 'from-primary to-info',
    condition: (s) => s.missionsTerminees >= 50,
    progression: (s) => Math.min(100, (s.missionsTerminees / 50) * 100),
  },
  {
    id: 'marathonien', label: 'Marathonien', description: '1 000h cumulées',
    icone: Clock, couleurDebloque: 'from-violet-400 to-violet-600',
    condition: (s) => s.heuresCumulees >= 1000,
    progression: (s) => Math.min(100, (s.heuresCumulees / 1000) * 100),
  },
  {
    id: 'zero_annulation', label: 'Zéro annulation', description: '0 annulation sur 20+ missions',
    icone: XCircle, couleurDebloque: 'from-teal-400 to-teal-600',
    condition: (s) => s.annulations === 0 && s.totalMissions >= 20,
    progression: (s) => s.totalMissions < 20 ? Math.min(99, (s.totalMissions / 20) * 100) : (s.annulations === 0 ? 100 : 0),
  },
  {
    id: 'noctambule', label: 'Noctambule', description: '10 missions de nuit',
    icone: Moon, couleurDebloque: 'from-indigo-400 to-indigo-600',
    condition: (s) => s.missionsNuit >= 10,
    progression: (s) => Math.min(100, (s.missionsNuit / 10) * 100),
  },
  {
    id: 'weekender', label: 'Week-ender', description: '10 missions le week-end',
    icone: Calendar, couleurDebloque: 'from-orange-400 to-orange-600',
    condition: (s) => s.missionsWeekend >= 10,
    progression: (s) => Math.min(100, (s.missionsWeekend / 10) * 100),
  },
  {
    id: 'fidele', label: 'Fidèle', description: '10 missions chez le même établissement',
    icone: Heart, couleurDebloque: 'from-rose-400 to-rose-600',
    condition: (s) => s.maxMissionsMemeEtab >= 10,
    progression: (s) => Math.min(100, (s.maxMissionsMemeEtab / 10) * 100),
  },
  {
    id: 'veloce', label: 'Véloce', description: '0 retard sur 10+ missions',
    icone: Zap, couleurDebloque: 'from-yellow-400 to-yellow-600',
    condition: (s) => s.retards === 0 && s.totalMissions >= 10,
    progression: (s) => s.totalMissions < 10 ? Math.min(99, (s.totalMissions / 10) * 100) : (s.retards === 0 ? 100 : 0),
  },
];

interface BadgesGamificationProps {
  stats: BadgeStats;
  compact?: boolean;
}

export function BadgesGamification({ stats, compact }: BadgesGamificationProps) {
  const debloqués = BADGES.filter(b => b.condition(stats)).length;

  return (
    <div className="card-base">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-base font-semibold text-foreground flex items-center gap-2">
          <Trophy className="h-5 w-5 text-primary" /> Mes badges
        </h2>
        <span className="text-xs text-muted-foreground font-medium">{debloqués}/{BADGES.length} débloqués</span>
      </div>

      <div className={`grid ${compact ? 'grid-cols-3' : 'grid-cols-3 md:grid-cols-5'} gap-3`}>
        {BADGES.map((badge) => {
          const debloque = badge.condition(stats);
          const rawPct = badge.progression(stats);
          const pct = Number.isFinite(rawPct) ? Math.round(rawPct) : 0;
          const Icone = badge.icone;

          return (
            <div
              key={badge.id}
              className={`flex flex-col items-center text-center p-3 rounded-xl border transition-all ${
                debloque
                  ? 'border-primary/30 bg-primary/5 shadow-sm'
                  : 'border-border bg-muted/30 opacity-50 grayscale'
              }`}
              title={badge.description}
            >
              <div className={`w-10 h-10 rounded-full flex items-center justify-center mb-2 ${
                debloque
                  ? `bg-gradient-to-br ${badge.couleurDebloque} text-white shadow-md`
                  : 'bg-muted text-muted-foreground'
              }`}>
                {debloque ? <Icone className="h-5 w-5" /> : <Lock className="h-4 w-4" />}
              </div>
              <span className={`text-[11px] font-semibold leading-tight ${debloque ? 'text-foreground' : 'text-muted-foreground'}`}>
                {badge.label}
              </span>
              {!debloque && (
                <div className="w-full mt-1.5">
                  <div className="h-1 bg-border rounded-full overflow-hidden">
                    <div className="h-full bg-primary/40 rounded-full transition-all" style={{ width: `${pct}%` }} />
                  </div>
                  <span className="text-[9px] text-muted-foreground">{pct}%</span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

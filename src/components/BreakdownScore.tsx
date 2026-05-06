import React from 'react';
import { CheckCircle2, AlertCircle, MinusCircle, TrendingDown, TrendingUp } from 'lucide-react';

interface Composante {
  cle: string;
  label: string;
  description: string;
  pct: number | null; // null si inactive
  poids_initial: number;
  poids_effectif: number; // après redistribution
  conseil_si_bas?: string;
}

interface Breakdown {
  score_total: number;
  niveau: 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE';
  en_periode_probatoire: boolean;
  notation_etab_soignant_pct: number | null;
  notation_etab_soignant_poids: number | null;
  presentisme_pct: number | null;
  presentisme_poids: number | null;
  ponctualite_pct: number | null;
  ponctualite_poids: number | null;
  reactivite_pct: number | null;
  reactivite_poids: number | null;
  anciennete_volume_pct: number | null;
  anciennete_volume_poids: number | null;
  notation_soignant_etab_pct: number | null;
  notation_soignant_etab_poids: number | null;
  litiges_malus: number;
  absence_sans_prevenir_malus: number;
  bonus_super_actif: number;
  composantes_actives_count: number;
  composantes_inactives_json?: Array<{ composante: string; poids_initial: number }>;
  redistribution_json?: { facteur?: number; total_poids_actifs?: number };
}

interface Props {
  breakdown: Breakdown;
}

const SEUIL_CONSEIL = 60;
const COMPOSANTES_DEF: Array<{ cle: keyof Breakdown; label: string; description: string; conseil: string; poids_initial: number }> = [
  { cle: 'notation_etab_soignant_pct', label: 'Notation reçue (étab → vous)', description: 'Moyenne des étoiles 4 critères, pondérée récence', conseil: 'Maintenez un haut niveau de professionnalisme : les étabs notent ponctualité, professionnalisme, qualité du soin, communication.', poids_initial: 35 },
  { cle: 'presentisme_pct', label: 'Présentéisme', description: '% de missions terminées vs total acceptées (12 mois)', conseil: 'Évitez les annulations de dernière minute et les absences. Privilégiez de prévenir 48h avant si imprévu.', poids_initial: 20 },
  { cle: 'ponctualite_pct', label: 'Ponctualité', description: 'Écart pointage arrivée vs heure prévue (12 mois)', conseil: 'Arrivez 5 min avant l\'heure prévue. Pointez dès l\'arrivée pour valider la ponctualité.', poids_initial: 15 },
  { cle: 'reactivite_pct', label: 'Réactivité aux propositions', description: 'Délai moyen pour répondre aux propositions de mission', conseil: 'Répondez sous 1h aux propositions urgentes, sous 24h pour les autres. Activez les notifications push.', poids_initial: 10 },
  { cle: 'anciennete_volume_pct', label: 'Ancienneté & volume', description: 'Nombre de missions terminées sur 12 mois', conseil: 'Continuez à candidater régulièrement. La fréquence de mission booste cette composante.', poids_initial: 10 },
  { cle: 'notation_soignant_etab_pct', label: 'Vous notez les étabs', description: '% de missions terminées que vous avez notées', conseil: 'Notez les étabs après chaque mission terminée : c\'est un signal d\'engagement et améliore l\'écosystème.', poids_initial: 10 },
];

function CouleurPct(pct: number | null): string {
  if (pct == null) return 'text-muted-foreground';
  if (pct >= 80) return 'text-success';
  if (pct >= SEUIL_CONSEIL) return 'text-foreground';
  return 'text-warning';
}

export function BreakdownScore({ breakdown }: Props) {
  const composantes: Composante[] = COMPOSANTES_DEF.map((def) => {
    const pctKey = def.cle as keyof Breakdown;
    const poidsKey = def.cle.toString().replace('_pct', '_poids') as keyof Breakdown;
    return {
      cle: def.cle.toString(),
      label: def.label,
      description: def.description,
      pct: (breakdown[pctKey] as number | null),
      poids_initial: def.poids_initial,
      poids_effectif: Number(breakdown[poidsKey] ?? 0),
      conseil_si_bas: def.conseil,
    };
  });

  const inactives = composantes.filter((c) => c.pct == null);
  const actives = composantes.filter((c) => c.pct != null);
  const aRedistribution = inactives.length > 0;

  const malusActifs = (breakdown.litiges_malus ?? 0) < 0 || (breakdown.absence_sans_prevenir_malus ?? 0) < 0;
  const bonusActif = (breakdown.bonus_super_actif ?? 0) > 0;

  return (
    <div className="space-y-4">
      {breakdown.en_periode_probatoire && (
        <div className="card-base border-l-4 border-l-warning bg-warning/5">
          <div className="flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-semibold text-foreground">Période probatoire</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Votre score est calculé sur les composantes disponibles, mais reste indicatif tant que vous n'avez pas terminé au moins 3 missions.
              </p>
            </div>
          </div>
        </div>
      )}

      {aRedistribution && (
        <div className="card-base border-l-4 border-l-info bg-info/5">
          <div className="flex items-start gap-3">
            <MinusCircle className="h-5 w-5 text-info shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">Composantes inactives — poids redistribués</p>
              <p className="text-xs text-muted-foreground mt-0.5 mb-2">
                {inactives.length} composante{inactives.length > 1 ? 's' : ''} non comptée{inactives.length > 1 ? 's' : ''} (pas assez de données). Les autres composantes voient leur poids majoré proportionnellement.
              </p>
              <ul className="text-xs text-muted-foreground space-y-0.5">
                {inactives.map((c) => (
                  <li key={c.cle}>• <strong>{c.label}</strong> : {c.poids_initial}% redistribué</li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}

      <div className="space-y-2">
        {actives.map((c) => (
          <article key={c.cle} className="card-base">
            <div className="flex items-start justify-between gap-3 mb-1">
              <div className="min-w-0">
                <p className="text-sm font-semibold text-foreground">{c.label}</p>
                <p className="text-xs text-muted-foreground">{c.description}</p>
              </div>
              <div className="text-right shrink-0">
                <p className={`text-2xl font-extrabold ${CouleurPct(c.pct)}`}>{Math.round(c.pct ?? 0)}%</p>
                <p className="text-[10px] text-muted-foreground">poids {c.poids_effectif.toFixed(0)}%</p>
              </div>
            </div>

            {/* Barre progression */}
            <div className="h-2 bg-muted rounded-full overflow-hidden mb-1">
              <div
                className={`h-full rounded-full ${(c.pct ?? 0) >= 80 ? 'bg-success' : (c.pct ?? 0) >= SEUIL_CONSEIL ? 'bg-primary' : 'bg-warning'}`}
                style={{ width: `${Math.min(100, c.pct ?? 0)}%` }}
              />
            </div>

            {/* Contribution au score */}
            <p className="text-[11px] text-muted-foreground">
              Contribution : <strong className="text-foreground">{((c.pct ?? 0) * c.poids_effectif / 100).toFixed(1)} pts</strong> sur {c.poids_effectif.toFixed(0)} possibles
            </p>

            {/* Conseil si < 60% */}
            {c.pct != null && c.pct < SEUIL_CONSEIL && c.conseil_si_bas && (
              <div className="mt-2 rounded-xl bg-warning/5 border border-warning/20 p-2.5">
                <p className="text-xs text-foreground inline-flex items-start gap-1.5">
                  <TrendingDown className="h-3.5 w-3.5 text-warning shrink-0 mt-0.5" />
                  <span><strong>Améliorez :</strong> {c.conseil_si_bas}</span>
                </p>
              </div>
            )}
          </article>
        ))}
      </div>

      {(malusActifs || bonusActif) && (
        <div className="card-base">
          <h3 className="text-sm font-semibold text-foreground mb-2">Malus & bonus</h3>
          <div className="space-y-1 text-xs">
            {breakdown.litiges_malus < 0 && (
              <p className="text-warning">⚠️ Litiges perdus 12 mois : <strong>{breakdown.litiges_malus} pts</strong> (cap -20)</p>
            )}
            {breakdown.absence_sans_prevenir_malus < 0 && (
              <p className="text-destructive">🚫 Absence sans prévenir : <strong>{breakdown.absence_sans_prevenir_malus} pts</strong></p>
            )}
            {breakdown.bonus_super_actif > 0 && (
              <p className="text-success inline-flex items-center gap-1"><TrendingUp className="h-3 w-3" /> Bonus super-actif (plus de 50 missions sur 12 mois) : <strong>+{breakdown.bonus_super_actif} pts</strong></p>
            )}
          </div>
        </div>
      )}

      <div className="rounded-xl bg-muted/30 border border-border p-3 text-xs text-muted-foreground">
        <CheckCircle2 className="h-3.5 w-3.5 inline mr-1 text-primary" />
        Score total = somme pondérée des composantes + malus/bonus, borné [0, 100]. Recalculé à chaque nouvelle notation, mission terminée ou litige résolu.
      </div>
    </div>
  );
}

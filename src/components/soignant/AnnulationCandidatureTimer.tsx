import { useEffect, useState } from 'react';
import { Clock, AlertTriangle, CheckCircle } from 'lucide-react';

interface Props {
  /** Date d'acceptation de la candidature (ISO) */
  accepteeA: string | Date;
  /** Date de début de la mission (ISO) */
  debutMission: string | Date;
  /** Mission en mode ASAP (proposition urgente) */
  estAsap?: boolean;
}

interface Bucket {
  libre: boolean;
  points: number;
  motif: string;
  signalement: boolean;
}

/**
 * Composant affichant le statut de rétractation candidature Sprint 3.5.
 *
 * Reproduit côté front la logique de `fn_calculer_penalite_annulation_soignant` :
 *  - Fenêtre 30 min après acceptation, uniquement avant le début : libre, 0 pt
 *  - ASAP < 2h du début : -25 pts
 *  - Délai 12-24h du début : -5 pts
 *  - Délai 1-12h du début : -10 pts
 *  - Jour J ou no-show (mission débutée) : -30 pts + signalement
 *
 * Mise à jour temps réel toutes les 10 secondes.
 */
export function AnnulationCandidatureTimer({ accepteeA, debutMission, estAsap = false }: Props) {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 10_000);
    return () => clearInterval(t);
  }, []);

  const accepteeDate = accepteeA instanceof Date ? accepteeA : new Date(accepteeA);
  const debutDate = debutMission instanceof Date ? debutMission : new Date(debutMission);

  const deltaRetractMs = now.getTime() - accepteeDate.getTime();
  const deltaMissionMs = debutDate.getTime() - now.getTime();
  const dansFenetre30Min = deltaMissionMs > 0 && deltaRetractMs < 30 * 60_000;
  const minutesRestantes = Math.max(0, Math.ceil((30 * 60_000 - deltaRetractMs) / 60_000));

  const bucket = calculerBucketAnnulation(deltaRetractMs, deltaMissionMs, estAsap);

  if (dansFenetre30Min) {
    return (
      <div className="rounded-xl border-2 border-success/40 bg-success/5 p-3 space-y-1">
        <div className="flex items-center gap-2 text-success font-semibold text-sm">
          <CheckCircle className="h-4 w-4" />
          <span>Fenêtre de rétractation active</span>
        </div>
        <p className="text-xs text-success/80">
          Vous pouvez annuler sans aucun impact sur votre score pendant encore <strong>{minutesRestantes} min</strong>.
        </p>
        <p className="text-[11px] text-muted-foreground">
          Cette fenêtre de 30 min protège vos retours en arrière après acceptation. Aucune notation, aucune pénalité.
        </p>
      </div>
    );
  }

  const styleBucket = bucket.points <= -25
    ? 'border-destructive/50 bg-destructive/5 text-destructive'
    : bucket.points <= -10
      ? 'border-orange-500/40 bg-orange-50 dark:bg-orange-950/20 text-orange-700 dark:text-orange-300'
      : bucket.points < 0
        ? 'border-warning/40 bg-warning/5 text-warning'
        : 'border-muted bg-muted/30 text-muted-foreground';

  return (
    <div className={`rounded-xl border-2 p-3 space-y-1 ${styleBucket}`}>
      <div className="flex items-center gap-2 font-semibold text-sm">
        {bucket.points < 0 ? <AlertTriangle className="h-4 w-4" /> : <Clock className="h-4 w-4" />}
        <span>{libelleBucket(bucket)}</span>
      </div>
      <p className="text-xs">
        {descriptionBucket(bucket)}
      </p>
      {bucket.points < 0 && (
        <p className="text-[11px] italic">
          Cette pénalité reste contestable via votre page score si vous avez une raison légitime (urgence médicale, deuil, force majeure…).
        </p>
      )}
    </div>
  );
}

// Ce helper est exporté pour verrouiller les frontières métier dans un test
// unitaire sans devoir simuler l'écoulement du temps dans React.
// eslint-disable-next-line react-refresh/only-export-components
export function calculerBucketAnnulation(deltaRetractMs: number, deltaMissionMs: number, estAsap: boolean): Bucket {
  // Une mission déjà commencée est toujours un no-show : la fenêtre de retour
  // et le bucket ASAP ne doivent jamais masquer cet état.
  if (deltaMissionMs <= 0) {
    return { libre: false, points: -30, motif: 'NO_SHOW', signalement: true };
  }

  if (deltaRetractMs < 30 * 60_000) {
    return { libre: true, points: 0, motif: 'fenetre_retractation_30min', signalement: false };
  }

  if (estAsap && deltaMissionMs < 2 * 3600_000) {
    return { libre: false, points: -25, motif: 'ASAP_ANNULEE_APRES_FENETRE', signalement: false };
  }

  if (deltaMissionMs < 3600_000) {
    return { libre: false, points: -30, motif: 'ANNULATION_MOINS_1H', signalement: false };
  }

  if (deltaMissionMs < 12 * 3600_000) {
    return { libre: false, points: -10, motif: 'ANNULATION_1_12H', signalement: false };
  }

  if (deltaMissionMs < 24 * 3600_000) {
    return { libre: false, points: -5, motif: 'ANNULATION_12_24H', signalement: false };
  }

  return { libre: true, points: 0, motif: 'neutre_delai_long', signalement: false };
}

function libelleBucket(b: Bucket): string {
  if (b.libre) return 'Annulation libre';
  if (b.signalement) return 'No-show : -30 pts + signalement admin';
  if (b.motif === 'ANNULATION_MOINS_1H') return 'Annulation à moins d’1h : -30 pts';
  if (b.points === -25) return 'Annulation tardive ASAP : -25 pts';
  if (b.points === -10) return 'Annulation 1-12h avant : -10 pts';
  if (b.points === -5) return 'Annulation 12-24h avant : -5 pts';
  if (b.points === 0) return 'Annulation >24h avant : score inchangé';
  return `Annulation : ${b.points} pts`;
}

function descriptionBucket(b: Bucket): string {
  if (b.libre) return 'Aucun impact sur votre score.';
  if (b.signalement) {
    return 'La mission a déjà commencé sans présence confirmée. Votre score est impacté de -30 pts et l’admin Jolene est notifié pour examen.';
  }
  if (b.motif === 'ANNULATION_MOINS_1H') {
    return 'Annulation très tardive avant le début de la mission. Votre score est impacté de -30 pts, sans être qualifiée de no-show.';
  }
  if (b.points === -25) {
    return 'Mission urgente (ASAP) acceptée et annulée à moins de 2h du début. Votre score est impacté de -25 pts.';
  }
  if (b.points === -10) {
    return 'Annulation à moins de 12h du début de mission. Votre score est impacté de -10 pts.';
  }
  if (b.points === -5) {
    return 'Annulation entre 12h et 24h avant le début de mission. Votre score est impacté de -5 pts.';
  }
  if (b.points === 0) {
    return 'L\'annulation est suffisamment anticipée. Votre score n\'est pas impacté.';
  }
  return '';
}

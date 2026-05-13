import { useEffect, useState } from 'react';
import { Clock, AlertTriangle } from 'lucide-react';

interface Props {
  /** Date de création du contrat (ISO string). Le countdown court 72h à partir de cette date. */
  contratCreeLe: string;
  /** Callback optionnel quand le countdown expire (0:00:00) */
  onExpire?: () => void;
}

/**
 * Countdown 72h pour signature contrat.
 *
 * Sprint 6 PR 6 — Fix P1-6 audit Sprint 5.
 *
 * Couleur progressive :
 * - vert  > 48h restants
 * - orange 24-48h restants
 * - rouge < 24h restants
 *
 * Format affichage : "Jh Mm Ss" (heures, minutes, secondes restantes).
 * Au-delà de 72h : "Expiré" en rouge.
 */
export function Countdown72hSignature({ contratCreeLe, onExpire }: Props) {
  const [restant, setRestant] = useState<number>(() => calculerRestant(contratCreeLe));

  useEffect(() => {
    if (restant <= 0) {
      onExpire?.();
      return;
    }
    const t = setInterval(() => {
      setRestant(calculerRestant(contratCreeLe));
    }, 1000);
    return () => clearInterval(t);
  }, [contratCreeLe, restant, onExpire]);

  if (restant <= 0) {
    return (
      <div className="rounded-xl bg-destructive/10 border border-destructive/30 p-3 inline-flex items-center gap-2">
        <AlertTriangle className="h-4 w-4 text-destructive shrink-0" />
        <p className="text-xs font-semibold text-destructive">
          ⚠️ Délai de signature expiré (72h dépassées).
        </p>
      </div>
    );
  }

  const heures = Math.floor(restant / 3600);
  const minutes = Math.floor((restant % 3600) / 60);
  const secondes = restant % 60;

  let couleur: 'success' | 'warning' | 'destructive';
  if (heures >= 48) couleur = 'success';
  else if (heures >= 24) couleur = 'warning';
  else couleur = 'destructive';

  const couleurClasses = {
    success: 'bg-success/10 border-success/30 text-success',
    warning: 'bg-warning/10 border-warning/30 text-warning',
    destructive: 'bg-destructive/10 border-destructive/30 text-destructive',
  }[couleur];

  return (
    <div className={`rounded-xl border p-3 inline-flex items-center gap-2 ${couleurClasses}`} role="timer" aria-live="polite">
      <Clock className="h-4 w-4 shrink-0" />
      <p className="text-xs font-semibold">
        {couleur === 'destructive'
          ? 'Signature urgente — moins de 24h restantes !'
          : 'Signature à finaliser sous'}
        <span className="ml-1 tabular-nums font-mono">
          {heures}h {minutes.toString().padStart(2, '0')}m {secondes.toString().padStart(2, '0')}s
        </span>
      </p>
    </div>
  );
}

function calculerRestant(contratCreeLe: string): number {
  const cree = new Date(contratCreeLe).getTime();
  const echeance = cree + 72 * 3600 * 1000;
  const maintenant = Date.now();
  return Math.max(0, Math.floor((echeance - maintenant) / 1000));
}

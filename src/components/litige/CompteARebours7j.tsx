import React, { useEffect, useState } from 'react';
import { Clock, AlertTriangle } from 'lucide-react';
import { heuresRestantes7j } from '@/lib/statutLitige';

interface Props {
  creeLe: string;
}

export function CompteARebours7j({ creeLe }: Props) {
  const [heures, setHeures] = useState<number>(() => heuresRestantes7j(creeLe));

  useEffect(() => {
    // Refresh chaque minute
    const t = setInterval(() => setHeures(heuresRestantes7j(creeLe)), 60_000);
    return () => clearInterval(t);
  }, [creeLe]);

  const expire = heures < 0;
  const urgent = heures > 0 && heures < 24;

  if (expire) {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-destructive">
        <AlertTriangle className="h-3.5 w-3.5" /> Délai 7 jours expiré
      </span>
    );
  }

  const jours = Math.floor(heures / 24);
  const h = Math.floor(heures % 24);
  const label = jours > 0
    ? `${jours} jour${jours > 1 ? 's' : ''} ${h}h pour s'accorder`
    : `${h}h restantes pour s'accorder`;

  return (
    <span className={`inline-flex items-center gap-1.5 text-xs font-semibold ${urgent ? 'text-warning' : 'text-info'}`}>
      <Clock className="h-3.5 w-3.5" /> {label}
    </span>
  );
}

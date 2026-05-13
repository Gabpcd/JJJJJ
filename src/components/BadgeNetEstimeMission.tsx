import { useEffect, useState } from 'react';
import { Banknote } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  missionId: string;
  /** Taux horaire base (€) */
  tauxHoraire: number;
  /** Heures prévues (peut différer des heures pointées) */
  dureeHeuresPrevue?: number;
  /** % charges sociales soignant (default 22% libéral, 28% CDD) */
  pctCharges?: number;
}

/**
 * Badge "Net estimé" pour mission en cours soignant.
 *
 * Sprint 7 PR 5 — Cosmétique P2 §9.
 *
 * Calcule le net estimé en live :
 * - Heures pointées si présence existe (arrivée+départ)
 * - Sinon heures prévues
 * - taux × heures × (1 - pctCharges)
 *
 * Affiché en lecture seule, indicatif.
 */
export function BadgeNetEstimeMission({ missionId, tauxHoraire, dureeHeuresPrevue, pctCharges = 0.22 }: Props) {
  const [heuresReelles, setHeuresReelles] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('presences' as any)
        .select('pointage_arrivee_le, pointage_depart_le')
        .eq('mission_id', missionId)
        .maybeSingle();
      if (cancelled) return;
      const row = data as any;
      if (row?.pointage_arrivee_le && row?.pointage_depart_le) {
        const diff = new Date(row.pointage_depart_le).getTime() - new Date(row.pointage_arrivee_le).getTime();
        if (diff > 0) setHeuresReelles(diff / 3600000);
      } else if (row?.pointage_arrivee_le) {
        // Pointage en cours : calcule depuis l'arrivée jusqu'à maintenant
        const diff = Date.now() - new Date(row.pointage_arrivee_le).getTime();
        if (diff > 0) setHeuresReelles(diff / 3600000);
      }
    })();
    return () => { cancelled = true; };
  }, [missionId]);

  const heures = heuresReelles ?? dureeHeuresPrevue ?? 0;
  if (heures <= 0 || tauxHoraire <= 0) return null;

  const brut = tauxHoraire * heures;
  const net = brut * (1 - pctCharges);
  const label = heuresReelles != null ? 'Net estimé (pointage)' : 'Net estimé (prévision)';

  return (
    <span
      className="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full bg-success/10 text-success font-medium"
      title={`${label} : ${heures.toFixed(1)}h × ${tauxHoraire.toFixed(2)}€ × ${((1 - pctCharges) * 100).toFixed(0)}%`}
    >
      <Banknote className="h-3 w-3" />
      Net estimé : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(net)}
    </span>
  );
}

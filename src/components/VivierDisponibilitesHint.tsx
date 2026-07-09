import { useEffect, useState } from 'react';
import { Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface VivierDisponibilitesHintProps {
  /** Valeur du champ datetime-local (ou date ISO) — seul le jour compte. */
  jour: string | null;
  profession: string | null;
}

/**
 * Lot 17 (F5) — vivier de disponibilités côté établissement.
 * Affiche « N soignants disponibles ce jour-là » sous le choix de date d'une
 * mission, à partir des calendriers de disponibilités déclarés par les
 * soignants (fn_vivier_disponibilites — compte + prénoms uniquement, RGPD).
 */
export function VivierDisponibilitesHint({ jour, profession }: VivierDisponibilitesHintProps) {
  const [nb, setNb] = useState<number | null>(null);

  useEffect(() => {
    let annule = false;
    setNb(null);
    const dateJour = jour?.slice(0, 10);
    if (!dateJour || dateJour.length < 10) return;
    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc('fn_vivier_disponibilites' as any, {
        p_jour: dateJour,
        p_profession: profession || null,
      });
      if (!annule && !error && data && typeof (data as any).nb === 'number') {
        setNb((data as any).nb);
      }
    }, 400);
    return () => { annule = true; clearTimeout(timer); };
  }, [jour, profession]);

  if (!nb) return null;
  return (
    <p className="text-xs text-primary font-medium flex items-center gap-1">
      <Users aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />
      {nb > 1
        ? `${nb} soignants ont déclaré être disponibles ce jour-là — ils seront alertés des missions qui collent à leur planning.`
        : `1 soignant a déclaré être disponible ce jour-là — il sera alerté des missions qui collent à son planning.`}
    </p>
  );
}

import React, { useState, useEffect } from 'react';
import { Users } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface CompteurSoignantsDisponiblesProps {
  etablissementId: string;
}

export function CompteurSoignantsDisponibles({ etablissementId }: CompteurSoignantsDisponiblesProps) {
  const [count, setCount] = useState<number | null>(null);

  useEffect(() => {
    const load = async () => {
      // Get professions from open missions of this establishment
      const { data: missions } = await supabase
        .from('missions')
        .select('profession_requise')
        .eq('etablissement_id', etablissementId)
        .eq('statut', 'OUVERTE');

      if (!missions || missions.length === 0) {
        setCount(0);
        return;
      }

      const professions = [...new Set(missions.map(m => m.profession_requise))];

      // Count active soignants with matching profession
      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

      const { count: c } = await supabase
        .from('soignants')
        .select('id', { count: 'exact', head: true })
        .in('profession', professions)
        .gte('derniere_activite_le', sevenDaysAgo.toISOString());

      setCount(c ?? 0);
    };

    load();
  }, [etablissementId]);

  if (count === null) return null;

  return (
    <div className="card-base flex items-center gap-3">
      <div className="relative flex items-center justify-center">
        <div className="h-10 w-10 rounded-full bg-success/10 flex items-center justify-center">
          <Users className="h-5 w-5 text-success" />
        </div>
        {count > 0 && (
          <span className="absolute -top-0.5 -right-0.5 flex h-3 w-3">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75" />
            <span className="relative inline-flex rounded-full h-3 w-3 bg-success" />
          </span>
        )}
      </div>
      <div>
        <p className="text-2xl font-bold text-foreground">{count}</p>
        <p className="text-xs text-muted-foreground">soignant{count !== 1 ? 's' : ''} disponible{count !== 1 ? 's' : ''} maintenant</p>
      </div>
    </div>
  );
}

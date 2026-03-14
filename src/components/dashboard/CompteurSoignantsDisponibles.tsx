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
      const { data, error } = await supabase.rpc('fn_compteur_soignants_disponibles', {
        p_etablissement_id: etablissementId,
      });

      if (error) {
        console.error('[CompteurSoignantsDisponibles]', error.message);
        setCount(0);
        return;
      }

      setCount((data as any)?.disponibles ?? 0);
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

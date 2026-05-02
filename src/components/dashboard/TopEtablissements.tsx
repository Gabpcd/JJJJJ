import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Trophy, Building2, ArrowRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface TopEtab {
  etablissement_id: string;
  nom: string;
  ville: string | null;
  logo_url: string | null;
  nb_missions: number;
  derniere_mission_le: string | null;
}

export function TopEtablissements() {
  const navigate = useNavigate();
  const [items, setItems] = useState<TopEtab[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_top_etablissements_soignant' as any, { p_limit: 3 });
      if (!alive) return;
      setItems(((data as any) ?? []) as TopEtab[]);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (loading || items.length === 0) return null;

  return (
    <div className="card-base mb-6">
      <h2 className="text-base font-bold text-foreground inline-flex items-center gap-2 mb-3">
        <Trophy className="h-4 w-4 text-amber-500" /> Mes top établissements
      </h2>
      <div className="space-y-2">
        {items.map((e, idx) => (
          <button
            key={e.etablissement_id}
            type="button"
            onClick={() => navigate(`/soignant/etablissements/${e.etablissement_id}`)}
            className="w-full text-left rounded-xl p-2.5 transition-colors hover:bg-muted/50 flex items-center gap-3"
          >
            <span className={`h-8 w-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${idx === 0 ? 'bg-amber-100 text-amber-700' : idx === 1 ? 'bg-slate-100 text-slate-700' : 'bg-orange-100 text-orange-800'}`}>
              {idx + 1}
            </span>
            {e.logo_url ? (
              <img src={e.logo_url} alt="" className="h-8 w-8 rounded-lg object-cover border border-border shrink-0" />
            ) : (
              <div className="h-8 w-8 rounded-lg bg-muted flex items-center justify-center shrink-0">
                <Building2 className="h-4 w-4 text-muted-foreground" />
              </div>
            )}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground truncate">{e.nom}</p>
              <p className="text-xs text-muted-foreground">
                {e.nb_missions} mission{e.nb_missions > 1 ? 's' : ''}
                {e.ville && ` · ${e.ville}`}
                {e.derniere_mission_le && ` · dernière ${format(new Date(e.derniere_mission_le), 'd MMM', { locale: fr })}`}
              </p>
            </div>
            <ArrowRight className="h-4 w-4 text-muted-foreground shrink-0" />
          </button>
        ))}
      </div>
    </div>
  );
}

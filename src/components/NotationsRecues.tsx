import React, { useEffect, useState } from 'react';
import { Star, MessageSquare, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Notation {
  id: string;
  mission_id: string;
  mission_intitule: string;
  mission_fin_le: string;
  critere_1: number;
  critere_2: number;
  critere_3: number;
  critere_4: number;
  note_moyenne: number;
  commentaire: string | null;
  cree_le: string;
}

interface Props {
  audience: 'SOIGNANT' | 'ETAB';
}

const LABELS: Record<'SOIGNANT' | 'ETAB', string[]> = {
  SOIGNANT: ['Ponctualité', 'Professionnalisme', 'Qualité du soin', 'Communication'],
  ETAB: ['Accueil', 'Encadrement', 'Clarté des consignes', 'Paiement à temps'],
};

function Stars({ n }: { n: number }) {
  return (
    <span className="inline-flex">
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} className={`h-3.5 w-3.5 ${i <= n ? 'text-amber-400 fill-amber-400' : 'text-muted-foreground/30'}`} />
      ))}
    </span>
  );
}

export function NotationsRecues({ audience }: Props) {
  const [items, setItems] = useState<Notation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_lister_notations_recues' as any, { p_limit: 20 });
      if (!alive) return;
      if (Array.isArray(data)) setItems(data as Notation[]);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (loading) {
    return (
      <div className="card-base text-center py-8">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground mx-auto" />
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="card-base text-center py-8">
        <Star className="h-8 w-8 text-muted-foreground/30 mx-auto mb-2" />
        <p className="text-sm text-muted-foreground">Aucune notation reçue pour le moment.</p>
      </div>
    );
  }

  const labels = LABELS[audience];
  const cible = audience === 'SOIGNANT' ? 'Établissement' : 'Soignant';

  return (
    <div className="space-y-3">
      {items.map((n) => (
        <article key={n.id} className="card-base">
          <div className="flex items-start justify-between gap-3 mb-2">
            <div className="min-w-0">
              <p className="text-sm font-medium text-foreground truncate">{n.mission_intitule}</p>
              <p className="text-xs text-muted-foreground">
                Mission terminée le {format(new Date(n.mission_fin_le), 'd MMM yyyy', { locale: fr })}
                {' · '}Notée par : <strong>{cible} anonyme</strong>
                {' · '}{format(new Date(n.cree_le), 'd MMM', { locale: fr })}
              </p>
            </div>
            <span className="badge-base bg-amber-50 text-amber-700 text-[11px] font-semibold whitespace-nowrap">
              ⭐ {Number(n.note_moyenne).toFixed(1)}/5
            </span>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-2">
            {[n.critere_1, n.critere_2, n.critere_3, n.critere_4].map((v, i) => (
              <div key={i} className="rounded-xl border border-border bg-muted/30 p-2">
                <p className="text-[10px] uppercase font-semibold text-muted-foreground">{labels[i]}</p>
                <Stars n={v} />
              </div>
            ))}
          </div>

          {n.commentaire && (
            <div className="mt-3 rounded-xl bg-muted/30 border border-border p-3 inline-flex items-start gap-2 text-sm text-foreground">
              <MessageSquare className="h-3.5 w-3.5 text-muted-foreground shrink-0 mt-0.5" />
              <p className="text-xs leading-relaxed">{n.commentaire}</p>
            </div>
          )}
        </article>
      ))}
    </div>
  );
}

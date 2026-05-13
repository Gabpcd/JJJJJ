import React, { useEffect, useState } from 'react';
import { Star, MessageSquare, Loader2, Flag, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
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
  const [notationSignaler, setNotationSignaler] = useState<Notation | null>(null);

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

          <div className="mt-3 flex justify-end">
            <button
              onClick={() => setNotationSignaler(n)}
              className="text-[11px] text-muted-foreground hover:text-destructive inline-flex items-center gap-1"
            >
              <Flag className="h-3 w-3" /> Signaler cette évaluation
            </button>
          </div>
        </article>
      ))}

      {notationSignaler && (
        <ModaleSignaler
          notation={notationSignaler}
          onFermer={() => setNotationSignaler(null)}
        />
      )}
    </div>
  );
}

function ModaleSignaler({ notation, onFermer }: { notation: Notation; onFermer: () => void }) {
  const { afficherNotification } = useNotification();
  const [motif, setMotif] = useState('');
  const [loading, setLoading] = useState(false);

  async function signaler() {
    if (motif.trim().length < 10) {
      afficherNotification({ type: 'erreur', message: 'Veuillez expliquer le motif (min 10 caractères).' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_signaler_notation' as any, {
      p_notation_id: notation.id,
      p_motif: motif.trim(),
    });
    setLoading(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    const result = data as any;
    if (result && result.success === false) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur signalement.' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Signalement transmis à l\'administrateur Jolene.' });
    onFermer();
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-bold text-foreground">Signaler cette évaluation</h3>
          <button onClick={onFermer} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-semibold text-foreground">{notation.mission_intitule}</p>
          <p className="text-muted-foreground">Note moyenne : {Number(notation.note_moyenne).toFixed(1)}/5</p>
        </div>

        <p className="text-xs text-muted-foreground">
          Si vous pensez que cette évaluation est abusive, inappropriée ou injuste, signalez-la.
          Un administrateur Jolene examinera votre signalement et pourra masquer la notation si justifiée.
        </p>

        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif du signalement * (min 10 caractères)</span>
          <textarea
            value={motif}
            onChange={(e) => setMotif(e.target.value)}
            className="input-base"
            rows={4}
            placeholder="Expliquez pourquoi cette évaluation vous paraît abusive…"
            disabled={loading}
          />
          <span className="text-[10px] text-muted-foreground">{motif.length} / 10+</span>
        </label>

        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">Annuler</button>
          <button onClick={signaler} disabled={loading || motif.trim().length < 10} className="bg-destructive text-destructive-foreground rounded-xl px-4 py-2 text-sm font-medium hover:bg-destructive/90 disabled:opacity-50 flex-1 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Signaler
          </button>
        </div>
      </div>
    </div>
  );
}

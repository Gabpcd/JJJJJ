import { useEffect, useState } from 'react';
import { History, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface LitigeSimilaire {
  id: string;
  type_litige: string;
  resolution: string | null;
  en_faveur_de: string | null;
  cree_le: string;
  resolu_le: string | null;
  motif: string | null;
  statut: string;
  mission_id: string | null;
  montant_tresorerie_bloquee: number | null;
}

// Contexte d'aide à la décision : affiche à l'admin les litiges PASSÉS similaires
// (même type, même établissement) déjà résolus, pour cohérence des décisions.
// Branche fn_litiges_historique_similaires (jusque-là sans UI).
export function LitigesSimilairesPanel({ litigeId }: { litigeId: string }) {
  const [items, setItems] = useState<LitigeSimilaire[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      const { data } = await supabase.rpc('fn_litiges_historique_similaires' as any, {
        p_litige_id: litigeId,
        p_limit: 5,
      });
      if (!cancelled) {
        setItems(((data as unknown as LitigeSimilaire[]) ?? []).filter((l) => l.id !== litigeId));
        setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [litigeId]);

  if (loading) {
    return (
      <div className="flex items-center gap-2 rounded-lg border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Recherche de litiges similaires…
      </div>
    );
  }

  if (items.length === 0) return null;

  const faveurLabel = (v: string | null) =>
    v === 'SOIGNANT' ? 'soignant' : v === 'ETABLISSEMENT' ? 'établissement' : v === 'NEUTRE' ? 'neutre' : '—';

  return (
    <div className="rounded-lg border border-jolene-rose-200/50 bg-jolene-rose-50/40 dark:bg-jolene-rose-950/20 p-3">
      <p className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-foreground">
        <History className="h-3.5 w-3.5 text-primary" />
        Litiges similaires déjà résolus ({items.length}) — aide à la cohérence
      </p>
      <ul className="space-y-1.5">
        {items.map((l) => (
          <li key={l.id} className="text-[11px] text-muted-foreground border-t border-border/50 pt-1.5 first:border-0 first:pt-0">
            <span className="font-medium text-foreground">{l.type_litige}</span>
            {' · '}{new Date(l.cree_le).toLocaleDateString('fr-FR')}
            {l.resolu_le && <> → résolu en faveur du <span className="font-medium">{faveurLabel(l.en_faveur_de)}</span></>}
            {l.resolution && <span className="block italic opacity-80">« {l.resolution.slice(0, 120)}{l.resolution.length > 120 ? '…' : ''} »</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}

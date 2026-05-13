import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Info, ExternalLink, Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  soignantId: string;
  scoreFiabilite: number;
  /** Variant compact (icône seule) ou inline (badge entier hover) */
  trigger?: 'icon' | 'inline';
}

interface Composante {
  cle: string;
  label: string;
  poids: number;
  valeur: number | null;
}

/**
 * Popover détaillant la décomposition du score soignant inline.
 *
 * Sprint 7 PR 2 — Fix P1-5 audit Sprint 5.
 *
 * Affiche au clic / focus les 6 composantes Sprint 3.5 (notation 35%,
 * présentéisme 20%, ponctualité 15%, réactivité 10%, ancienneté 10%,
 * note étabs 10%) avec lien vers le profil complet.
 *
 * Données chargées via fn_soignant_score_breakdown si dispo, sinon
 * fallback affichage simplifié.
 */
export function PopoverScoreSoignant({ soignantId, scoreFiabilite, trigger = 'icon' }: Props) {
  const navigate = useNavigate();
  const [ouvert, setOuvert] = useState(false);
  const [composantes, setComposantes] = useState<Composante[] | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ouvert) return;
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOuvert(false);
    }
    function onEscape(e: KeyboardEvent) { if (e.key === 'Escape') setOuvert(false); }
    document.addEventListener('mousedown', onClick);
    document.addEventListener('keydown', onEscape);
    return () => {
      document.removeEventListener('mousedown', onClick);
      document.removeEventListener('keydown', onEscape);
    };
  }, [ouvert]);

  useEffect(() => {
    if (!ouvert || composantes) return;
    let cancelled = false;
    (async () => {
      try {
        const { data } = await supabase.rpc(
          'fn_soignant_score_breakdown' as any,
          { p_soignant_id: soignantId },
        );
        if (cancelled) return;
        const result = data as any;
        if (result?.success && Array.isArray(result.composantes)) {
          setComposantes(result.composantes as Composante[]);
        } else {
          setComposantes([]);
        }
      } catch {
        if (!cancelled) setComposantes([]);
      }
    })();
    return () => { cancelled = true; };
  }, [ouvert, composantes, soignantId]);

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); setOuvert((o) => !o); }}
        className="text-muted-foreground hover:text-primary"
        aria-label="Décomposition du score"
        aria-expanded={ouvert}
      >
        {trigger === 'icon'
          ? <Info className="h-3 w-3" />
          : <span className="underline-dotted decoration-dotted">détail</span>}
      </button>

      {ouvert && (
        <div
          role="dialog"
          className="absolute z-50 top-full mt-1 left-1/2 -translate-x-1/2 w-72 rounded-xl border border-border bg-card shadow-lg p-3 text-xs"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="flex items-center justify-between mb-2">
            <p className="font-bold text-foreground inline-flex items-center gap-1">
              <Star className="h-3 w-3 fill-yellow-400 text-yellow-400" />
              Score {scoreFiabilite}/100
            </p>
          </div>

          {composantes === null ? (
            <p className="text-muted-foreground italic">Chargement…</p>
          ) : composantes.length === 0 ? (
            <>
              <p className="text-muted-foreground mb-2">Détail indisponible pour ce soignant. Score basé sur :</p>
              <ul className="space-y-1 text-[11px] text-muted-foreground">
                <li>• Notations reçues (35%)</li>
                <li>• Présentéisme (20%)</li>
                <li>• Ponctualité (15%)</li>
                <li>• Réactivité (10%)</li>
                <li>• Ancienneté (10%)</li>
                <li>• Notations données aux étabs (10%)</li>
              </ul>
            </>
          ) : (
            <ul className="space-y-1.5">
              {composantes.map((c) => {
                const pct = c.valeur != null ? Math.round(c.valeur) : null;
                return (
                  <li key={c.cle} className="flex items-center justify-between gap-2">
                    <span className="text-muted-foreground flex-1 truncate">
                      {c.label} <span className="text-[10px]">({c.poids}%)</span>
                    </span>
                    <span className={`font-mono tabular-nums ${pct == null ? 'text-muted-foreground' : pct >= 70 ? 'text-success' : pct >= 50 ? 'text-foreground' : 'text-warning'}`}>
                      {pct != null ? `${pct}%` : '—'}
                    </span>
                  </li>
                );
              })}
            </ul>
          )}

          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); setOuvert(false); navigate(`/etablissement/soignants/${soignantId}`); }}
            className="mt-3 inline-flex items-center gap-1 text-[11px] text-primary hover:underline w-full justify-end"
          >
            Voir le profil complet <ExternalLink className="h-3 w-3" />
          </button>
        </div>
      )}
    </div>
  );
}

import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ShieldCheck, ArrowRight, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BadgeNiveauV2 } from '@/components/BadgeNiveauV2';

interface ScoreEtab {
  score_qualite: number | null;
  niveau: 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE' | null;
  composantes: {
    notation_pct: number | null;
    nb_notations: number;
    paiement_pct: number | null;
    nb_factures: number;
    nb_litiges_perdus: number;
  };
}

export function CardScoreQualiteEtab() {
  const navigate = useNavigate();
  const [score, setScore] = useState<ScoreEtab | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_mon_score_etab' as any);
      if (!alive) return;
      const payload = data as any;
      if (payload && !payload.error) setScore(payload as ScoreEtab);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (loading) {
    return (
      <div className="card-base mb-6 flex items-center justify-center py-6">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }
  if (!score) return null;

  const scoreNum = score.score_qualite != null ? Math.round(Number(score.score_qualite)) : null;
  const c = score.composantes;
  const nonNote = (c.nb_notations < 3) && (c.nb_factures === 0);

  return (
    <button
      type="button"
      onClick={() => navigate('/etablissement/score')}
      className="card-base hover:shadow-md transition-shadow w-full text-left mb-6 cursor-pointer"
    >
      <div className="flex items-center gap-4">
        <div className="rounded-2xl bg-primary/10 p-3 shrink-0">
          <ShieldCheck className="h-6 w-6 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-2 mb-1">
            <p className="text-sm font-semibold text-foreground">Mon score qualité</p>
            <ArrowRight className="h-4 w-4 text-muted-foreground" />
          </div>
          {nonNote ? (
            <div className="flex items-center gap-2">
              <BadgeNiveauV2 nonNote compact />
              <p className="text-xs text-muted-foreground">Score disponible après 3 notations soignants</p>
            </div>
          ) : (
            <div className="flex items-center gap-3">
              <p className="text-3xl font-extrabold text-primary">{scoreNum}<span className="text-sm text-muted-foreground"> / 100</span></p>
              <BadgeNiveauV2 niveau={score.niveau ?? undefined} compact />
            </div>
          )}
          <p className="text-xs text-muted-foreground mt-1">
            {c.nb_notations} notation{c.nb_notations > 1 ? 's' : ''} · {c.nb_factures} facture{c.nb_factures > 1 ? 's' : ''} payée{c.nb_factures > 1 ? 's' : ''}
            {c.nb_litiges_perdus > 0 && ` · ${c.nb_litiges_perdus} litige${c.nb_litiges_perdus > 1 ? 's' : ''}`}
          </p>
        </div>
      </div>
    </button>
  );
}

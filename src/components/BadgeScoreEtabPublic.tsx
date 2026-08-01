import React, { useEffect, useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BadgeNiveauV2 } from '@/components/BadgeNiveauV2';

interface Props {
  etablissementId: string;
}

interface ScorePub {
  score_qualite: number | null;
  niveau: 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE' | null;
}

/**
 * Mini badge "Score qualité de l'étab" affiché côté soignant sur DetailMissionSoignant.
 * Appelle fn_score_etab_public (autorisé seulement si soignant a déjà eu une mission avec cet étab).
 */
export function BadgeScoreEtabPublic({ etablissementId }: Props) {
  const [data, setData] = useState<ScorePub | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: payload, error } = await supabase.rpc('fn_score_etab_public', { p_etab_id: etablissementId });
      if (!alive) return;
      if (!error && payload && !(payload as any).error) {
        setData(payload as unknown as ScorePub);
      }
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [etablissementId]);

  if (loading || !data) return null;
  if (data.score_qualite == null) {
    return <BadgeNiveauV2 nonNote compact />;
  }

  return (
    <span className="inline-flex items-center gap-1.5">
      <BadgeNiveauV2 niveau={data.niveau ?? undefined} compact />
      <span className="text-[10px] text-muted-foreground">
        <ShieldCheck className="h-3 w-3 inline mr-0.5" />
        {Math.round(Number(data.score_qualite))}/100
      </span>
    </span>
  );
}

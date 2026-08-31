import { useState, useEffect, useRef } from 'react';
import { Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  soignantId: string;
  etablissementId: string;
}

export function BoutonFavori({ soignantId, etablissementId }: Props) {
  const [favori, setFavori] = useState(false);
  const [loading, setLoading] = useState(false);
  const [bouncing, setBouncing] = useState(false);

  useEffect(() => {
    (supabase.from('favoris_etab_soignant' as any) as any)
      .select('id')
      .eq('etablissement_id', etablissementId)
      .eq('soignant_id', soignantId)
      .maybeSingle()
      .then(({ data }: any) => setFavori(!!data));
  }, [soignantId, etablissementId]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setLoading(true);
    if (favori) {
      await (supabase.from('favoris_etab_soignant' as any) as any)
        .delete()
        .eq('etablissement_id', etablissementId)
        .eq('soignant_id', soignantId);
      setFavori(false);
    } else {
      await (supabase.from('favoris_etab_soignant' as any) as any)
        .insert({ etablissement_id: etablissementId, soignant_id: soignantId });
      setFavori(true);
      setBouncing(true);
      setTimeout(() => setBouncing(false), 400);
    }
    setLoading(false);
  };

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={loading}
      title={favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      aria-label={favori ? 'Retirer ce soignant des favoris' : 'Ajouter ce soignant aux favoris'}
      aria-pressed={favori}
      className={`inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl p-0 transition-colors disabled:opacity-50 disabled:pointer-events-none ${bouncing ? 'animate-bounce-fav' : ''} ${
        favori ? 'text-warning' : 'text-muted-foreground hover:text-warning'
      }`}
    >
      <Star aria-hidden="true" className={`h-5 w-5 ${favori ? 'fill-warning' : ''}`} />
    </button>
  );
}

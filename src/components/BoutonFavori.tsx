import { useState, useEffect } from 'react';
import { Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Props {
  soignantId: string;
  etablissementId: string;
  compact?: boolean;
}

export function BoutonFavori({ soignantId, etablissementId, compact }: Props) {
  const [favori, setFavori] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.from('favoris')
      .select('id')
      .eq('etablissement_id', etablissementId)
      .eq('soignant_id', soignantId)
      .maybeSingle()
      .then(({ data }) => setFavori(!!data));
  }, [soignantId, etablissementId]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setLoading(true);
    if (favori) {
      await supabase.from('favoris')
        .delete()
        .eq('etablissement_id', etablissementId)
        .eq('soignant_id', soignantId);
      setFavori(false);
    } else {
      await supabase.from('favoris')
        .insert({ etablissement_id: etablissementId, soignant_id: soignantId });
      setFavori(true);
    }
    setLoading(false);
  };

  return (
    <button
      onClick={toggle}
      disabled={loading}
      title={favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      className={`p-1.5 rounded-lg transition-colors disabled:opacity-50 ${
        favori ? 'text-warning' : 'text-muted-foreground hover:text-warning'
      }`}
    >
      <Star className={`h-4 w-4 ${favori ? 'fill-warning' : ''}`} />
    </button>
  );
}

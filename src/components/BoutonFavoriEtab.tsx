import { useState, useEffect } from 'react';
import { Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

interface Props {
  etablissementId: string;
  // Mode compact (icon-only) vs avec libellé
  mode?: 'icon' | 'label';
  onChange?: (favori: boolean) => void;
}

/**
 * Bouton ⭐ pour soignant : favoriser un établissement.
 * Insère/supprime dans favoris_soignant_etab via fn_toggle_favori_etablissement.
 */
export function BoutonFavoriEtab({ etablissementId, mode = 'icon', onChange }: Props) {
  const { user } = useAuth();
  const [favori, setFavori] = useState(false);
  const [loading, setLoading] = useState(false);
  const [bouncing, setBouncing] = useState(false);

  useEffect(() => {
    if (!user || !etablissementId) return;
    (supabase.from('favoris_soignant_etab' as any) as any)
      .select('id')
      .eq('soignant_id', user.id)
      .eq('etablissement_id', etablissementId)
      .maybeSingle()
      .then(({ data }: any) => setFavori(!!data));
  }, [etablissementId, user?.id]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
    if (!user) return;
    setLoading(true);
    const newFav = !favori;
    const { data, error } = await supabase.rpc('fn_toggle_favori_etablissement' as any, {
      p_etablissement_id: etablissementId,
      p_actif: newFav,
    });
    setLoading(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const r = data as any;
    if (r?.success) {
      setFavori(newFav);
      onChange?.(newFav);
      if (newFav) {
        setBouncing(true);
        setTimeout(() => setBouncing(false), 400);
      }
    } else {
      toast.error(r?.error ?? 'Erreur favori');
    }
  };

  if (mode === 'label') {
    return (
      <button
        type="button"
        onClick={toggle}
        disabled={loading}
        className={`btn-secondary text-xs inline-flex items-center gap-1.5 ${bouncing ? 'animate-bounce-fav' : ''}`}
        title={favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      >
        <Star className={`h-4 w-4 ${favori ? 'fill-warning text-warning' : ''}`} />
        {favori ? 'Favori' : 'Ajouter aux favoris'}
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={loading}
      title={favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      aria-label={favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      // Cible tactile ≥ 44 pt (Lot 6b.3) : l'étoile visuelle reste petite,
      // la zone de tap est étendue par marges négatives (pas de décalage layout).
      className={`min-h-[44px] min-w-[44px] -m-2.5 flex items-center justify-center rounded-lg transition-colors disabled:opacity-50 disabled:pointer-events-none ${bouncing ? 'animate-bounce-fav' : ''} ${
        favori ? 'text-warning' : 'text-muted-foreground hover:text-warning'
      }`}
    >
      <Star className={`h-4 w-4 ${favori ? 'fill-warning' : ''}`} />
    </button>
  );
}

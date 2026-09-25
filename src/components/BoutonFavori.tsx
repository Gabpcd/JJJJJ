import { useState, useEffect, useRef } from 'react';
import { AlertCircle, Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Props {
  soignantId: string;
  etablissementId: string;
}

export function BoutonFavori({ soignantId, etablissementId }: Props) {
  const [favori, setFavori] = useState(false);
  const [loading, setLoading] = useState(true);
  const [bouncing, setBouncing] = useState(false);
  const [erreurLecture, setErreurLecture] = useState(false);
  const [tentative, setTentative] = useState(0);
  const animation = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    let actif = true;
    setLoading(true);
    setErreurLecture(false);
    const charger = async () => {
      try {
        const { data, error } = await (supabase.from('favoris_etab_soignant' as any) as any)
          .select('id').eq('etablissement_id', etablissementId).eq('soignant_id', soignantId).maybeSingle();
        if (error) throw error;
        if (actif) setFavori(!!data);
      } catch {
        if (actif) setErreurLecture(true);
      } finally {
        if (actif) setLoading(false);
      }
    };
    void charger();
    return () => {
      actif = false;
      if (animation.current) clearTimeout(animation.current);
    };
  }, [soignantId, etablissementId, tentative]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (erreurLecture) { setTentative((n) => n + 1); return; }
    setLoading(true);
    try {
      const { error } = favori
        ? await (supabase.from('favoris_etab_soignant' as any) as any)
        .delete()
        .eq('etablissement_id', etablissementId)
        .eq('soignant_id', soignantId)
        : await (supabase.from('favoris_etab_soignant' as any) as any)
        .insert({ etablissement_id: etablissementId, soignant_id: soignantId });
      if (error) throw error;
      setFavori(!favori);
      if (!favori) {
        setBouncing(true);
        animation.current = setTimeout(() => setBouncing(false), 400);
      }
    } catch {
      toast.error(favori ? 'Impossible de retirer ce soignant des favoris. Veuillez réessayer.' : 'Impossible d’ajouter ce soignant aux favoris. Veuillez réessayer.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={loading}
      title={erreurLecture ? 'Favori indisponible — réessayer' : favori ? 'Retirer des favoris' : 'Ajouter aux favoris'}
      aria-label={erreurLecture ? 'Réessayer le chargement du favori' : favori ? 'Retirer ce soignant des favoris' : 'Ajouter ce soignant aux favoris'}
      aria-pressed={favori}
      className={`inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl p-0 transition-colors disabled:opacity-50 disabled:pointer-events-none ${bouncing ? 'animate-bounce-fav' : ''} ${
        favori ? 'text-warning' : 'text-muted-foreground hover:text-warning'
      }`}
    >
      {erreurLecture ? <AlertCircle aria-hidden="true" className="h-5 w-5 text-destructive" /> : <Star aria-hidden="true" className={`h-5 w-5 ${favori ? 'fill-warning' : ''}`} />}
    </button>
  );
}

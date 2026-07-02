/**
 * BoutonSauvegarderMission — étoile « sauvegarder cette mission » (D1, Lot 6c).
 *
 * MÊME sémantique que le ⭐ du deck de swipe : favoris de MISSIONS illimités
 * (table missions_sauvegardees), synchronisés entre la carte liste et le swipe.
 * Distinct du favori d'ÉTABLISSEMENT (BoutonFavoriEtab), qui vit sur la fiche
 * établissement.
 */
import React, { useEffect, useState } from 'react';
import { Star } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

interface Props {
  missionId: string;
  className?: string;
}

export const BoutonSauvegarderMission = React.memo(function BoutonSauvegarderMission({ missionId, className = '' }: Props) {
  const { user } = useAuth();
  const [sauvegardee, setSauvegardee] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase
      .from('missions_sauvegardees' as any)
      .select('id')
      .eq('mission_id', missionId)
      .maybeSingle()
      .then(({ data }) => { if (!cancelled) setSauvegardee(!!data); });
    return () => { cancelled = true; };
  }, [user, missionId]);

  const toggle = async (e: React.MouseEvent) => {
    e.stopPropagation(); // la carte parente est cliquable (détail mission)
    if (!user || loading) return;
    setLoading(true);
    if (sauvegardee) {
      const { error } = await supabase
        .from('missions_sauvegardees' as any)
        .delete()
        .eq('mission_id', missionId)
        .eq('soignant_id', user.id);
      if (!error) {
        setSauvegardee(false);
        toast.success('Mission retirée de tes favoris');
      }
    } else {
      const { error } = await supabase
        .from('missions_sauvegardees' as any)
        .insert({ mission_id: missionId, soignant_id: user.id } as any);
      if (!error) {
        setSauvegardee(true);
        toast.success('Mission sauvegardée ⭐');
      } else {
        toast.error('Sauvegarde impossible pour le moment');
      }
    }
    setLoading(false);
  };

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={loading}
      title={sauvegardee ? 'Retirer de mes missions sauvegardées' : 'Sauvegarder cette mission'}
      aria-label={sauvegardee ? 'Retirer de mes missions sauvegardées' : 'Sauvegarder cette mission'}
      aria-pressed={sauvegardee}
      // Cible tactile ≥ 44 pt, zone étendue par marges négatives (cf. Lot 6b.3)
      className={`min-h-[44px] min-w-[44px] -m-2.5 flex items-center justify-center rounded-lg transition-colors disabled:opacity-50 disabled:pointer-events-none ${
        sauvegardee ? 'text-jolene-butter-600' : 'text-muted-foreground hover:text-jolene-butter-600'
      } ${className}`}
    >
      <Star className={`h-4 w-4 ${sauvegardee ? 'fill-jolene-butter-400' : ''}`} />
    </button>
  );
});

export default BoutonSauvegarderMission;

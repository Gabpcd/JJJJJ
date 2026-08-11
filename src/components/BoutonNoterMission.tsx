import React, { useCallback, useEffect, useState } from 'react';
import { Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { ModalNoterMission } from '@/components/ModalNoterMission';

interface Props {
  missionId: string;
  sens: 'ETAB_VERS_SOIGNANT' | 'SOIGNANT_VERS_ETAB';
  missionIntitule?: string;
  /** Variant : "primary" (bouton plein), "secondary" (bouton outline) */
  variant?: 'primary' | 'secondary';
  /** Si déjà noté, masquer le bouton (default true) */
  hideIfNoted?: boolean;
}

/**
 * Bouton "Noter" qui ouvre la ModalNoterMission, vérifie si déjà noté,
 * et auto-cache si déjà fait. À placer sur les pages détail mission TERMINEE.
 */
export function BoutonNoterMission({ missionId, sens, missionIntitule, variant = 'primary', hideIfNoted = true }: Props) {
  const [open, setOpen] = useState(false);
  const [dejaNote, setDejaNote] = useState(false);
  const [loading, setLoading] = useState(true);

  const verif = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from('notations_missions' as any)
      .select('id')
      .eq('mission_id', missionId)
      .eq('sens', sens)
      .maybeSingle();
    setDejaNote(!!data);
    setLoading(false);
  }, [missionId, sens]);

  useEffect(() => { void verif(); }, [verif]);

  if (loading) return null;
  if (dejaNote && hideIfNoted) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-success/10 text-success px-2 py-0.5 text-[10px] font-medium">
        <Star className="h-3 w-3 fill-current" /> Notation envoyée
      </span>
    );
  }

  const cls = variant === 'primary'
    ? 'btn-primary text-xs inline-flex items-center gap-1.5'
    : 'btn-secondary text-xs inline-flex items-center gap-1.5';

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={cls}>
        <Star className="h-3.5 w-3.5" />
        {sens === 'ETAB_VERS_SOIGNANT' ? 'Noter le soignant' : 'Noter l\'établissement'}
      </button>
      {open && (
        <ModalNoterMission
          missionId={missionId}
          sens={sens}
          missionIntitule={missionIntitule}
          onClose={() => setOpen(false)}
          onSuccess={() => verif()}
        />
      )}
    </>
  );
}

import React, { useCallback, useEffect, useState } from 'react';
import { Loader2, Star } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { ModalNoterMission } from '@/components/ModalNoterMission';
import { avecDelai } from '@/lib/avecDelai';
import { handleErrorSilent } from '@/lib/handleError';

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
  const [verificationIndisponible, setVerificationIndisponible] = useState(false);

  const verif = useCallback(async () => {
    setLoading(true);
    setVerificationIndisponible(false);
    try {
      const { data, error } = await avecDelai(
        supabase
          .from('notations_missions' as any)
          .select('id')
          .eq('mission_id', missionId)
          .eq('sens', sens)
          .maybeSingle(),
        6_000,
        'La vérification de la notation met trop de temps à répondre.',
      );
      if (error) throw error;
      setDejaNote(!!data);
    } catch (error) {
      // Le bouton reste utilisable : la RPC d'envoi contrôle elle-même
      // l'éligibilité et l'unicité, donc aucune double notation n'est possible.
      setVerificationIndisponible(true);
      handleErrorSilent(error, 'BoutonNoterMission.verification');
    } finally {
      setLoading(false);
    }
  }, [missionId, sens]);

  useEffect(() => { void verif(); }, [verif]);

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
      <button type="button" onClick={() => setOpen(true)} className={cls} aria-busy={loading}>
        {loading
          ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />
          : <Star className="h-3.5 w-3.5" aria-hidden="true" />}
        {sens === 'ETAB_VERS_SOIGNANT' ? 'Noter le soignant' : 'Noter l\'établissement'}
      </button>
      {verificationIndisponible && (
        <span className="sr-only" role="status">
          Vérification temporairement indisponible. L'éligibilité sera contrôlée à l'envoi.
        </span>
      )}
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

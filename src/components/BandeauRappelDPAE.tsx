import React, { useEffect, useState } from 'react';
import { AlertTriangle, ExternalLink, CheckCircle, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface BandeauRappelDPAEProps {
  contratId?: string;
  dpaeEffectuee?: boolean;
  dpaeEffectueeLe?: string | null;
  typeContrat?: string;
}

export function BandeauRappelDPAE({ contratId, dpaeEffectuee, dpaeEffectueeLe, typeContrat }: BandeauRappelDPAEProps) {
  const { afficherNotification } = useNotification();
  const [confirming, setConfirming] = useState(false);
  const [confirmed, setConfirmed] = useState(dpaeEffectuee ?? false);
  const [confirmedDate, setConfirmedDate] = useState(dpaeEffectueeLe ?? null);

  useEffect(() => {
    setConfirmed(dpaeEffectuee ?? false);
    setConfirmedDate(dpaeEffectueeLe ?? null);
  }, [dpaeEffectuee, dpaeEffectueeLe]);

  // Afficher uniquement pour les contrats CDDU
  if (typeContrat !== 'CDDU') return null;

  const handleConfirmer = async () => {
    if (!contratId) return;
    setConfirming(true);
    try {
      const { data, error } = await supabase.rpc('fn_confirmer_dpae' as any, {
        p_contrat_id: contratId,
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      setConfirmed(true);
      setConfirmedDate((data as any)?.dpae_effectuee_le ?? new Date().toISOString());
      afficherNotification({ type: 'succes', message: 'DPAE confirmée avec succès !' });
    } catch (err) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(err) });
    } finally {
      setConfirming(false);
    }
  };

  if (confirmed) {
    return (
      <div className="bg-success/10 border border-success/30 rounded-xl p-4 flex items-start gap-3">
        <CheckCircle className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-success">
            ✅ DPAE effectuée{confirmedDate ? ` le ${format(new Date(confirmedDate), 'd MMMM yyyy', { locale: fr })}` : ''}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 flex items-start gap-3">
      <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
      <div className="flex-1">
        <p className="text-sm font-semibold text-warning">
          ⚠️ Rappel légal : effectuez la Déclaration Préalable à l'Embauche (DPAE) sur net-entreprises.fr avant le début de la mission.
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          La DPAE est obligatoire pour les contrats CDDU. Pour les remplacements libéraux, elle n'est pas requise.
        </p>
        <div className="flex flex-wrap items-center gap-3 mt-2">
          <a
            href="https://www.net-entreprises.fr"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
          >
            Accéder à net-entreprises.fr <ExternalLink className="h-3 w-3" />
          </a>
          {contratId && (
            <button
              onClick={handleConfirmer}
              disabled={confirming}
              className="inline-flex items-center gap-1 text-xs font-medium text-success bg-success/10 hover:bg-success/20 rounded-lg px-3 py-1.5 transition-colors disabled:opacity-50"
            >
              {confirming ? <Loader2 className="h-3 w-3 animate-spin" /> : <CheckCircle className="h-3 w-3" />}
              J'ai effectué la DPAE
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

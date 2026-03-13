import React, { useState } from 'react';
import { AlertTriangle, ExternalLink, CheckCircle, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface BandeauRappelDUEProps {
  contratId?: string;
  dueEffectuee?: boolean;
  dueEffectueeLe?: string | null;
}

export function BandeauRappelDUE({ contratId, dueEffectuee, dueEffectueeLe }: BandeauRappelDUEProps) {
  const { afficherNotification } = useNotification();
  const [confirming, setConfirming] = useState(false);
  const [confirmed, setConfirmed] = useState(dueEffectuee ?? false);
  const [confirmedDate, setConfirmedDate] = useState(dueEffectueeLe ?? null);

  const handleConfirmer = async () => {
    if (!contratId) return;
    setConfirming(true);
    try {
      const { data, error } = await supabase.rpc('fn_confirmer_due' as any, { p_contrat_id: contratId });
      if (error) throw error;
      if ((data as any)?.success === false) throw new Error((data as any).error);
      setConfirmed(true);
      setConfirmedDate(new Date().toISOString());
      afficherNotification({ type: 'succes', message: 'DUE confirmée.' });
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
            ✅ DUE effectuée{confirmedDate ? ` le ${format(new Date(confirmedDate), 'd MMMM yyyy', { locale: fr })}` : ''}
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
          ⚠️ Rappel légal : effectuez la Déclaration Unique d'Embauche (DUE) sur net-entreprises.fr avant le début de la mission.
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
              J'ai effectué la DUE
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

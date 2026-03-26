import React, { useState } from 'react';
import { Ban } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { RpcSuccessOrError } from '@/lib/supabase-rpc-types';

interface BoutonExclusionProps {
  excluId: string;
  typeExcluPar: 'SOIGNANT' | 'ETABLISSEMENT';
  label?: string;
  onDone?: () => void;
}

export function BoutonExclusion({ excluId, typeExcluPar, label, onDone }: BoutonExclusionProps) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [showModal, setShowModal] = useState(false);
  const [motif, setMotif] = useState('');
  const [saving, setSaving] = useState(false);

  const handleExclure = async () => {
    if (!user) return;
    setSaving(true);

    const { data, error } = await supabase.rpc('fn_exclure_utilisateur' as any, {
      p_exclu_id: excluId,
      p_type: typeExcluPar,
      p_motif: motif.trim() || null,
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if (data && !(data as any).success) {
      afficherNotification({ type: 'erreur', message: (data as any).error });
    } else {
      afficherNotification({ type: 'succes', message: 'Exclusion enregistrée. Les missions ne seront plus visibles.' });
      onDone?.();
    }
    setSaving(false);
    setShowModal(false);
    setMotif('');
  };

  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        className="flex items-center gap-1.5 text-xs text-destructive hover:text-destructive/80 font-medium"
      >
        <Ban className="h-3.5 w-3.5" /> {label || '🚫 Ne plus travailler ensemble'}
      </button>

      {showModal && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center">
          <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={() => setShowModal(false)} />
          <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full">
            <h3 className="text-lg font-bold text-foreground mb-2">🚫 Confirmer l'exclusion</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Les missions de cette partie ne seront plus visibles. Vous pourrez annuler cette exclusion depuis vos paramètres.
            </p>
            <div className="mb-4">
              <label className="text-sm font-medium text-foreground mb-1.5 block">Motif (optionnel)</label>
              <textarea
                value={motif}
                onChange={(e) => setMotif(e.target.value)}
                placeholder="Indiquez un motif si vous le souhaitez..."
                className="input-base min-h-[80px]"
                maxLength={500}
              />
            </div>
            <div className="flex gap-3 justify-end">
              <button onClick={() => setShowModal(false)} className="btn-secondary text-sm px-4 py-2">Annuler</button>
              <button onClick={handleExclure} disabled={saving} className="btn-danger text-sm px-4 py-2 disabled:opacity-50">
                {saving ? 'En cours...' : 'Confirmer l\'exclusion'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

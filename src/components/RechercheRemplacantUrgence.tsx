import React, { useState } from 'react';
import { Send, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { RpcSoignantsUrgence } from '@/lib/supabase-rpc-types';

interface RechercheRemplacantUrgenceProps {
  missionId: string;
  onPropose: () => void;
  onError: (msg: string) => void;
  onSuccess: (msg: string) => void;
}

export function RechercheRemplacantUrgence({ missionId, onPropose, onError, onSuccess }: RechercheRemplacantUrgenceProps) {
  const [soignants, setSoignants] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [proposing, setProposing] = useState<string | null>(null);

  const chercher = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_soignants_urgence' as any, { p_mission_id: missionId });
    if (error) {
      onError(extraireMessageErreur(error));
    } else {
      setSoignants(Array.isArray(data) ? data : []);
      setLoaded(true);
    }
    setLoading(false);
  };

  const proposer = async (soignantId: string) => {
    setProposing(soignantId);
    try {
      // Check for existing candidature to avoid duplicate key error
      const { data: existing } = await supabase
        .from('candidatures')
        .select('id, statut')
        .eq('mission_id', missionId)
        .eq('soignant_id', soignantId)
        .maybeSingle();

      if (existing) {
        if (existing.statut === 'REFUSEE' || existing.statut === 'EXPIREE') {
          // Update existing rejected/expired candidature to PROPOSEE
          const { error: updateErr } = await supabase
            .from('candidatures')
            .update({ statut: 'PROPOSEE', traite_le: null, motif_refus: null })
            .eq('id', existing.id);
          if (updateErr) throw updateErr;
        } else {
          onError('Ce soignant a déjà une candidature en cours pour cette mission.');
          setProposing(null);
          return;
        }
      } else {
        const { error } = await supabase.rpc('fn_proposer_mission_soignant' as any, {
          p_mission_id: missionId,
          p_soignant_id: soignantId,
        });
        if (error) throw error;
      }
      onSuccess('Mission proposée au soignant !');
      onPropose();
    } catch (err: any) {
      onError(extraireMessageErreur(err));
    }
    setProposing(null);
  };

  if (!loaded) {
    return (
      <button
        onClick={chercher}
        disabled={loading}
        className="w-full btn-danger text-sm py-3 flex items-center justify-center gap-2"
      >
        {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : '🚨'}
        {loading ? 'Recherche en cours…' : 'Rechercher un remplaçant d\'urgence'}
      </button>
    );
  }

  return (
    <div className="card-base border-destructive/30">
      <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
        🚨 Soignants du pool urgence
      </h3>
      {soignants.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-4">Aucun soignant urgence disponible dans le rayon.</p>
      ) : (
        <div className="space-y-2">
          {soignants.map((s: any) => (
            <div key={s.soignant_id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
              <div>
                <p className="text-sm font-medium text-foreground">
                  {s.prenom} {s.nom}
                  <span className="badge-base bg-destructive/10 text-destructive text-[10px] ml-2">🔥 Urgence</span>
                </p>
                <p className="text-xs text-muted-foreground">
                  ⭐ {s.score_fiabilite}/100
                  {s.distance_km != null && ` · ${s.distance_km} km`}
                </p>
              </div>
              <button
                onClick={() => proposer(s.soignant_id)}
                disabled={proposing === s.soignant_id}
                className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
              >
                <Send className="h-3.5 w-3.5" />
                {proposing === s.soignant_id ? '…' : 'Proposer'}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

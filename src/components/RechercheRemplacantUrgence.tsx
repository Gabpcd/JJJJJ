import React, { useState } from 'react';
import { Send, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { RpcSoignantsUrgence } from '@/lib/supabase-rpc-types';
import { ChoixContratDialog } from '@/components/ChoixContratDialog';

interface RechercheRemplacantUrgenceProps {
  missionId: string;
  onPropose: () => void;
  onError: (msg: string) => void;
  onSuccess: (msg: string) => void;
}

export function RechercheRemplacantUrgence({ missionId, onPropose, onError, onSuccess }: RechercheRemplacantUrgenceProps) {
  const [soignants, setSoignants] = useState<RpcSoignantsUrgence[]>([]);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [proposing, setProposing] = useState<string | null>(null);
  const [choixDialog, setChoixDialog] = useState<{ open: boolean; options: { value: string; label: string }[]; soignantId: string | null }>({ open: false, options: [], soignantId: null });

  const chercher = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_soignants_urgence' as any, { p_mission_id: missionId });
    if (error) {
      onError(extraireMessageErreur(error));
    } else {
      setSoignants(Array.isArray(data) ? (data as unknown as RpcSoignantsUrgence[]) : []);
      setLoaded(true);
    }
    setLoading(false);
  };

  const proposer = async (soignantId: string, choixContrat?: string) => {
    setProposing(soignantId);
    try {
      // Toute proposition, y compris la réactivation d'une ancienne
      // candidature refusée/expirée, passe par la RPC atomique : le frontend
      // ne contourne ni les contrôles de profession, ni le planning, ni les
      // notifications.
      const params: any = { p_mission_id: missionId, p_soignant_id: soignantId };
      if (choixContrat) params.p_choix_contrat = choixContrat;
      const { data, error } = await supabase.rpc('fn_proposer_mission_soignant' as any, params);
      if (error) throw error;

      if ((data as any)?.choix_requis) {
        setChoixDialog({ open: true, options: (data as any).options || [], soignantId });
        setProposing(null);
        return;
      }

      if ((data as any)?.error) {
        onError((data as any).message || (data as any).error);
        setProposing(null);
        return;
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
    <>
      <div className="card-base border-destructive/30">
        <h3 className="font-semibold text-foreground mb-3 flex items-center gap-2">
          🚨 Soignants du pool urgence
        </h3>
        {soignants.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-4">Aucun soignant urgence disponible dans le rayon.</p>
        ) : (
          <div className="space-y-2">
            {soignants.map((s) => (
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

      <ChoixContratDialog
        open={choixDialog.open}
        options={choixDialog.options}
        onClose={() => setChoixDialog({ open: false, options: [], soignantId: null })}
        onChoose={(val) => {
          const sid = choixDialog.soignantId;
          setChoixDialog({ open: false, options: [], soignantId: null });
          if (sid) proposer(sid, val);
        }}
        loading={proposing === choixDialog.soignantId}
      />
    </>
  );
}

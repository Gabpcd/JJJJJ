import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Ban, Trash2, ShieldAlert } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { fetchEtablissementsSafe } from '@/lib/etablissements';

type Onglet = 'envoyees' | 'recues';

interface ExclusionRecue {
  id: string;
  exclu_par: string;
  motif: string | null;
  cree_le: string;
  nom_etablissement: string | null;
}

export default function ExclusionsSoignant() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [exclusions, setExclusions] = useState<any[]>([]);
  const [exclusionsRecues, setExclusionsRecues] = useState<ExclusionRecue[]>([]);
  const [loading, setLoading] = useState(true);
  const [suppressionExcluId, setSuppressionExcluId] = useState<string | null>(null);
  const [onglet, setOnglet] = useState<Onglet>('envoyees');

  const charger = async () => {
    if (!user) return;

    const [resEnvoyees, resRecues] = await Promise.all([
      supabase
        .from('exclusions')
        .select('id, exclu_id, exclu_par, motif, type_exclu_par, cree_le')
        .eq('exclu_par', user.id)
        .order('cree_le', { ascending: false }),
      supabase.rpc('fn_mes_exclusions_recues' as any),
    ]);

    let list = resEnvoyees.data || [];
    if (list.length > 0) {
      const etabIds = list.map((e: any) => e.exclu_id);
      const etabMap = await fetchEtablissementsSafe(etabIds);
      list = list.map((e: any) => ({ ...e, nom_exclu: etabMap[e.exclu_id]?.nom || e.exclu_id }));
    }
    setExclusions(list);
    setExclusionsRecues((resRecues.data as ExclusionRecue[]) || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const supprimerExclusion = async () => {
    if (!suppressionExcluId) return;
    const { data, error } = await supabase.rpc('fn_retirer_exclusion' as any, {
      p_exclu_id: suppressionExcluId,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if (data && !(data as any).success) {
      afficherNotification({ type: 'erreur', message: (data as any).error });
    } else {
      afficherNotification({ type: 'succes', message: 'Exclusion supprimée.' });
      charger();
    }
    setSuppressionExcluId(null);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-6 flex items-center gap-2">
        <Ban className="h-5 w-5 text-destructive" /> Mes exclusions
      </h1>

      {/* Tabs */}
      <div className="flex gap-1 mb-6 bg-muted rounded-lg p-1">
        <button
          onClick={() => setOnglet('envoyees')}
          className={`flex-1 text-sm font-medium py-2 px-3 rounded-md transition-colors ${
            onglet === 'envoyees'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          Envoyées ({exclusions.length})
        </button>
        <button
          onClick={() => setOnglet('recues')}
          className={`flex-1 text-sm font-medium py-2 px-3 rounded-md transition-colors ${
            onglet === 'recues'
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          Reçues ({exclusionsRecues.length})
        </button>
      </div>

      {/* Envoyées */}
      {onglet === 'envoyees' && (
        <>
          {exclusions.length === 0 ? (
            <EtatVide icone={Ban} titre="Aucune exclusion" sousTitre="Vous n'avez bloqué aucun établissement." />
          ) : (
            <div className="space-y-3">
              {exclusions.map((e: any) => (
                <div key={e.id} className="card-base flex items-center justify-between">
                  <div>
                    <p className="font-semibold text-foreground text-sm">{e.nom_exclu}</p>
                    {e.motif && <p className="text-xs text-muted-foreground">{e.motif}</p>}
                    <p className="text-[10px] text-muted-foreground/60">
                      Depuis le {format(new Date(e.cree_le), 'd MMM yyyy', { locale: fr })}
                    </p>
                  </div>
                  <button onClick={() => setSuppressionExcluId(e.exclu_id)} className="text-destructive hover:text-destructive/80 p-2">
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {/* Reçues */}
      {onglet === 'recues' && (
        <>
          <div className="bg-muted/50 border border-border rounded-lg p-4 mb-4">
            <div className="flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 text-warning mt-0.5 shrink-0" />
              <p className="text-xs text-muted-foreground">
                Ces établissements ont choisi de ne plus travailler avec vous. Leurs missions ne vous sont plus proposées.
              </p>
            </div>
          </div>

          {exclusionsRecues.length === 0 ? (
            <EtatVide icone={Ban} titre="Aucune exclusion reçue" sousTitre="Aucun établissement ne vous a exclu." />
          ) : (
            <div className="space-y-3">
              {exclusionsRecues.map((e) => (
                <div key={e.id} className="card-base">
                  <p className="font-semibold text-foreground text-sm">{e.nom_etablissement || 'Établissement inconnu'}</p>
                  {e.motif && <p className="text-xs text-muted-foreground mt-1">{e.motif}</p>}
                  <p className="text-[10px] text-muted-foreground/60 mt-1">
                    Depuis le {format(new Date(e.cree_le), 'd MMM yyyy', { locale: fr })}
                  </p>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      <ModalConfirmation
        ouvert={!!suppressionExcluId}
        onFermer={() => setSuppressionExcluId(null)}
        onConfirmer={supprimerExclusion}
        titre="Supprimer cette exclusion ?"
        message="L'établissement pourra à nouveau vous proposer des missions."
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </LayoutApp>
  );
}

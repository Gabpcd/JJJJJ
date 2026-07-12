import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState, IllustrationBouclier } from '@/components/ui/EmptyState';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Ban, Trash2, ShieldAlert, Flame } from 'lucide-react';
import { PoolUrgenceToggle } from '@/components/PoolUrgenceToggle';
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
  usePageTitle('Exclusions');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [exclusions, setExclusions] = useState<any[]>([]);
  const [exclusionsRecues, setExclusionsRecues] = useState<ExclusionRecue[]>([]);
  const [loading, setLoading] = useState(true);
  const [suppressionExcluId, setSuppressionExcluId] = useState<string | null>(null);
  const [onglet, setOnglet] = useState<Onglet>('envoyees');
  const [poolActif, setPoolActif] = useState(false);
  const [poolRayon, setPoolRayon] = useState(30);

  const charger = async () => {
    if (!user) return;

    const [resEnvoyees, resRecues, resProfil] = await Promise.all([
      supabase
        .from('exclusions')
        .select('id, exclu_id, exclu_par, motif, type_exclu_par, cree_le')
        .eq('exclu_par', user.id)
        .order('cree_le', { ascending: false }),
      supabase.rpc('fn_mes_exclusions_recues' as any),
      supabase.from('soignants').select('disponible_urgence, urgence_rayon_km').eq('id', user.id).maybeSingle(),
    ]);

    let list = resEnvoyees.data || [];
    if (list.length > 0) {
      const etabIds = list.map((e: any) => e.exclu_id);
      const etabMap = await fetchEtablissementsSafe(etabIds);
      list = list.map((e: any) => ({ ...e, nom_exclu: etabMap[e.exclu_id]?.nom || e.exclu_id }));
    }
    setExclusions(list);
    setExclusionsRecues((resRecues.data as ExclusionRecue[]) || []);
    if (resProfil.data) {
      setPoolActif(!!(resProfil.data as any).disponible_urgence);
      setPoolRayon((resProfil.data as any).urgence_rayon_km || 30);
    }
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
      <h1 className="text-xl font-bold text-foreground mb-4 flex items-center gap-2">
        <Flame className="h-5 w-5 text-rose" /> Urgences & exclusions
      </h1>

      {/* Pool urgence toggle */}
      <div className="mb-6">
        <PoolUrgenceToggle
          actif={poolActif}
          rayonKm={poolRayon}
          onUpdate={(a, r) => { setPoolActif(a); setPoolRayon(r); }}
          onError={(msg) => afficherNotification({ type: 'erreur', message: msg })}
          onSuccess={(msg) => afficherNotification({ type: 'succes', message: msg })}
        />
      </div>

      <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2">
        <Ban className="h-5 w-5 text-destructive" /> Mes exclusions
      </h2>

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
            <EmptyState illustration={<IllustrationBouclier />} titre="Aucune exclusion" description="Tu n'as bloqué personne." />
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
                  <button aria-label={`Retirer l’exclusion de ${e.nom_exclu}`} onClick={() => setSuppressionExcluId(e.exclu_id)} className="text-destructive hover:text-destructive/80 p-2">
                    <Trash2 className="h-4 w-4" aria-hidden="true" />
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
                Ces établissements ont choisi de ne plus travailler avec toi. Leurs missions ne te sont plus proposées.
              </p>
            </div>
          </div>

          {exclusionsRecues.length === 0 ? (
            <EmptyState illustration={<IllustrationBouclier />} titre="Aucune exclusion reçue" description="Aucun établissement ne t'a exclu." variant="success" />
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
        message="L'établissement pourra à nouveau te proposer des missions."
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </LayoutApp>
  );
}

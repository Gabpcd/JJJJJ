import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide, IllustrationBouclier } from '@/components/EtatVide';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Ban, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function ExclusionsEtablissement() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [exclusions, setExclusions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [suppressionExcluId, setSuppressionExcluId] = useState<string | null>(null);

  const charger = async () => {
    if (!user) return;
    const [{ data }, { data: soignantsData }] = await Promise.all([
      supabase
        .from('exclusions')
        .select('id, exclu_id, exclu_par, motif, type_exclu_par, cree_le')
        .eq('exclu_par', user.id)
        .order('cree_le', { ascending: false }),
      supabase.rpc('fn_mes_soignants_etablissement'),
    ]);

    let list = data || [];
    if (list.length > 0) {
      const soignantMap: Record<string, string> = {};
      if (Array.isArray(soignantsData)) {
        for (const s of soignantsData) {
          soignantMap[s.id] = `${s.prenom} ${s.nom}`;
        }
      }
      list = list.map((e: any) => ({ ...e, nom_exclu: soignantMap[e.exclu_id] || 'Soignant inconnu' }));
    }
    setExclusions(list);
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

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <h1 className="text-xl font-bold text-foreground mb-6 flex items-center gap-2">
        <Ban className="h-5 w-5 text-destructive" /> Exclusions
      </h1>

      {exclusions.length === 0 ? (
        <EtatVide illustration={<IllustrationBouclier />} titre="Aucune exclusion" sousTitre="Vous n'avez bloqué personne." />
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

      <ModalConfirmation
        ouvert={!!suppressionExcluId}
        onFermer={() => setSuppressionExcluId(null)}
        onConfirmer={supprimerExclusion}
        titre="Supprimer cette exclusion ?"
        message="Ce soignant pourra à nouveau postuler à vos missions."
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </LayoutApp>
  );
}

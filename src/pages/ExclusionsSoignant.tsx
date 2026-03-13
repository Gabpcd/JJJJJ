import React, { useState, useEffect } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { Ban, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { fetchEtablissementsSafe } from '@/lib/etablissements';

export default function ExclusionsSoignant() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [exclusions, setExclusions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [suppressionId, setSuppressionId] = useState<string | null>(null);

  const charger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('exclusions')
      .select('*')
      .eq('exclu_par', user.id)
      .order('cree_le', { ascending: false });

    let list = data || [];
    if (list.length > 0) {
      const etabIds = list.map((e: any) => e.exclu_id);
      const etabMap = await fetchEtablissementsSafe(etabIds);
      list = list.map((e: any) => ({ ...e, nom_exclu: etabMap[e.exclu_id]?.nom || e.exclu_id }));
    }
    setExclusions(list);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const supprimerExclusion = async () => {
    if (!suppressionId || !user) return;
    const { error } = await supabase.from('exclusions').delete().eq('id', suppressionId);
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'EXCLUSION_SUPPRIMEE', p_type_ressource: 'exclusion',
        p_id_ressource: suppressionId, p_cle_s3: null,
        p_details: {},
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: 'Exclusion supprimée.' });
      charger();
    }
    setSuppressionId(null);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-6 flex items-center gap-2">
        <Ban className="h-5 w-5 text-destructive" /> Mes exclusions
      </h1>

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
              <button onClick={() => setSuppressionId(e.id)} className="text-destructive hover:text-destructive/80 p-2">
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>
      )}

      <ModalConfirmation
        ouvert={!!suppressionId}
        onFermer={() => setSuppressionId(null)}
        onConfirmer={supprimerExclusion}
        titre="Supprimer cette exclusion ?"
        message="L'établissement pourra à nouveau vous proposer des missions."
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </LayoutApp>
  );
}

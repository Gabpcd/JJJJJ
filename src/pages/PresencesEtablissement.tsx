import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CarteValidation } from '@/components/CarteValidation';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import type { RpcSuccessOrError, RpcValiderPresencesLot } from '@/lib/supabase-rpc-types';
import { ClipboardCheck, CheckCircle, Clock, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { useSearchParams } from 'react-router-dom';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

export default function PresencesEtablissement() {
  usePageTitle('Présences');
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [searchParams, setSearchParams] = useSearchParams();
  const [presences, setPresences] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalLot, setModalLot] = useState(false);
  const tabParam = searchParams.get('tab');
  const [activeTab, setActiveTab] = useState(['a_valider', 'en_cours', 'validees', 'alertes'].includes(tabParam || '') ? tabParam! : 'validees');

  const charger = useCallback(async () => {
    if (!user || !etablissementId) return;
    const [{ data: presData }, { data: soignantsData }] = await Promise.all([
      supabase
        .from('presences')
        .select(`
          id, mission_id, soignant_id,
          pointage_arrivee_le, pointage_depart_le,
          arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
          depart_lat, depart_lng, depart_precision_gps_m,
          distance_etablissement_m, perimetre_gps_valide,
          alerte_teleportation, alertes_fraude,
          valide_par_etablissement, valide_le, motif_litige,
          missions!inner(intitule, service, debut_le, fin_le, duree_heures, etablissement_id)
        `)
        .eq('missions.etablissement_id', etablissementId)
        .not('pointage_arrivee_le', 'is', null)
        .order('pointage_arrivee_le', { ascending: false }),
      supabase.rpc('fn_mes_soignants_etablissement'),
    ]);

    const sgMap: Record<string, any> = {};
    if (Array.isArray(soignantsData)) {
      for (const s of soignantsData) sgMap[s.id] = s;
    }

    if (Object.keys(sgMap).length === 0 && Array.isArray(presData)) {
      const soignantIds = [...new Set(presData.map((p: any) => p.soignant_id).filter(Boolean))];
      if (soignantIds.length > 0) {
        const { data: soignantsDirect } = await supabase
          .from('soignants')
          .select('id, prenom, nom, profession, telephone')
          .in('id', soignantIds);
        if (Array.isArray(soignantsDirect)) {
          for (const s of soignantsDirect) sgMap[s.id] = s;
        }
      }
    }

    setPresences((presData || []).map((p: any) => ({
      ...p,
      soignants: sgMap[p.soignant_id] || null,
    })));
    setLoading(false);
  }, [user, etablissementId]);

  useEffect(() => { charger(); }, [charger]);

  useEffect(() => {
    if (tabParam && ['a_valider', 'en_cours', 'validees', 'alertes'].includes(tabParam) && tabParam !== activeTab) {
      setActiveTab(tabParam);
    }
  }, [tabParam]);

  const aValider = presences.filter(p => !p.valide_par_etablissement && p.pointage_depart_le);
  const validees = presences.filter(p => p.valide_par_etablissement);
  const enCours = presences.filter(p => !p.pointage_depart_le);
  const alertes = presences.filter(p => p.alerte_teleportation || !p.perimetre_gps_valide);

  const presencesSansAlerte = aValider.filter(p =>
    p.perimetre_gps_valide === true && !p.alerte_teleportation
  );

  const validerUne = async (presenceId: string) => {
    const { data, error } = await supabase.rpc('fn_valider_presence', { p_presence_id: presenceId });
    const result = data as unknown as RpcSuccessOrError | null;

    if (error || (result && !result.success)) {
      afficherNotification({ type: 'erreur', message: result?.error || extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_VALIDATION', p_type_ressource: 'presence',
        p_id_ressource: presenceId, p_cle_s3: null,
        p_details: { type: 'validation_individuelle' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: '✅ Présence validée !' });
      charger();
    }
  };

  const contester = async (presenceId: string, motif: string) => {
    const { data, error } = await supabase.rpc('fn_contester_presence', {
      p_presence_id: presenceId,
      p_motif: motif,
    });
    const result = data as unknown as RpcSuccessOrError | null;

    if (error || (result && !result.success)) {
      afficherNotification({ type: 'erreur', message: result?.error || extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_CONTESTATION', p_type_ressource: 'presence',
        p_id_ressource: presenceId, p_cle_s3: null,
        p_details: { motif },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'avertissement', message: 'Contestation enregistrée.' });
      charger();
    }
  };

  const validerEnLot = async () => {
    if (presencesSansAlerte.length === 0) {
      afficherNotification({ type: 'info', message: 'Aucune présence éligible à la validation automatique.' });
      return;
    }

    const ids = presencesSansAlerte.map(p => p.id);

    const { data, error } = await supabase.rpc('fn_valider_presences_lot', { p_ids: ids });

    if (error || (data && !(data as any).success)) {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || extraireMessageErreur(error) });
    } else {
      const nbValidees = (data as any)?.nb_validees ?? ids.length;
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_VALIDATION_LOT', p_type_ressource: 'presence',
        p_id_ressource: user!.id, p_cle_s3: null,
        p_details: { type: 'validation_en_lot', nb_validees: nbValidees, ids_presences: ids },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: `✅ ${nbValidees} présences validées !` });
      charger();
    }
  };

  const ouvrirLitige = async (presenceId: string, missionId: string, soignantId: string, motif: string) => {
    if (!etablissementId || !motif.trim()) return;
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: missionId,
      p_motif: motif.trim(),
    });
    if (error) {
      toast.error('Erreur lors de la création du litige.');
      console.error(error);
      return;
    }
    if (data?.error) { toast.error(data.error); return; }
    toast.success('Litige ouvert avec succès.');
    charger();
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <ClipboardCheck className="h-5 w-5 text-primary" /> Présences à valider
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Vérifiez et validez les pointages de vos soignants</p>
      </div>

      <Tabs
        value={activeTab}
        onValueChange={(value) => {
          setActiveTab(value);
          if (value === 'a_valider') setSearchParams({}, { replace: true });
          else setSearchParams({ tab: value }, { replace: true });
        }}
      >
        <TabsList className="w-full grid grid-cols-4 mb-4">
          <TabsTrigger value="a_valider" className="text-xs">
            À valider ({aValider.length})
          </TabsTrigger>
          <TabsTrigger value="en_cours" className="text-xs">
            En cours ({enCours.length})
          </TabsTrigger>
          <TabsTrigger value="validees" className="text-xs">
            Validées ({validees.length})
          </TabsTrigger>
          <TabsTrigger value="alertes" className="text-xs">
            Alertes ({alertes.length})
          </TabsTrigger>
        </TabsList>

        <TabsContent value="a_valider">
          {aValider.length > 0 && (
            <div className="bg-card border border-border rounded-2xl p-4 mb-4">
              <p className="text-sm font-semibold text-foreground mb-2">{aValider.length} présences à valider</p>
              <button
                onClick={() => setModalLot(true)}
                disabled={presencesSansAlerte.length === 0}
                className="btn-primary text-sm flex items-center gap-2 disabled:opacity-50"
              >
                <CheckCircle className="h-4 w-4" /> Tout valider (sans alerte) · {presencesSansAlerte.length} présences
              </button>
              <p className="text-[11px] text-muted-foreground mt-2">
                Ce bouton valide uniquement les présences sans aucune alerte (géofence OK, pas de téléportation).
              </p>
            </div>
          )}
          {aValider.length > 0 ? (
            <div className="space-y-4">
              {aValider.map(p => (
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} onOuvrirLitige={ouvrirLitige} />
              ))}
            </div>
          ) : (
            <EtatVide icone={CheckCircle} titre="Aucune présence à valider" sousTitre="Les pointages de vos soignants apparaîtront ici." />
          )}
        </TabsContent>

        <TabsContent value="en_cours">
          {enCours.length > 0 ? (
            <div className="space-y-4">
              {enCours.map(p => (
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} onOuvrirLitige={ouvrirLitige} />
              ))}
            </div>
          ) : (
            <EtatVide icone={Clock} titre="Aucune mission en cours" sousTitre="Les soignants actuellement en mission apparaîtront ici." />
          )}
        </TabsContent>

        <TabsContent value="validees">
          {validees.length > 0 ? (
            <div className="space-y-4">
              {validees.map(p => (
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} onOuvrirLitige={ouvrirLitige} />
              ))}
            </div>
          ) : (
            <EtatVide icone={CheckCircle} titre="Aucune présence validée" sousTitre="Les présences validées seront archivées ici." />
          )}
        </TabsContent>

        <TabsContent value="alertes">
          {alertes.length > 0 ? (
            <div className="space-y-4">
              {alertes.map(p => (
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} onOuvrirLitige={ouvrirLitige} />
              ))}
            </div>
          ) : (
            <EtatVide icone={AlertTriangle} titre="Aucune alerte" sousTitre="Les présences avec des alertes de fraude apparaîtront ici." />
          )}
        </TabsContent>
      </Tabs>

      <ModalConfirmation
        ouvert={modalLot}
        onFermer={() => setModalLot(false)}
        onConfirmer={validerEnLot}
        titre={`Valider ${presencesSansAlerte.length} présences ?`}
        message="Seules les présences sans alerte de fraude seront validées."
        labelConfirmer={`Valider ${presencesSansAlerte.length} présences`}
      />
    </LayoutApp>
  );
}

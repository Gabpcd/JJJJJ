import React, { useState, useEffect, useCallback } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CarteValidation } from '@/components/CarteValidation';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { ClipboardCheck, CheckCircle, Clock, AlertTriangle } from 'lucide-react';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';

export default function PresencesEtablissement() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [presences, setPresences] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalLot, setModalLot] = useState(false);

  const charger = useCallback(async () => {
    if (!user) return;
    // We need to get presences for missions belonging to this établissement
    // Since RLS on presences checks soignant_id or ADMIN_ETABLISSEMENT role,
    // we query missions first then presences
    const { data } = await supabase
      .from('presences')
      .select(`
        id, mission_id, soignant_id,
        pointage_arrivee_le, pointage_depart_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        depart_lat, depart_lng, depart_precision_gps_m,
        distance_etablissement_m, perimetre_gps_valide,
        alerte_teleportation, alertes_fraude,
        valide_par_etablissement, valide_le, motif_litige,
        soignants(prenom, nom, telephone, email, profession),
        missions!inner(intitule, service, debut_le, fin_le, duree_heures, etablissement_id)
      `)
      .eq('missions.etablissement_id', user.id)
      .not('pointage_arrivee_le', 'is', null)
      .order('pointage_arrivee_le', { ascending: false });

    setPresences(data || []);
    setLoading(false);
  }, [user]);

  useEffect(() => { charger(); }, [charger]);

  const aValider = presences.filter(p => !p.valide_par_etablissement && p.pointage_depart_le);
  const validees = presences.filter(p => p.valide_par_etablissement);
  const enCours = presences.filter(p => !p.pointage_depart_le);
  const alertes = presences.filter(p => p.alerte_teleportation || !p.perimetre_gps_valide);

  const presencesSansAlerte = aValider.filter(p =>
    p.perimetre_gps_valide === true && !p.alerte_teleportation
  );

  const validerUne = async (presenceId: string) => {
    const { error } = await supabase
      .from('presences')
      .update({ valide_par_etablissement: true, valide_le: new Date().toISOString(), modifie_le: new Date().toISOString() } as any)
      .eq('id', presenceId);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit', {
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
    const { error } = await supabase
      .from('presences')
      .update({ motif_litige: motif, modifie_le: new Date().toISOString() } as any)
      .eq('id', presenceId);

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      await supabase.rpc('fn_ecrire_audit', {
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

    const { error } = await supabase
      .from('presences')
      .update({ valide_par_etablissement: true, valide_le: new Date().toISOString(), modifie_le: new Date().toISOString() } as any)
      .in('id', ids);

    if (!error) {
      await supabase.rpc('fn_ecrire_audit', {
        p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT',
        p_action: 'PRESENCE_VALIDATION_LOT', p_type_ressource: 'presence',
        p_id_ressource: user!.id, p_cle_s3: null,
        p_details: { type: 'validation_en_lot', nb_validees: ids.length, ids_presences: ids },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
      afficherNotification({ type: 'succes', message: `✅ ${ids.length} présences validées !` });
      charger();
    } else {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    }
  };

  if (loading) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <ClipboardCheck className="h-5 w-5 text-primary" /> Présences à valider
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Vérifiez et validez les pointages de vos soignants</p>
      </div>

      <Tabs defaultValue="a_valider">
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
          {/* Bulk validation */}
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
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} />
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
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} />
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
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} />
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
                <CarteValidation key={p.id} presence={p} onValider={validerUne} onContester={contester} />
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

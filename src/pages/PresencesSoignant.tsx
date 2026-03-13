import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CartePointage } from '@/components/CartePointage';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { PanneauContestation } from '@/components/PanneauContestation';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { genererIdTerminal } from '@/lib/terminal';
import { stockerPointageHorsLigne } from '@/lib/horsLigne';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CalendarDays, Clock, CheckCircle } from 'lucide-react';

export default function PresencesSoignant() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [missions, setMissions] = useState<any[]>([]);
  const [presencesValidees, setPresencesValidees] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [contrats, setContrats] = useState<Record<string, any>>({});

  const charger = useCallback(async () => {
    if (!user) return;
    const aujourdhui = new Date();
    aujourdhui.setHours(0, 0, 0, 0);
    const demain = new Date(aujourdhui);
    demain.setDate(demain.getDate() + 1);

    const { data } = await supabase
      .from('missions')
      .select(`
        id, intitule, service, debut_le, fin_le, duree_heures, statut,
        etablissements(nom, adresse_ville, adresse_lat, adresse_lng),
        presences(id, pointage_arrivee_le, pointage_depart_le,
          perimetre_gps_valide, alerte_teleportation, distance_etablissement_m,
          arrivee_precision_gps_m, depart_precision_gps_m, valide_par_etablissement, valide_le)
      `)
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
      .gte('debut_le', aujourdhui.toISOString())
      .lt('debut_le', demain.toISOString())
      .order('debut_le', { ascending: true });

    const missionsList = data || [];
    setMissions(missionsList);

    // Check contract status for each mission
    if (missionsList.length > 0) {
      const missionIds = missionsList.map((m: any) => m.id);
      const { data: contratsData } = await supabase
        .from('contrats_mission')
        .select('id, mission_id, statut')
        .in('mission_id', missionIds);
      const map: Record<string, any> = {};
      (contratsData || []).forEach((c: any) => { map[c.mission_id] = c; });
      setContrats(map);
    }

    // Load recently validated presences (last 7 days) for contestation
    const il7jours = new Date();
    il7jours.setDate(il7jours.getDate() - 7);
    const { data: validees } = await supabase
      .from('presences')
      .select(`
        id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
        valide_par_etablissement, valide_le,
        missions!inner(id, intitule, etablissement_id, debut_le, fin_le,
          etablissements(nom))
      `)
      .eq('soignant_id', user!.id)
      .eq('valide_par_etablissement', true)
      .gte('valide_le', il7jours.toISOString())
      .order('valide_le', { ascending: false });

    setPresencesValidees(validees || []);

    setLoading(false);
  }, [user]);

  useEffect(() => { charger(); }, [charger]);

  const obtenirPosition = async (): Promise<GeolocationPosition> => {
    return new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true, timeout: 10000, maximumAge: 0,
      });
    });
  };

  const pointerArrivee = async (missionId: string) => {
    if (!user) return;
    if (!navigator.onLine) {
      stockerPointageHorsLigne(missionId, 'arrivee');
      afficherNotification({ type: 'info', message: '📡 Mode hors-ligne : pointage stocké localement.', duree: 8000 });
      return;
    }

    let position: GeolocationPosition;
    try {
      position = await obtenirPosition();
    } catch {
      afficherNotification({ type: 'erreur', message: 'Impossible d\'obtenir votre position. Vérifiez que la géolocalisation est activée.' });
      return;
    }

    const idTerminal = genererIdTerminal();
    const modeleTerminal = navigator.userAgent.substring(0, 200);

    const { data, error } = await supabase
      .from('presences')
      .insert({
        mission_id: missionId,
        soignant_id: user.id,
        pointage_arrivee_le: new Date().toISOString(),
        arrivee_lat: position.coords.latitude,
        arrivee_lng: position.coords.longitude,
        arrivee_precision_gps_m: position.coords.accuracy,
        arrivee_id_terminal: idTerminal,
        arrivee_modele_terminal: modeleTerminal,
      } as any)
      .select()
      .single();

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
      return;
    }

    if ('vibrate' in navigator) navigator.vibrate(200);

    // Re-read trigger-calculated columns
    const { data: pc } = await supabase
      .from('presences')
      .select('perimetre_gps_valide, alerte_teleportation, distance_etablissement_m, alertes_fraude, arrivee_precision_gps_m')
      .eq('id', (data as any).id)
      .single();

    if (pc?.perimetre_gps_valide) {
      afficherNotification({ type: 'succes', message: `✅ Arrivée pointée ! Vous êtes à ${Math.round(pc.distance_etablissement_m)}m de l'établissement.` });
    } else {
      afficherNotification({ type: 'avertissement', message: `⚠️ Arrivée pointée, mais vous êtes à ${Math.round(pc?.distance_etablissement_m || 0)}m (périmètre : 500m).` });
    }

    if (pc?.alerte_teleportation) {
      afficherNotification({ type: 'erreur', message: '🚨 Alerte : un déplacement inhabituellement rapide a été détecté.', duree: 10000 });
    }

    // Mission → EN_COURS (handled by trigger on presence insert)

    // Audit
    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT', p_action: 'PRESENCE_POINTAGE_ARRIVEE',
      p_type_ressource: 'presence', p_id_ressource: (data as any).id, p_cle_s3: null,
      p_details: { mission_id: missionId, lat: position.coords.latitude, lng: position.coords.longitude, precision_m: position.coords.accuracy, perimetre_ok: pc?.perimetre_gps_valide, distance_m: pc?.distance_etablissement_m },
      p_ip: null, p_navigateur: navigator.userAgent,
    });

    charger();
  };

  const pointerDepart = async (presenceId: string, missionId: string) => {
    if (!user) return;
    if (!navigator.onLine) {
      stockerPointageHorsLigne(missionId, 'depart', presenceId);
      afficherNotification({ type: 'info', message: '📡 Mode hors-ligne : pointage stocké localement.', duree: 8000 });
      return;
    }

    let position: GeolocationPosition;
    try {
      position = await obtenirPosition();
    } catch {
      afficherNotification({ type: 'erreur', message: 'Position GPS indisponible.' });
      return;
    }

    const { data: rpcResult, error } = await supabase.rpc('fn_pointer_depart' as any, {
      p_presence_id: presenceId,
      p_lat: position.coords.latitude,
      p_lng: position.coords.longitude,
      p_precision: position.coords.accuracy,
      p_terminal_id: genererIdTerminal(),
      p_modele: navigator.userAgent.slice(0, 100),
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
      return;
    }
    if (rpcResult?.error) {
      afficherNotification({ type: 'erreur', message: rpcResult.error });
      return;
    }

    if ('vibrate' in navigator) navigator.vibrate([200, 100, 200]);

    // Email MISSION_TERMINEE au soignant
    const missionData = missions.find((m: any) => m.id === missionId);
    if (missionData) {
      supabase.functions.invoke('send-email', {
        body: {
          type: 'MISSION_TERMINEE',
          data: {
            prenom: user.prenom || '',
            mission: missionData.intitule || missionData.missions?.intitule || 'Mission',
            etablissement: missionData.etablissements?.nom || missionData.missions?.etablissements?.nom || '',
            heures: missionData.duree_heures || missionData.missions?.duree_heures || 0,
            net: missionData.net_a_payer || missionData.missions?.net_a_payer || 0,
          },
          destinataire_id: user.id,
        },
      }).catch(() => {});
    }

    afficherNotification({ type: 'succes', message: '🏁 Départ pointé ! Mission terminée.' });
    charger();
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <BandeauHorsLigne />
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Clock className="h-5 w-5 text-primary" /> Mes présences
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Pointez vos arrivées et départs pour chaque mission</p>
      </div>

      {missions.length > 0 ? (
        <div className="space-y-4">
          {missions.map((m: any) => {
            const presence = m.presences?.[0] || null;
            const contrat = contrats[m.id];
            const contratBloque = contrat && contrat.statut !== 'SIGNE_COMPLET';
            const pasDeContrat = !contrat;

            if ((contratBloque || pasDeContrat) && !presence?.pointage_arrivee_le) {
              return (
                <div key={m.id} className="card-base">
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <p className="font-semibold text-foreground">{m.intitule}</p>
                      <p className="text-xs text-muted-foreground">{(m as any).etablissements?.nom}</p>
                    </div>
                  </div>
                  <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 text-center">
                    <p className="text-warning font-bold text-sm">⚠️ Contrat non signé</p>
                    <p className="text-warning/80 text-xs mt-1">
                      Le contrat de mission doit être signé par les deux parties avant de pouvoir pointer.
                    </p>
                    {contrat && (
                      <button onClick={() => navigate(`/contrat/${contrat.id}`)} className="btn-primary text-xs mt-3">
                        Signer le contrat →
                      </button>
                    )}
                  </div>
                </div>
              );
            }

            return (
              <CartePointage
                key={m.id}
                mission={m}
                presence={presence}
                onPointerArrivee={() => pointerArrivee(m.id)}
                onPointerDepart={() => presence ? pointerDepart(presence.id, m.id) : Promise.resolve()}
              />
            );
          })}
        </div>
      ) : (
        <EtatVide
          icone={CalendarDays}
          titre="Aucune mission aujourd'hui"
          sousTitre="Vos missions assignées apparaîtront ici le jour J pour le pointage."
        />
      )}

      {/* Presences validated recently — contestation possible */}
      {presencesValidees.length > 0 && (
        <div className="mt-8">
          <h2 className="text-base font-bold text-foreground flex items-center gap-2 mb-4">
            <CheckCircle className="h-4 w-4 text-success" /> Présences validées récemment
          </h2>
          <div className="space-y-3">
            {presencesValidees.map((p: any) => {
              const m = p.missions;
              return (
                <div key={p.id} className="rounded-2xl border border-border p-4">
                  <div className="flex items-start justify-between mb-1">
                    <div>
                      <p className="font-semibold text-sm text-foreground">{m?.intitule}</p>
                      <p className="text-xs text-muted-foreground">{m?.etablissements?.nom}</p>
                    </div>
                    <span className="text-[11px] bg-success/10 text-success px-2 py-0.5 rounded-full font-medium">
                      Validée
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground mb-2">
                    {p.valide_le && format(new Date(p.valide_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                  </p>
                  <PanneauContestation
                    presenceId={p.id}
                    missionId={p.mission_id}
                    etablissementId={m?.etablissement_id}
                    soignantId={p.soignant_id}
                    presenceValideeLe={p.valide_le}
                    role="SOIGNANT"
                    onUpdate={charger}
                  />
                </div>
              );
            })}
          </div>
        </div>
      )}
    </LayoutApp>
  );
}

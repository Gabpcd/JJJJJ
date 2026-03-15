import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CartePointage } from '@/components/CartePointage';
import { SaisieCodePointage } from '@/components/SaisieCodePointage';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { PanneauContestation } from '@/components/PanneauContestation';
import { EtatVide } from '@/components/EtatVide';
import { ConsentementGPS } from '@/components/ConsentementGPS';
import { BandeauSansGPS } from '@/components/BandeauSansGPS';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { genererIdTerminal } from '@/lib/terminal';
import { stockerPointageHorsLigne } from '@/lib/horsLigne';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CalendarDays, Clock, CheckCircle } from 'lucide-react';

export default function PresencesSoignant() {
  usePageTitle('Présences');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const [missions, setMissions] = useState<any[]>([]);
  const [presencesValidees, setPresencesValidees] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [contrats, setContrats] = useState<Record<string, any>>({});

  // GPS consent state
  const [consentementGPS, setConsentementGPS] = useState<boolean | null>(null);
  const [showConsentementGPS, setShowConsentementGPS] = useState(false);
  const [consentementCharge, setConsentementCharge] = useState(false);

  // Load GPS consent on mount
  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('consentement_gps').eq('id', user.id).single().then(({ data }) => {
      setConsentementGPS(data?.consentement_gps ?? null);
      setConsentementCharge(true);
    });
  }, [user]);

  const handleAccepterGPS = async () => {
    if (!user) return;
    // Use dedicated RPC to update only GPS consent without touching other fields
    await supabase.rpc('fn_consentir_gps' as any, {
      p_accepte: true,
    });
    setConsentementGPS(true);
    setShowConsentementGPS(false);

    // Audit GPS consent
    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
      p_action: 'RGPD_CONSENTEMENT_DONNE',
      p_type_ressource: 'soignant', p_id_ressource: user.id,
      p_cle_s3: null, p_details: { type: 'gps', consentement: true },
      p_ip: null, p_navigateur: navigator.userAgent,
    });

    afficherNotification({ type: 'succes', message: 'Consentement GPS enregistré.' });
  };

  const handleRefuserGPS = async () => {
    if (!user) return;
    await supabase.rpc('fn_consentir_gps' as any, {
      p_accepte: false,
    });
    setConsentementGPS(false);
    setShowConsentementGPS(false);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
      p_action: 'RGPD_CONSENTEMENT_DONNE',
      p_type_ressource: 'soignant', p_id_ressource: user.id,
      p_cle_s3: null, p_details: { type: 'gps', consentement: false },
      p_ip: null, p_navigateur: navigator.userAgent,
    });

    afficherNotification({ type: 'info', message: 'Pointage sans GPS activé. Vérification manuelle requise.' });
  };

  const charger = useCallback(async () => {
    if (!user) return;
    const aujourdhui = new Date();
    aujourdhui.setHours(0, 0, 0, 0);
    const demain = new Date(aujourdhui);
    demain.setDate(demain.getDate() + 1);

    const { data } = await supabase
      .from('missions')
      .select(`
        id, intitule, service, debut_le, fin_le, duree_heures, statut, etablissement_id,
        presences(id, pointage_arrivee_le, pointage_depart_le,
          perimetre_gps_valide, alerte_teleportation, distance_etablissement_m,
          arrivee_precision_gps_m, depart_precision_gps_m, valide_par_etablissement, valide_le)
      `)
      .eq('soignant_assigne_id', user.id)
      .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
      .gte('debut_le', aujourdhui.toISOString())
      .lt('debut_le', demain.toISOString())
      .order('debut_le', { ascending: true });

    let missionsList = data || [];
    if (missionsList.length > 0) {
      const etabMap = await fetchEtablissementsSafe(missionsList.map((m: any) => m.etablissement_id));
      missionsList = missionsList.map((m: any) => ({ ...m, etablissements: etabMap[m.etablissement_id] || null }));
    }
    setMissions(missionsList);

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

    const il7jours = new Date();
    il7jours.setDate(il7jours.getDate() - 7);
    const { data: validees } = await supabase
      .from('presences')
      .select(`
        id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
        valide_par_etablissement, valide_le,
        missions!inner(id, intitule, etablissement_id, debut_le, fin_le)
      `)
      .eq('soignant_id', user!.id)
      .eq('valide_par_etablissement', true)
      .gte('valide_le', il7jours.toISOString())
      .order('valide_le', { ascending: false });

    let presencesList = validees || [];
    if (presencesList.length > 0) {
      const etabIds = presencesList.map((p: any) => p.missions?.etablissement_id).filter(Boolean);
      const etabMap = await fetchEtablissementsSafe(etabIds);
      presencesList = presencesList.map((p: any) => ({
        ...p,
        missions: { ...p.missions, etablissements: etabMap[p.missions?.etablissement_id] || null },
      }));
    }
    setPresencesValidees(presencesList);
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

    // Check GPS consent before first geolocation
    if (consentementGPS === null || consentementGPS === undefined) {
      setShowConsentementGPS(true);
      return;
    }

    if (!navigator.onLine) {
      stockerPointageHorsLigne(missionId, 'arrivee');
      afficherNotification({ type: 'info', message: '📡 Mode hors-ligne : pointage stocké localement.', duree: 8000 });
      return;
    }

    let position: GeolocationPosition | null = null;

    if (consentementGPS) {
      try {
        position = await obtenirPosition();
      } catch {
        afficherNotification({ type: 'erreur', message: 'Impossible d\'obtenir votre position. Vérifiez que la géolocalisation est activée.' });
        return;
      }
    }

    const idTerminal = genererIdTerminal();
    const modeleTerminal = navigator.userAgent.substring(0, 100);

    const { data: rpcResult, error } = await supabase.rpc('fn_pointer_arrivee' as any, {
      p_mission_id: missionId,
      p_lat: position?.coords.latitude ?? 0,
      p_lng: position?.coords.longitude ?? 0,
      p_precision: position?.coords.accuracy ?? 0,
      p_terminal_id: idTerminal,
      p_modele: modeleTerminal,
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
      return;
    }
    if (rpcResult?.error) {
      afficherNotification({ type: 'erreur', message: rpcResult.error });
      return;
    }

    if ('vibrate' in navigator) navigator.vibrate(200);

    const presenceId = rpcResult?.presence_id;
    const perimetreOk = rpcResult?.perimetre_gps_valide;
    const distanceM = rpcResult?.distance_etablissement_m;
    const alerteTeleportation = rpcResult?.alerte_teleportation;

    if (!consentementGPS) {
      afficherNotification({ type: 'avertissement', message: '⚠️ Arrivée pointée sans GPS. Vérification manuelle requise.' });
    } else if (perimetreOk) {
      afficherNotification({ type: 'succes', message: `✅ Arrivée pointée ! Vous êtes à ${Math.round(distanceM || 0)}m de l'établissement.` });
    } else {
      afficherNotification({ type: 'avertissement', message: `⚠️ Arrivée pointée, mais vous êtes à ${Math.round(distanceM || 0)}m (périmètre : 500m).` });
    }

    if (alerteTeleportation) {
      afficherNotification({ type: 'erreur', message: '🚨 Alerte : un déplacement inhabituellement rapide a été détecté.', duree: 10000 });
    }

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT', p_action: 'PRESENCE_POINTAGE_ARRIVEE',
      p_type_ressource: 'presence', p_id_ressource: presenceId, p_cle_s3: null,
      p_details: { mission_id: missionId, lat: position?.coords.latitude, lng: position?.coords.longitude, precision_m: position?.coords.accuracy, perimetre_ok: perimetreOk, distance_m: distanceM, gps_consent: consentementGPS },
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

    let position: GeolocationPosition | null = null;

    if (consentementGPS) {
      try {
        position = await obtenirPosition();
      } catch {
        afficherNotification({ type: 'erreur', message: 'Position GPS indisponible.' });
        return;
      }
    }

    const { data: rpcResult, error } = await supabase.rpc('fn_pointer_depart' as any, {
      p_presence_id: presenceId,
      p_lat: position?.coords.latitude ?? 0,
      p_lng: position?.coords.longitude ?? 0,
      p_precision: position?.coords.accuracy ?? 0,
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

    const missionData = missions.find((m: any) => m.id === missionId);
    if (missionData) {
      supabase.functions.invoke('send-email', {
        body: {
          type: 'MISSION_TERMINEE',
          data: {
            prenom: user.prenom || '',
            mission: missionData.intitule || 'Mission',
            etablissement: missionData.etablissements?.nom || '',
            heures: missionData.duree_heures || 0,
            net: missionData.net_a_payer || 0,
          },
          destinataire_id: user.id,
        },
      }).catch(() => {});
    }

    afficherNotification({ type: 'succes', message: '🏁 Départ pointé ! Mission terminée.' });
    charger();
  };

  if (loading || !consentementCharge) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  // Show GPS consent screen if first time
  if (showConsentementGPS) {
    return <ConsentementGPS onAccepter={handleAccepterGPS} onRefuser={handleRefuserGPS} />;
  }

  return (
    <LayoutApp role="SOIGNANT">
      <BandeauHorsLigne />

      {consentementGPS === false && <BandeauSansGPS />}

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
                onRecharger={charger}
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

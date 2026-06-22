import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { getCurrentPosition as obtenirGeoloc, JoleneGeolocError } from '@/lib/geoloc';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { CartePointage } from '@/components/CartePointage';
import { SaisieCodePointage } from '@/components/SaisieCodePointage';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { PanneauContestation } from '@/components/PanneauContestation';
import { EmptyState } from '@/components/ui/EmptyState';
import { BadgeStatut } from '@/components/BadgeStatut';
import { ConsentementGPS } from '@/components/ConsentementGPS';
import { BandeauSansGPS } from '@/components/BandeauSansGPS';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { genererIdTerminal } from '@/lib/terminal';
import { stockerPointageHorsLigne } from '@/lib/horsLigne';
import { extraireMessageErreur } from '@/lib/erreurs';
import { handleErrorSilent } from '@/lib/handleError';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { CalendarDays, Clock, CheckCircle, History, AlertTriangle, MapPin, Hash, Eye, Activity } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Button } from '@/components/ui/button';

export default function PresencesSoignant() {
  usePageTitle('Présences');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // GPS consent state
  const [consentementGPS, setConsentementGPS] = useState<boolean | null>(null);
  const [showConsentementGPS, setShowConsentementGPS] = useState(false);
  const [consentementCharge, setConsentementCharge] = useState(false);

  // Load GPS consent on mount
  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('consentement_gps').eq('id', user.id).maybeSingle().then(({ data }) => {
      setConsentementGPS(data?.consentement_gps ?? null);
      setConsentementCharge(true);
    }).then(undefined, (err) => handleErrorSilent(err, 'PresencesSoignant.consentementGPS'));
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

  const { data: presencesData, isLoading: loading } = useQuery({
    queryKey: ['presences-soignant', user?.id],
    queryFn: async () => {
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
            arrivee_precision_gps_m, depart_precision_gps_m, valide_par_etablissement, valide_le,
            methode_pointage_arrivee, methode_pointage_depart)
        `)
        .eq('soignant_assigne_id', user!.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .gte('debut_le', aujourdhui.toISOString())
        .lt('debut_le', demain.toISOString())
        .order('debut_le', { ascending: true });

      let missionsList = data || [];
      if (missionsList.length > 0) {
        const etabMap = await fetchEtablissementsSafe(missionsList.map((m: any) => m.etablissement_id));
        missionsList = missionsList.map((m: any) => ({ ...m, etablissements: etabMap[m.etablissement_id] || null }));
      }

      // Missions à venir (ASSIGNEE, après aujourd'hui)
      const { data: aVenirData } = await supabase
        .from('missions')
        .select('id, intitule, service, debut_le, fin_le, duree_heures, statut, etablissement_id')
        .eq('soignant_assigne_id', user!.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS'])
        .gte('debut_le', demain.toISOString())
        .order('debut_le', { ascending: true })
        .limit(20);

      let aVenirList = aVenirData || [];
      if (aVenirList.length > 0) {
        const etabMapAV = await fetchEtablissementsSafe(aVenirList.map((m: any) => m.etablissement_id));
        aVenirList = aVenirList.map((m: any) => ({ ...m, etablissements: etabMapAV[m.etablissement_id] || null }));
      }

      // Missions EN_COURS avec arrivée pointée mais pas de départ
      const { data: enCoursData } = await supabase
        .from('missions')
        .select(`
          id, intitule, service, debut_le, fin_le, duree_heures, statut, etablissement_id,
          presences(id, pointage_arrivee_le, pointage_depart_le,
            perimetre_gps_valide, alerte_teleportation, distance_etablissement_m,
            arrivee_precision_gps_m, depart_precision_gps_m, valide_par_etablissement, valide_le,
            methode_pointage_arrivee, methode_pointage_depart)
        `)
        .eq('soignant_assigne_id', user!.id)
        .eq('statut', 'EN_COURS')
        .order('debut_le', { ascending: false });

      let enCoursList = (enCoursData || []).filter((m: any) => {
        const p = m.presences?.[0];
        return p?.pointage_arrivee_le && !p?.pointage_depart_le;
      });
      if (enCoursList.length > 0) {
        const etabMapEC = await fetchEtablissementsSafe(enCoursList.map((m: any) => m.etablissement_id));
        enCoursList = enCoursList.map((m: any) => ({ ...m, etablissements: etabMapEC[m.etablissement_id] || null }));
      }

      let contratsMap: Record<string, any> = {};
      if (missionsList.length > 0) {
        const missionIds = missionsList.map((m: any) => m.id);
        const { data: contratsData } = await supabase
          .from('contrats_mission')
          .select('id, mission_id, statut')
          .in('mission_id', missionIds);
        (contratsData || []).forEach((c: any) => { contratsMap[c.mission_id] = c; });
      }

      const il7jours = new Date();
      il7jours.setDate(il7jours.getDate() - 7);
      const { data: validees } = await supabase
        .from('presences')
        .select(`
          id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
          valide_par_etablissement, valide_le,
          methode_pointage_arrivee, methode_pointage_depart,
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

      // Load full historique — show all presences regardless of mission status
      const { data: allPresences } = await supabase
        .from('presences')
        .select(`
          id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
          valide_par_etablissement, valide_le,
          methode_pointage_arrivee, methode_pointage_depart,
          missions(id, intitule, etablissement_id, debut_le, fin_le, statut)
        `)
        .eq('soignant_id', user!.id)
        .order('cree_le', { ascending: false })
        .limit(100);

      let allList = allPresences || [];
      if (allList.length > 0) {
        const etabIds2 = allList.map((p: any) => p.missions?.etablissement_id).filter(Boolean);
        const etabMap2 = await fetchEtablissementsSafe(etabIds2);
        allList = allList.map((p: any) => ({
          ...p,
          missions: { ...p.missions, etablissements: etabMap2[p.missions?.etablissement_id] || null },
        }));
      }

      return {
        missions: missionsList,
        missionsAVenir: aVenirList,
        missionsEnCours: enCoursList,
        contrats: contratsMap,
        presencesValidees: presencesList,
        historiquePresences: allList,
      };
    },
    staleTime: 60_000,
    enabled: !!user,
  });

  const missions = useMemo(() => presencesData?.missions ?? [], [presencesData]);
  const missionsAVenir = useMemo(() => presencesData?.missionsAVenir ?? [], [presencesData]);
  const missionsEnCours = useMemo(() => presencesData?.missionsEnCours ?? [], [presencesData]);
  const contrats = useMemo(() => presencesData?.contrats ?? {}, [presencesData]);
  const presencesValidees = useMemo(() => presencesData?.presencesValidees ?? [], [presencesData]);
  const historiquePresences = useMemo(() => presencesData?.historiquePresences ?? [], [presencesData]);

  const charger = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['presences-soignant'] });
  }, [queryClient]);

  // Wrapper unifié Capacitor native / Web (Sprint 4 PR 5)
  const obtenirPosition = async (): Promise<{ coords: { latitude: number; longitude: number; accuracy: number } }> => {
    try {
      const result = await obtenirGeoloc({ enableHighAccuracy: true, timeout: 10000 });
      return { coords: { latitude: result.coords.latitude, longitude: result.coords.longitude, accuracy: result.coords.accuracy } };
    } catch (err) {
      if (err instanceof JoleneGeolocError) throw new Error(err.message);
      throw err;
    }
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

    let position: { coords: { latitude: number; longitude: number; accuracy: number } } | null = null;

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

    let position: { coords: { latitude: number; longitude: number; accuracy: number } } | null = null;

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

    const missionData = missions.find((m: any) => m.id === missionId) as any;
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
      }).then(undefined, () => { afficherNotification({ type: 'erreur', message: 'Erreur lors de l\'envoi de l\'email de confirmation.' }); });
    }

    afficherNotification({ type: 'succes', message: '🏁 Départ pointé ! Mission terminée.' });
    charger();
  };

  if (loading || !consentementCharge) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  // Show GPS consent screen if first time
  if (showConsentementGPS) {
    return <ConsentementGPS onAccepter={handleAccepterGPS} onRefuser={handleRefuserGPS} />;
  }

  const getMethodeLabel = (m: string | null) => {
    if (!m) return '—';
    if (m === 'GPS') return '📍 GPS';
    if (m === 'CODE') return '🔢 Code';
    if (m === 'QR') return '🔢 Code';
    return m;
  };

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

      <Tabs defaultValue="avenir">
        <TabsList className="w-full max-w-lg mb-4">
          <TabsTrigger value="avenir" className="flex-1 gap-1.5"><CalendarDays className="h-4 w-4" />À venir{missionsAVenir.length > 0 && <BadgeY2K variant="info" size="sm" className="ml-1 h-5 min-w-[20px] justify-center px-1" aria-label={`${missionsAVenir.length} mission${missionsAVenir.length > 1 ? 's' : ''} à venir`}>{missionsAVenir.length}</BadgeY2K>}</TabsTrigger>
          <TabsTrigger value="encours" className="flex-1 gap-1.5"><Activity className="h-4 w-4" />En cours</TabsTrigger>
          <TabsTrigger value="aujourdhui" className="flex-1 gap-1.5"><Clock className="h-4 w-4" />Aujourd'hui</TabsTrigger>
          <TabsTrigger value="historique" className="flex-1 gap-1.5"><History className="h-4 w-4" />Historique</TabsTrigger>
        </TabsList>

        <TabsContent value="avenir">
          {missionsAVenir.length > 0 ? (
            <div className="space-y-3">
              {missionsAVenir.map((m: any) => (
                <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3">
                  <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                    <span className="text-[10px] font-semibold text-primary uppercase">{format(new Date(m.debut_le), 'EEE', { locale: fr })}</span>
                    <span className="text-lg font-bold text-primary leading-tight">{format(new Date(m.debut_le), 'd')}</span>
                    <span className="text-[10px] text-primary">{format(new Date(m.debut_le), 'MMM', { locale: fr })}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <BadgeStatut statut={m.statut} />
                    <h3 className="font-semibold text-sm text-foreground truncate mt-1">{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      🏥 {m.etablissements?.nom}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                      {m.duree_heures ? ` (${m.duree_heures}h)` : ''}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState
              icone={<CalendarDays />}
              mascotte="thinking"
              titre="Aucune mission à venir"
              description="Vos prochaines missions assignées apparaîtront ici."
              cta={{ label: 'Chercher des missions', onClick: () => navigate('/soignant/missions') }}
            />
          )}
        </TabsContent>

        <TabsContent value="encours">
          {missionsEnCours.length > 0 ? (
            <div className="space-y-4">
              {missionsEnCours.map((m: any) => {
                const presence = m.presences?.[0] || null;
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
            <EmptyState
              icone={<Activity />}
              mascotte="empty"
              titre="Aucune mission en cours"
              description="Les missions avec une arrivée pointée apparaîtront ici."
              cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }}
            />
          )}
        </TabsContent>

        <TabsContent value="aujourdhui">
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
            <EmptyState
              icone={<CalendarDays />}
              mascotte="empty"
              titre="Aucune mission aujourd'hui"
              description="Vos missions assignées apparaîtront ici le jour J pour le pointage."
              cta={{ label: 'Voir mon planning', onClick: () => navigate('/soignant/planning') }}
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
        </TabsContent>

        <TabsContent value="historique">
          {historiquePresences.length > 0 ? (
            <div className="space-y-3">
              {historiquePresences.map((p: any) => {
                const m = p.missions;
                const arrivee = p.pointage_arrivee_le ? new Date(p.pointage_arrivee_le) : null;
                const depart = p.pointage_depart_le ? new Date(p.pointage_depart_le) : null;
                const heuresTravaillees = arrivee && depart ? ((depart.getTime() - arrivee.getTime()) / 3600000).toFixed(1) : null;

                return (
                  <div key={p.id} className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate(`/soignant/presences/mission/${p.mission_id}`)}>
                    <div className="flex items-start justify-between mb-2">
                      <div>
                        <p className="font-semibold text-sm text-foreground">{m?.intitule}</p>
                        <p className="text-xs text-muted-foreground">🏥 {m?.etablissements?.nom}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          📅 {m?.debut_le && format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <button className="flex items-center gap-1 text-xs text-primary hover:underline" onClick={e => { e.stopPropagation(); navigate(`/soignant/presences/mission/${p.mission_id}`); }}>
                          <Eye className="h-3.5 w-3.5" /> Détail
                        </button>
                        {p.valide_par_etablissement ? (
                          <BadgeY2K variant="success" size="sm">✅ Validée</BadgeY2K>
                        ) : (
                          <BadgeY2K variant="warning" size="sm">⏳ Non validée</BadgeY2K>
                        )}
                      </div>
                    </div>

                    <div className="grid grid-cols-3 gap-2 text-xs text-muted-foreground bg-muted/30 rounded-lg p-2">
                      <div>
                        <span className="font-medium text-foreground">Arrivée :</span>{' '}
                        {arrivee ? format(arrivee, "HH'h'mm", { locale: fr }) : '—'}
                        <span className="ml-1 text-[10px]">{getMethodeLabel(p.methode_pointage_arrivee)}</span>
                      </div>
                      <div>
                        <span className="font-medium text-foreground">Départ :</span>{' '}
                        {depart ? format(depart, "HH'h'mm", { locale: fr }) : '—'}
                        <span className="ml-1 text-[10px]">{getMethodeLabel(p.methode_pointage_depart)}</span>
                      </div>
                      <div>
                        <span className="font-medium text-foreground">Heures :</span>{' '}
                        {heuresTravaillees ? `${heuresTravaillees}h` : '—'}
                      </div>
                      {(p.code_arrivee || p.code_depart) && (
                        <div className="col-span-2">
                          <Hash className="h-3 w-3 inline" /> Code : {p.code_arrivee || p.code_depart || '—'}
                        </div>
                      )}
                    </div>

                    {!p.valide_par_etablissement && (
                      <div className="mt-2">
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
                    )}
                  </div>
                );
              })}
            </div>
          ) : (
            <EmptyState icone={<History />} mascotte="empty" titre="Aucune présence enregistrée" description="Votre historique de pointages apparaîtra ici." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
          )}
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { getCurrentPosition as obtenirGeoloc, JoleneGeolocError } from '@/lib/geoloc';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BlocPointageMission } from '@/components/pointage/BlocPointageMission';
import { SaisieCodePointage } from '@/components/SaisieCodePointage';
import { BandeauHorsLigne } from '@/components/BandeauHorsLigne';
import { PanneauContestation } from '@/components/PanneauContestation';
import { EmptyState } from '@/components/ui/EmptyState';
import { BadgeStatut } from '@/components/BadgeStatut';
import { ConsentementGPS } from '@/components/ConsentementGPS';
import { SheetNotationRapide } from '@/components/NotationRapide';
import { BandeauSansGPS } from '@/components/BandeauSansGPS';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { genererIdTerminal } from '@/lib/terminal';
import { stockerPointageHorsLigne } from '@/lib/horsLigne';
import { extraireMessageErreur } from '@/lib/erreurs';
import { handleErrorSilent } from '@/lib/handleError';
import {
  ajouterRepliMissionPonctuelle,
  creneauChevauchePeriode,
  creneauxPrevisionnels,
  choisirContratPointage,
  filtrerMissionsEnCours,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { ajouterJoursCivilsParis, debutJourParis, formatParis } from '@/lib/date-heure-paris';
import { CalendarDays, Clock, CheckCircle, History, AlertTriangle, MapPin, Hash, Eye, Activity } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Button } from '@/components/ui/button';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import { construireHistoriqueEffectifsSansPresence } from '@/lib/presencesSoignantUi';

export default function PresencesSoignant() {
  usePageTitle('Présences');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // GPS consent state
  const [consentementGPS, setConsentementGPS] = useState<boolean | null>(null);
  const [showConsentementGPS, setShowConsentementGPS] = useState(false);
  // F4 (Lot 7b) : mission à noter juste après le check-out (null = sheet fermée).
  const [notationMissionId, setNotationMissionId] = useState<string | null>(null);
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

    afficherNotification({ type: 'info', message: 'Pointage sans GPS activé — ton pointage sera validé manuellement par l\'établissement, rien à faire de ton côté.' });
  };

  const {
    data: presencesData,
    isLoading: loading,
    isError: chargementEnErreur,
    error: erreurChargement,
    refetch: rechargerPresences,
  } = useQuery({
    queryKey: ['presences-soignant', user?.id],
    queryFn: async () => {
      const aujourdhui = debutJourParis(new Date());
      const demain = ajouterJoursCivilsParis(aujourdhui, 1);
      const il7jours = ajouterJoursCivilsParis(new Date(), -7);
      const [missionsResult, valideesResult, historiqueResult, missionsHistoriqueResult] = await Promise.all([
        supabase
          .from('missions')
          .select(`
            id, intitule, service, debut_le, fin_le, duree_heures, statut, etablissement_id,
            type_contrat_applique, type_contrat_recherche, total_brut, net_a_payer, net_estime,
            presences(id, pointage_arrivee_le, pointage_depart_le,
              perimetre_gps_valide, alerte_teleportation, distance_etablissement_m,
              arrivee_precision_gps_m, depart_precision_gps_m, valide_par_etablissement, valide_le,
              methode_pointage_arrivee, methode_pointage_depart)
          `)
          .eq('soignant_assigne_id', user!.id)
          .in('statut', ['ASSIGNEE', 'EN_COURS'])
          .order('debut_le', { ascending: true }),
        supabase
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
          .order('valide_le', { ascending: false }),
        supabase
          .from('presences')
          .select(`
            id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le,
            valide_par_etablissement, valide_le,
            methode_pointage_arrivee, methode_pointage_depart,
            missions(id, intitule, etablissement_id, debut_le, fin_le, statut)
          `)
          .eq('soignant_id', user!.id)
          .order('cree_le', { ascending: false })
          .limit(100),
        supabase
          .from('missions')
          .select('id, intitule, service, debut_le, fin_le, duree_heures, statut, etablissement_id, type_contrat_applique, type_contrat_recherche, total_brut, net_a_payer, net_estime')
          .eq('soignant_assigne_id', user!.id)
          .in('statut', ['TERMINEE', 'LITIGE', 'ABSENCE'])
          .order('fin_le', { ascending: false })
          .limit(100),
      ]);

      if (missionsResult.error) throw missionsResult.error;
      if (valideesResult.error) throw valideesResult.error;
      if (historiqueResult.error) throw historiqueResult.error;
      if (missionsHistoriqueResult.error) throw missionsHistoriqueResult.error;

      const missionsActives = missionsResult.data || [];
      const missionIds = missionsActives.map((mission: any) => mission.id);
      const presencesValideesBrutes = valideesResult.data || [];
      const historiqueBrut = historiqueResult.data || [];
      const missionsHistoriques = missionsHistoriqueResult.data || [];
      const tousMissionIds = [...new Set([
        ...missionIds,
        ...presencesValideesBrutes.map((presence: any) => presence.mission_id),
        ...historiqueBrut.map((presence: any) => presence.mission_id),
        ...missionsHistoriques.map((mission: any) => mission.id),
      ].filter(Boolean))];

      const [creneauxResult, contratsResult, etabMap, etabMapValidees, etabMapHistorique, etabMapMissionsHistorique] = await Promise.all([
        tousMissionIds.length > 0
          ? supabase
            .from('mission_creneaux')
            .select('id, mission_id, debut, fin, est_pause, type_creneau')
            .in('mission_id', tousMissionIds)
            .order('debut', { ascending: true })
          : Promise.resolve({ data: [], error: null }),
        missionIds.length > 0
          ? supabase
            .from('contrats_mission')
            .select('id, mission_id, statut, cree_le')
            .in('mission_id', missionIds)
          : Promise.resolve({ data: [], error: null }),
        fetchEtablissementsSafe(missionsActives.map((mission: any) => mission.etablissement_id)),
        fetchEtablissementsSafe(
          presencesValideesBrutes.map((presence: any) => presence.missions?.etablissement_id).filter(Boolean),
        ),
        fetchEtablissementsSafe(
          historiqueBrut.map((presence: any) => presence.missions?.etablissement_id).filter(Boolean),
        ),
        fetchEtablissementsSafe(
          missionsHistoriques.map((mission: any) => mission.etablissement_id).filter(Boolean),
        ),
      ]);

      if (creneauxResult.error) throw creneauxResult.error;
      if (contratsResult.error) throw contratsResult.error;

      const creneauxParMission: Record<string, CreneauPointage[]> = {};
      (creneauxResult.data || []).forEach((creneau: any) => {
        (creneauxParMission[creneau.mission_id] ||= []).push(creneau);
      });

      const contratsParMission: Record<string, any[]> = {};
      (contratsResult.data || []).forEach((contrat: any) => {
        (contratsParMission[contrat.mission_id] ||= []).push(contrat);
      });
      const contratsMap: Record<string, any> = {};
      Object.entries(contratsParMission).forEach(([missionId, contratsMission]) => {
        const contrat = choisirContratPointage(contratsMission);
        if (contrat) contratsMap[missionId] = contrat;
      });

      const missionsEnrichies = missionsActives.map((mission: any) => ({
        ...mission,
        creneaux: ajouterRepliMissionPonctuelle(creneauxParMission[mission.id] || [], mission),
        etablissements: etabMap[mission.etablissement_id] || null,
      }));

      const missionsList = missionsEnrichies.filter((mission: any) => {
        const creneaux = mission.creneaux as CreneauPointage[];
        const aUnSegmentOuvert = creneaux.some((creneau) => (
          creneau.type_creneau === 'EFFECTIF' && !creneau.est_pause && !creneau.fin
        ));
        const planifies = creneauxPrevisionnels(creneaux);
        const aUnCreneauAujourdhui = planifies.some((creneau) => (
          creneauChevauchePeriode(creneau, aujourdhui, demain)
        ));
        return aUnSegmentOuvert
          || aUnCreneauAujourdhui;
      });

      const aVenirList = missionsEnrichies
        .map((mission: any) => {
          const prochain = creneauxPrevisionnels(mission.creneaux)
            .find((creneau) => new Date(creneau.debut) >= demain);
          const dateAffichage = prochain?.debut ?? null;
          const dureeAffichageHeures = prochain?.fin
            ? (new Date(prochain.fin).getTime() - new Date(prochain.debut).getTime()) / 3_600_000
            : mission.duree_heures;
          return dateAffichage
            ? { ...mission, dateAffichage, prochainCreneau: prochain, dureeAffichageHeures }
            : null;
        })
        .filter(Boolean)
        .concat(missionsEnrichies
          .filter((mission: any) => (
            mission.statut === 'ASSIGNEE'
            && creneauxPrevisionnels(mission.creneaux).length === 0
          ))
          .map((mission: any) => ({
            ...mission,
            dateAffichage: null,
            prochainCreneau: null,
            dureeAffichageHeures: null,
            planningAConfirmer: true,
          })))
        .sort((a: any, b: any) => (
          a.dateAffichage && b.dateAffichage
            ? new Date(a.dateAffichage).getTime() - new Date(b.dateAffichage).getTime()
            : a.dateAffichage ? -1 : b.dateAffichage ? 1 : 0
        ))
        .slice(0, 20);

      // Une mission EN_COURS reste visible même sans présence legacy : les
      // créneaux EFFECTIF sont désormais la source de vérité du pointage.
      const enCoursList = filtrerMissionsEnCours(missionsEnrichies);

      const presencesList = presencesValideesBrutes.map((presence: any) => ({
        ...presence,
        missions: {
          ...presence.missions,
          etablissements: etabMapValidees[presence.missions?.etablissement_id] || null,
          creneaux: creneauxParMission[presence.mission_id] || [],
        },
      }));

      const historiqueLegacy = historiqueBrut.map((presence: any) => ({
        ...presence,
        missions: {
          ...presence.missions,
          etablissements: etabMapHistorique[presence.missions?.etablissement_id] || null,
          creneaux: creneauxParMission[presence.mission_id] || [],
        },
      }));
      const historiqueEffectifs = construireHistoriqueEffectifsSansPresence({
        missions: missionsHistoriques,
        presences: historiqueBrut,
        creneauxParMission,
        etablissements: etabMapMissionsHistorique,
        soignantId: user!.id,
      });
      const dateHistorique = (presence: any) => new Date(
        presence.pointage_depart_le
          || presence.pointage_arrivee_le
          || presence.missions?.fin_le
          || presence.missions?.debut_le
          || 0,
      ).getTime();
      const allList = [...historiqueLegacy, ...historiqueEffectifs]
        .sort((a, b) => dateHistorique(b) - dateHistorique(a));

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

  // 9.1 — deep link : la page consomme ?tab= (onglet initial) et ?filtre= .
  // Sans ça, le clic sur « À valider » du pipeline Revenus atterrissait sur
  // « À venir » (defaultValue) — vide — au lieu des présences en attente.
  const [searchParams] = useSearchParams();
  const tabInitial = searchParams.get('tab')
    || (missions.length > 0 ? 'aujourdhui' : missionsEnCours.length > 0 ? 'encours' : 'avenir');
  const filtreAValider = searchParams.get('filtre') === 'a_valider';

  // Filtre « à valider » = miroir EXACT du gate 7b-B : présence à pointage
  // complet (départ pointé) non encore validée par l'établissement. C'est la
  // même condition qui alimente le KPI « À valider » de Revenus.
  const historiqueAffiche = useMemo(
    () => (filtreAValider
      ? historiquePresences.filter((p: any) => !p.valide_par_etablissement && p.pointage_depart_le)
      : historiquePresences),
    [historiquePresences, filtreAValider],
  );

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
      stockerPointageHorsLigne(missionId, 'arrivee', undefined, consentementGPS === true);
      afficherNotification({ type: 'info', message: '📡 Mode hors-ligne : pointage stocké localement.', duree: 8000 });
      return;
    }

    let position: { coords: { latitude: number; longitude: number; accuracy: number } } | null = null;

    if (consentementGPS) {
      try {
        position = await obtenirPosition();
      } catch {
        afficherNotification({ type: 'erreur', message: 'Impossible d\'obtenir ta position. Vérifie que la géolocalisation est activée.' });
        return;
      }
    }

    const idTerminal = genererIdTerminal();
    const modeleTerminal = navigator.userAgent.substring(0, 100);

    const { data: rpcResult, error } = await supabase.rpc('fn_pointer_arrivee' as any, {
      p_mission_id: missionId,
      p_lat: position?.coords.latitude ?? null,
      p_lng: position?.coords.longitude ?? null,
      p_precision: position?.coords.accuracy ?? null,
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
      afficherNotification({ type: 'info', message: '✅ Arrivée pointée. Sans localisation, l\'établissement la validera manuellement — rien à faire de ton côté.' });
    } else if (perimetreOk) {
      afficherNotification({ type: 'succes', message: `✅ Arrivée pointée ! Tu es à ${Math.round(distanceM || 0)}m de l'établissement.` });
    } else {
      afficherNotification({ type: 'avertissement', message: `⚠️ Arrivée pointée, mais tu es à ${Math.round(distanceM || 0)}m (périmètre : 500m).` });
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
      stockerPointageHorsLigne(missionId, 'depart', presenceId, consentementGPS === true);
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
      p_lat: position?.coords.latitude ?? null,
      p_lng: position?.coords.longitude ?? null,
      p_precision: position?.coords.accuracy ?? null,
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
      const finance = montantFinanceAfficheMission(missionData);
      supabase.functions.invoke('send-email', {
        body: {
          type: 'MISSION_TERMINEE',
          data: {
            prenom: user.prenom || '',
            mission: missionData.intitule || 'Mission',
            etablissement: missionData.etablissements?.nom || '',
            heures: missionData.duree_heures || 0,
            net: finance?.montant || 0,
          },
          destinataire_id: user.id,
        },
      }).then(undefined, () => { afficherNotification({ type: 'erreur', message: 'Erreur lors de l\'envoi de l\'email de confirmation.' }); });
    }

    afficherNotification({ type: 'succes', message: '🏁 Départ pointé ! Mission terminée.' });

    // F4 (Lot 7b) : notation 1-tap au check-out — une seule fois par mission,
    // skippable (le bandeau évaluations rattrape les « Plus tard »).
    const clePrompt = `jolene_note_checkout_${missionId}`;
    if (!localStorage.getItem(clePrompt)) {
      localStorage.setItem(clePrompt, '1');
      setNotationMissionId(missionId);
    }
    charger();
  };

  // Pendant une restauration/rotation de session, React Query est désactivé
  // quelques millisecondes. Conserver un état de chargement évite le flash
  // trompeur « aucune mission » entre deux pointages.
  if (loading || !consentementCharge || !user) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  if (chargementEnErreur) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="card-base border-destructive/30 max-w-xl mx-auto" role="alert">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 shrink-0 text-destructive" />
            <div>
              <h1 className="font-semibold text-foreground">Impossible de charger tes présences</h1>
              <p className="text-sm text-muted-foreground mt-1">
                {extraireMessageErreur(erreurChargement)}
              </p>
              <Button type="button" className="mt-4" onClick={() => rechargerPresences()}>
                Réessayer
              </Button>
            </div>
          </div>
        </div>
      </LayoutApp>
    );
  }

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

      {notationMissionId && (
        <SheetNotationRapide
          open={!!notationMissionId}
          onOpenChange={(o) => { if (!o) setNotationMissionId(null); }}
          missionId={notationMissionId}
          sens="SOIGNANT_VERS_ETAB"
          titre="Mission terminée 🎉 Comment ça s'est passé ?"
          description="Un tap suffit — ta note aide les autres soignants à choisir leurs missions."
        />
      )}

      {consentementGPS === false && <BandeauSansGPS />}

      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Clock className="h-5 w-5 text-primary" /> Mes présences
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Pointe tes arrivées et départs pour chaque mission</p>
      </div>

      <Tabs defaultValue={tabInitial}>
        <TabsList className="mb-4 grid w-full max-w-lg grid-cols-2 gap-1 sm:inline-flex sm:gap-0">
          <TabsTrigger value="avenir" className="flex-1 gap-1.5"><CalendarDays className="h-4 w-4" />À venir{missionsAVenir.length > 0 && <BadgeY2K variant="info" size="sm" className="ml-1 h-5 min-w-[20px] justify-center px-1" aria-label={`${missionsAVenir.length} mission${missionsAVenir.length > 1 ? 's' : ''} à venir`}>{missionsAVenir.length}</BadgeY2K>}</TabsTrigger>
          <TabsTrigger value="encours" className="flex-1 gap-1.5"><Activity className="h-4 w-4" />Actives</TabsTrigger>
          <TabsTrigger value="aujourdhui" className="flex-1 gap-1.5"><Clock className="h-4 w-4" />Aujourd'hui</TabsTrigger>
          <TabsTrigger value="historique" className="flex-1 gap-1.5"><History className="h-4 w-4" />Historique</TabsTrigger>
        </TabsList>

        <TabsContent value="avenir">
          {missionsAVenir.length > 0 ? (
            <div className="space-y-3">
              {missionsAVenir.map((m: any) => (
                <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3">
                  {m.planningAConfirmer ? (
                    <div className="flex h-[56px] min-w-[52px] items-center justify-center rounded-xl bg-warning/10 text-warning">
                      <AlertTriangle className="h-5 w-5" />
                    </div>
                  ) : (
                    <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                      <span className="text-[10px] font-semibold text-primary uppercase">{formatParis(m.dateAffichage, 'EEE')}</span>
                      <span className="text-lg font-bold text-primary leading-tight">{formatParis(m.dateAffichage, 'd')}</span>
                      <span className="text-[10px] text-primary">{formatParis(m.dateAffichage, 'MMM')}</span>
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <BadgeStatut statut={m.statut} />
                    <h3 className="font-semibold text-sm text-foreground truncate mt-1" title={m.intitule}>{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      🏥 {m.etablissements?.nom || 'Établissement'}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                    </p>
                    {m.planningAConfirmer ? (
                      <p className="text-xs font-medium text-warning mt-0.5">Planning détaillé à confirmer avec l’établissement</p>
                    ) : (
                      <p className="text-xs text-muted-foreground mt-0.5">
                        🕐 {formatParis(m.dateAffichage, "HH'h'mm")} → {formatParis(m.prochainCreneau.fin, "HH'h'mm")}
                        {m.dureeAffichageHeures ? ` (${m.dureeAffichageHeures}h)` : ''}
                      </p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState
              icone={<CalendarDays />}
              mascotte="thinking"
              titre="Aucune mission à venir"
              description="Tes prochaines missions assignées apparaîtront ici."
              cta={{ label: 'Chercher des missions', onClick: () => navigate('/soignant/missions') }}
            />
          )}
        </TabsContent>

        <TabsContent value="encours">
          {missionsEnCours.length > 0 ? (
            <div className="space-y-4">
              {missionsEnCours.map((mission: any) => (
                <BlocPointageMission
                  key={mission.id}
                  mission={mission}
                  contrat={contrats[mission.id]}
                  consentementGPS={consentementGPS}
                />
              ))}
            </div>
          ) : (
            <EmptyState
              icone={<Activity />}
              mascotte="empty"
              titre="Aucune mission active"
              description="Tes missions actives apparaîtront ici, même entre deux créneaux."
              cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }}
            />
          )}
        </TabsContent>

        <TabsContent value="aujourdhui">
          {missions.length > 0 ? (
            <div className="space-y-4">
              {missions.map((mission: any) => (
                <BlocPointageMission
                  key={mission.id}
                  mission={mission}
                  contrat={contrats[mission.id]}
                  consentementGPS={consentementGPS}
                />
              ))}
            </div>
          ) : (
            <EmptyState
              icone={<CalendarDays />}
              mascotte="empty"
              titre="Aucune mission aujourd'hui"
              description="Tes missions assignées apparaîtront ici le jour J pour le pointage."
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
                        {p.valide_le && formatParis(p.valide_le, "d MMM yyyy 'à' HH:mm")}
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
          {filtreAValider && (
            <div className="mb-3 rounded-xl bg-warning/10 border border-warning/30 p-3 text-sm text-warning font-medium">
              ⏳ Présences en attente de validation par l'établissement. Le paiement est débloqué dès la validation (automatique sous 72h).
            </div>
          )}
          {historiqueAffiche.length > 0 ? (
            <div className="space-y-3">
              {historiqueAffiche.map((p: any) => {
                const m = p.missions;
                const segmentsEffectifs = ((m?.creneaux || []) as CreneauPointage[])
                  .filter((creneau) => (
                    creneau.type_creneau === 'EFFECTIF'
                    && !creneau.est_pause
                    && Boolean(creneau.fin)
                  ))
                  .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
                const arrivee = segmentsEffectifs[0]?.debut
                  ? new Date(segmentsEffectifs[0].debut)
                  : p.pointage_arrivee_le ? new Date(p.pointage_arrivee_le) : null;
                const depart = segmentsEffectifs.at(-1)?.fin
                  ? new Date(segmentsEffectifs.at(-1)!.fin!)
                  : p.pointage_depart_le ? new Date(p.pointage_depart_le) : null;
                const heuresEffectives = segmentsEffectifs.reduce((total, segment) => (
                  total + (new Date(segment.fin!).getTime() - new Date(segment.debut).getTime()) / 3_600_000
                ), 0);
                const heuresTravaillees = segmentsEffectifs.length > 0
                  ? heuresEffectives.toFixed(1)
                  : arrivee && depart ? ((depart.getTime() - arrivee.getTime()) / 3_600_000).toFixed(1) : null;

                return (
                  <div key={p.id} className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate(`/soignant/presences/mission/${p.mission_id}`)}>
                    <div className="flex items-start justify-between mb-2">
                      <div>
                        <p className="font-semibold text-sm text-foreground">{m?.intitule}</p>
                        <p className="text-xs text-muted-foreground">🏥 {m?.etablissements?.nom || 'Établissement'}</p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          📅 {m?.debut_le && formatParis(m.debut_le, 'd MMM yyyy')}
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
                        {arrivee ? formatParis(arrivee, "d MMM · HH'h'mm") : '—'}
                        <span className="ml-1 text-[10px]">{getMethodeLabel(p.methode_pointage_arrivee)}</span>
                      </div>
                      <div>
                        <span className="font-medium text-foreground">Départ :</span>{' '}
                        {depart ? formatParis(depart, "d MMM · HH'h'mm") : '—'}
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

                    {!p.valide_par_etablissement && !p.origine_effectifs_sans_presence && (
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
                    {p.origine_effectifs_sans_presence && (
                      <div className="mt-2 rounded-lg border border-warning/30 bg-warning/5 p-2.5 text-xs text-muted-foreground">
                        <p>
                          Relevé reconstruit depuis les segments de pointage. La validation historique n’est pas disponible sur cet ancien dossier.
                        </p>
                        <button
                          type="button"
                          className="mt-2 min-h-11 font-semibold text-primary hover:underline"
                          onClick={(event) => {
                            event.stopPropagation();
                            navigate('/soignant/litiges');
                          }}
                        >
                          Voir ou signaler un litige
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          ) : (
            <EmptyState icone={<History />} mascotte="empty" titre="Aucune présence enregistrée" description="Ton historique de pointages apparaîtra ici." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
          )}
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}

import React, { useState, useMemo, useEffect, useCallback } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Link, useNavigate } from 'react-router-dom';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { AlertCircle, AlertTriangle, Banknote, Bell, CalendarDays, ChevronRight, CreditCard, FileText, Scale, Sparkles } from 'lucide-react';
import { CarteProposition } from '@/components/CarteProposition';
import type { PropositionMission } from '@/components/CarteProposition';
import { NoteNetEstime } from '@/components/NoteNetEstime';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { WidgetAllerPointer } from '@/components/WidgetAllerPointer';
import { BandeauOubliDepart } from '@/components/BandeauOubliDepart';
import { LayoutApp } from '@/components/LayoutApp';
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { ChecklistActivation, useActivationSoignant } from '@/components/dashboard/ChecklistActivation';
import { useAppliquerParrainage } from '@/hooks/useAppliquerParrainage';
import type { SoignantActivation, DocumentActivation } from '@/components/dashboard/ChecklistActivation';
import { BandeauCompletionProfil } from '@/components/profil-soignant/BandeauCompletionProfil';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BandeauAlerte48h } from '@/components/BandeauAlerte48h';
import { BandeauGraceDocuments } from '@/components/BandeauGraceDocuments';
import { BoutonAjouterCalendrier } from '@/components/SyncCalendrier';
import { SectionErrorBoundary } from '@/components/SectionErrorBoundary';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { differenceInDays } from 'date-fns';
import { extraireMessageErreur } from '@/lib/erreurs';
import { logger } from '@/lib/logger';
import {
  FENETRE_OUVERTURE_POINTAGE_MINUTES,
  prochainCreneauPointage,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { analyserCompletudePlanningMission } from '@/lib/completude-planning-mission';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import { formatParis, instantJolene } from '@/lib/date-heure-paris';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import { filtrerMissionsPlaywright } from '@/lib/donnees-test';
import { useChargementProlonge } from '@/hooks/useChargementProlonge';
/** 6c.5 : salutation heure-aware — « Hiii » → Bonjour/Bonsoir selon l'heure. */
function salutationHeure(): string {
  const h = new Date().getHours();
  if (h >= 5 && h < 18) return 'Bonjour';
  return 'Bonsoir';
}

interface SoignantData {
  prenom: string; nom: string; telephone: string | null;
  date_naissance: string | null; profession: string; type_contrat: string | null;
  numero_rpps: string | null; numero_adeli: string | null;
  adresse_lat: number | null; adresse_lng: number | null;
  tous_documents_valides: boolean | null; identite_verifiee: boolean | null;
  score_fiabilite: number | null; total_missions_terminees: number | null;
  heures_cumulees: number | null; eligible_conversion_3200h: boolean | null;
  type_exercice: string | null;
}

const EMPTY_SOIGNANT = {
  prenom: '', nom: '', telephone: '', profession: null, rpps_verifie: false,
  adresse_lat: null, adresse_lng: null, tous_documents_valides: false,
  identite_verifiee: false, score_fiabilite: 0, total_missions_terminees: 0,
  heures_cumulees: 0, type_exercice: 'SALARIE',
} as unknown as SoignantData;

export default function DashboardSoignant() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { user } = useAuth();
  // 7f : consomme le code parrainage capté (?ref=/?parrain=) à la 1ʳᵉ session.
  useAppliquerParrainage(user?.id);
  const [propositions, setPropositions] = useState<PropositionMission[]>([]);
  const [maintenant, setMaintenant] = useState(() => new Date());

  useEffect(() => {
    const intervalle = window.setInterval(() => setMaintenant(new Date()), 30_000);
    return () => window.clearInterval(intervalle);
  }, []);

  const {
    data: dashboard,
    isLoading,
    isError,
    error: erreurDashboard,
    refetch: rechargerDashboard,
  } = useQuery({
    queryKey: ['dashboard-soignant', user?.id],
    queryFn: async () => {
      const maintenantRequete = new Date();
      const debutMois = new Date(
        maintenantRequete.getFullYear(),
        maintenantRequete.getMonth(),
        1,
      ).toISOString();
      const [
        { data, error },
        { data: connectData, error: connectError },
        { data: gainsMissionsData, error: gainsMissionsError },
        { data: propositionsLitigesData, error: propositionsLitigesError },
      ] = await Promise.all([
        supabase.rpc('fn_dashboard_soignant_complet' as any),
        supabase
          .from('stripe_connect_onboarding')
          .select('statut')
          .eq('soignant_id', user!.id)
          .maybeSingle(),
        supabase
          .from('missions')
          .select('id, type_contrat_applique, type_contrat_recherche, total_brut, net_a_payer, net_estime')
          .eq('soignant_assigne_id', user!.id)
          .eq('statut', 'TERMINEE')
          .gte('fin_le', debutMois),
        supabase
          .from('litiges')
          .select('id, mission_id, statut, payload_modifications, accord_soignant, accord_etablissement, missions(intitule)')
          .eq('soignant_id', user!.id)
          .eq('accord_soignant', false)
          .eq('accord_etablissement', true)
          .not('payload_modifications', 'is', null)
          .in('statut', ['OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS'])
          .order('cree_le', { ascending: false })
          .limit(5),
      ]);
      if (error) throw error;
      if (connectError) logger.warn('[DashboardSoignant] Stripe Connect indisponible', connectError);
      if (gainsMissionsError) logger.warn('[DashboardSoignant] Gains détaillés indisponibles', gainsMissionsError);
      if (propositionsLitigesError) logger.warn('[DashboardSoignant] Propositions de litige indisponibles', propositionsLitigesError);
      if (!data) return { profil: null, missions_ouvertes: [], mes_missions: [], documents: [], heures_semaine: 0, gains_mois: { net_total: 0, brut_total: 0, nb_missions: 0 }, gains_missions: [], gains_6mois: [], missions_semaine_cal: [], propositions: [], propositions_litiges: [], heures_totales_terminees: 0, missions_oubliees_count: 0, notifs_non_lues: 0, hasStripeConnect: true };

      const missions = filtrerMissionsPlaywright(
        Array.isArray((data as any).mes_missions) ? (data as any).mes_missions : [],
        user?.email,
      );
      const missionsOuvertes = filtrerMissionsPlaywright(
        Array.isArray((data as any).missions_ouvertes) ? (data as any).missions_ouvertes : [],
        user?.email,
      );
      const missionIds = [...new Set(
        [...missions, ...missionsOuvertes]
          .map((mission: any) => mission.id)
          .filter(Boolean),
      )] as string[];

      let creneaux: CreneauPointage[] = [];
      let nombreCreneauxParMission = new Map<string, number | null>();
      let planningErreur = false;
      if (missionIds.length > 0) {
        try {
          const [creneauxCharges, missionsResult] = await Promise.all([
            chargerCreneauxMissionsPagines(missionIds, {
              typeCreneau: 'PREVISIONNEL',
              exclurePauses: true,
            }),
            supabase
              .from('missions')
              .select('id, nb_creneaux')
              .in('id', missionIds),
          ]);
          if (missionsResult.error) throw missionsResult.error;
          const metas = missionsResult.data ?? [];
          if (metas.length !== missionIds.length) {
            throw new Error('Le nombre de créneaux attendu ne peut pas être vérifié pour toutes les missions.');
          }
          creneaux = creneauxCharges as CreneauPointage[];
          nombreCreneauxParMission = new Map(
            metas.map((mission: any) => [mission.id, mission.nb_creneaux]),
          );
        } catch (erreurPlanning) {
          planningErreur = true;
          logger.warn('[DashboardSoignant] Planning détaillé indisponible', erreurPlanning);
        }
      }

      const creneauxParMission: Record<string, CreneauPointage[]> = {};
      creneaux.forEach((creneau: any) => {
        (creneauxParMission[creneau.mission_id] ||= []).push(creneau);
      });
      const maintenant = new Date();
      const enrichirPlanning = (mission: any) => {
        const analyse = planningErreur
          ? null
          : analyserCompletudePlanningMission(
              { ...mission, nb_creneaux: nombreCreneauxParMission.get(mission.id) },
              creneauxParMission[mission.id] || [],
            );
        if (!analyse?.complet) {
          return {
            ...mission,
            creneaux: [],
            planning_indisponible: true,
            prochainCreneau: null,
            debut_affiche: null,
            fin_affichee: null,
            duree_creneau_heures: null,
            duree_planifiee_heures: null,
            nb_creneaux_planifies: 0,
          };
        }

        const prochain = prochainCreneauPointage(analyse.creneauxPlanifies, maintenant);
        const indexProchain = prochain ? analyse.creneauxPlanifies.indexOf(prochain) + 1 : null;
        const dureeCreneauHeures = prochain?.fin
          ? (instantJolene(prochain.fin).getTime() - instantJolene(prochain.debut).getTime()) / 3_600_000
          : null;
        return {
          ...mission,
          creneaux: analyse.creneauxPlanifies,
          planning_indisponible: false,
          prochainCreneau: prochain,
          index_prochain_creneau: indexProchain,
          debut_affiche: prochain?.debut ?? null,
          fin_affichee: prochain?.fin ?? null,
          duree_creneau_heures: dureeCreneauHeures,
          duree_planifiee_heures: analyse.dureeTotaleHeures,
          nb_creneaux_planifies: analyse.nombrePlanifie,
        };
      };

      return {
        ...data,
        mes_missions: missions.map(enrichirPlanning),
        missions_ouvertes: missionsOuvertes.map(enrichirPlanning),
        // Le RPC historique agrégeait parfois le brut salarié sous le nom
        // `net_total`. Les montants affichés sont recalculés mission par mission.
        gains_missions: gainsMissionsError ? [] : (gainsMissionsData ?? []),
        propositions_litiges: propositionsLitigesError ? [] : (propositionsLitigesData ?? []),
        // En cas d'échec du module facultatif, ne pas afficher à tort un CTA
        // d'onboarding Stripe sur un compte potentiellement déjà configuré.
        hasStripeConnect: connectError ? true : connectData?.statut === 'COMPLET',
      };
    },
    staleTime: 60_000,
    refetchInterval: 60_000,
    enabled: !!user,
  });
  const { estProlonge: chargementProlonge, reinitialiser: reinitialiserChargement } = useChargementProlonge(isLoading);

  const relancerDashboard = () => {
    reinitialiserChargement();
    void queryClient.resetQueries({
      queryKey: ['dashboard-soignant', user?.id],
      exact: true,
    });
  };

  // Keep propositions in local state so they can be removed on action
  const dashboardPropositions = dashboard?.propositions;
  useEffect(() => {
    if (Array.isArray(dashboardPropositions)) {
      setPropositions(dashboardPropositions as PropositionMission[]);
    }
  }, [dashboardPropositions]);
  const retirerPropositionTraitee = useCallback((id: string) => {
    setPropositions(prev => prev.filter(proposition => proposition.id !== id));
  }, []);

  // Derive all values from the dashboard RPC response
  const soignant = dashboard?.profil as SoignantData | undefined ?? null;
  const mesMissions = useMemo(
    () => (dashboard?.mes_missions ?? []) as any[],
    [dashboard?.mes_missions],
  );
  // Lot 1 — opportunités à montrer en page d'accueil (valeur avant l'effort).
  const missionsOuvertes = (dashboard?.missions_ouvertes ?? []) as any[];
  const heuresSemaine = (dashboard?.heures_semaine ?? 0) as number;
  const hasStripeConnect = dashboard?.hasStripeConnect ?? true;
  const propositionsLitiges = (dashboard?.propositions_litiges ?? []) as any[];

  const docsExpirant = useMemo(() => {
    const docs = (dashboard?.documents ?? []) as any[];
    return docs.filter((d: any) =>
      d.valide_jusqua && d.statut_verification === 'VERIFIE' &&
      new Date(d.valide_jusqua) > new Date() &&
      differenceInDays(new Date(d.valide_jusqua), new Date()) < 30
    );
  }, [dashboard?.documents]);

  const missionProchaine = useMemo(() => {
    const maintenantMs = maintenant.getTime();
    const missionsActualisees = (mesMissions as any[])
      .filter((mission: any) => !mission.planning_indisponible)
      .map((mission: any) => {
        const planning = mission.creneaux || [];
        const prochainCreneau = prochainCreneauPointage(planning, maintenant);
        const creneauActuel = planning.some((creneau: CreneauPointage) => (
          creneau.type_creneau === 'PREVISIONNEL'
          && !creneau.est_pause
          && Boolean(creneau.fin)
          && maintenantMs >= instantJolene(creneau.debut).getTime() - FENETRE_OUVERTURE_POINTAGE_MINUTES * 60_000
          && maintenantMs <= instantJolene(creneau.fin!).getTime()
        ));
        return {
          ...mission,
          prochainCreneau,
          creneauActuel,
          debut_affiche: prochainCreneau?.debut ?? null,
          fin_affichee: prochainCreneau?.fin ?? null,
        };
      });

    const aPointer = missionsActualisees.find((mission: any) => mission.creneauActuel);
    if (aPointer) return aPointer;

    const missionProche = missionsActualisees.find((m: any) => {
      if (!m.debut_affiche) return false;
      const mins = (instantJolene(m.debut_affiche).getTime() - maintenantMs) / 60000;
      return mins > -30 && mins <= 60;
    });
    if (missionProche) return missionProche;

    return missionsActualisees
      .filter((mission: any) => mission.statut === 'EN_COURS' && mission.debut_affiche)
      .sort((a: any, b: any) => (
        instantJolene(a.debut_affiche).getTime() - instantJolene(b.debut_affiche).getTime()
      ))[0] || null;
  }, [mesMissions, maintenant]);

  const missionsOubliDepartCount = Math.max(0, Number(dashboard?.missions_oubliees_count) || 0);
  const gainsMissionsDashboard = (dashboard as any)?.gains_missions;

  const gainsCeMois = useMemo(() => {
    const result = { honoraires: 0, netSalarie: 0, brutIndicatif: 0, nb: 0 };
    const missionsGains = Array.isArray(gainsMissionsDashboard)
      ? gainsMissionsDashboard
      : [];
    missionsGains.forEach((mission: any) => {
      const finance = montantFinanceAfficheMission(mission);
      if (!finance) return;
      result.nb += 1;
      if (finance.nature === 'HONORAIRES_LIBERAUX') result.honoraires += finance.montant;
      else if (finance.nature === 'NET_SALARIE_ESTIME') result.netSalarie += finance.montant;
      else result.brutIndicatif += finance.montant;
    });
    return result;
  }, [gainsMissionsDashboard]);

  const { missionsTermineesCount, heuresCumuleesTotal } = useMemo(() => {
    // RPC returns heures_totales_terminees as a number (SUM of duree_heures)
    const heuresTotales = Number(dashboard?.heures_totales_terminees ?? 0);
    return {
      missionsTermineesCount: soignant?.total_missions_terminees ?? 0,
      heuresCumuleesTotal: Math.max(soignant?.heures_cumulees || 0, heuresTotales),
    };
  }, [dashboard?.heures_totales_terminees, soignant]);

  // Override soignant counts with real computed values
  const soignantWithCounts = useMemo(() => ({
    ...(soignant ?? EMPTY_SOIGNANT),
    total_missions_terminees: missionsTermineesCount,
    heures_cumulees: heuresCumuleesTotal,
  }) as SoignantData, [soignant, missionsTermineesCount, heuresCumuleesTotal]);

  const aRib = (dashboard?.documents ?? []).some(
    (d: any) => d.type_document === 'RIB' && d.statut_verification !== 'REJETE',
  );

  // Lot 6b.4 — checklist d'activation UNIQUE « Active ton compte — X/N »
  // (RPPS · Documents · Mandat · Paiement, adaptative au régime). Absorbe les
  // anciens nudges mandat/Stripe/RIB : au plus UNE carte d'action système.
  const activation = useActivationSoignant({
    soignant: soignant as unknown as SoignantActivation | null,
    documents: (dashboard?.documents ?? []) as DocumentActivation[],
    hasStripeConnect,
    aRib,
  });

  if (isLoading) {
    return (
      <LayoutApp role="SOIGNANT">
        {chargementProlonge ? (
          <div className="mx-auto flex min-h-[55vh] max-w-xl items-center px-4">
            <div
              role="alert"
              className="w-full rounded-2xl border border-amber-300 bg-amber-50 p-6 text-center shadow-sm dark:border-amber-700 dark:bg-amber-950/30"
            >
              <AlertTriangle className="mx-auto h-8 w-8 text-amber-600 dark:text-amber-400" aria-hidden="true" />
              <h1 className="mt-3 text-xl font-semibold text-foreground">Ton tableau de bord met plus de temps que prévu</h1>
              <p className="mt-2 text-sm text-muted-foreground">
                Ta session est toujours active. Vérifie ta connexion, puis relance le chargement.
              </p>
              <BoutonY2K className="mt-5" onClick={relancerDashboard}>
                Réessayer
              </BoutonY2K>
            </div>
          </div>
        ) : (
          <SkeletonDashboard />
        )}
      </LayoutApp>
    );
  }

  if (isError) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="card-base mx-auto max-w-xl border-destructive/30" role="alert">
          <div className="flex items-start gap-3">
            <AlertCircle className="h-5 w-5 shrink-0 text-destructive" />
            <div>
              <h1 className="font-semibold text-foreground">Impossible de charger ton tableau de bord</h1>
              <p className="mt-1 text-sm text-muted-foreground">
                {extraireMessageErreur(erreurDashboard)}
              </p>
              <BoutonY2K
                type="button"
                size="sm"
                variant="secondary"
                className="mt-4"
                onClick={() => rechargerDashboard()}
              >
                Réessayer
              </BoutonY2K>
            </div>
          </div>
        </div>
      </LayoutApp>
    );
  }


  return (
    <LayoutApp role="SOIGNANT">
      {propositionsLitiges.length > 0 && (
        <section className="mb-4 rounded-xl border-2 border-warning/40 bg-warning/5 p-4" role="alert">
          <div className="flex items-start gap-3">
            <Scale className="mt-0.5 h-5 w-5 shrink-0 text-warning" aria-hidden="true" />
            <div className="min-w-0 flex-1">
              <h2 className="font-bold text-foreground">Proposition de résolution à examiner</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                L’établissement a proposé un accord pour {propositionsLitiges[0]?.missions?.intitule || 'une mission'}.
                Consulte le détail avant de l’accepter ou de contre-proposer.
              </p>
              <button
                type="button"
                className="mt-3 text-sm font-semibold text-primary hover:underline"
                onClick={() => navigate(`/soignant/litiges?litige=${propositionsLitiges[0].id}`)}
              >
                Voir la proposition →
              </button>
            </div>
          </div>
        </section>
      )}
      {/* Checklist d'activation EN PREMIER pour un profil incomplet (elle se
          masque seule — return null — quand le profil est complet, donc aucun
          coût pour un soignant activé qui voit alors directement le CTA). */}
      <ChecklistActivation state={activation} className="mb-4" />

      {/* ═══ ZONE 1 : HERO + CTA (ce que le soignant voit en premier) ═══ */}

      {/* Header Y2K compact : mascotte + nom + chips gamification */}
      <div className="mb-4 flex items-start gap-4">
        {/* 6c.5 : mascotte neutre/souriante par défaut — la version triste est
            réservée aux états d'erreur, jamais au message d'accueil. */}
        <Mascotte etat="happy" taille="md" className="shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-xl font-bold text-foreground">
              {salutationHeure()}, <span className="text-gradient-hero">{soignantWithCounts.prenom}</span>
            </h1>
            <BadgeRPPS rppsVerifie={(soignantWithCounts as any).rpps_verifie} rpps={(soignantWithCounts as any).numero_rpps} profession={soignantWithCounts.profession} />
          </div>
          {!soignantWithCounts.tous_documents_valides ? (
            <p className="text-sm text-muted-foreground mt-1">
              {missionsOuvertes.length > 0
                ? `${missionsOuvertes.length} mission${missionsOuvertes.length > 1 ? 's' : ''} près de chez toi — tu peux déjà postuler.`
                : "Tu peux déjà postuler — tes documents validés débloquent l'acceptation."}
            </p>
          ) : (
            <p className="text-sm text-muted-foreground mt-1">
              {missionsOuvertes.length > 0
                ? `${missionsOuvertes.length} mission${missionsOuvertes.length > 1 ? 's' : ''} pour toi 🔥`
                : 'On trouve ta prochaine mission ? 🔥'}
            </p>
          )}
        </div>
      </div>

      {/* 6c.5 : les boutons « Trouver une mission » / « Mes missions » sont
          supprimés — ils dupliquaient les onglets Explorer / Mes missions de
          la bottom nav. */}

      {/* ═══ ZONE 2 : CONTEXTE IMMÉDIAT (missions en cours / pointage) ═══ */}

      {missionsOubliDepartCount > 0 && (
        <BandeauOubliDepart
          mission={{ count: missionsOubliDepartCount }}
          onPointer={() => navigate('/soignant/presences')}
        />
      )}

      {missionProchaine && <WidgetAllerPointer mission={missionProchaine} />}

      {/* Missions à venir (planning) */}
      <SectionErrorBoundary section="missions-a-venir">
      {mesMissions.length > 0 && (
        <div className="mb-6">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-base font-bold text-foreground flex items-center gap-2">
              <CalendarDays className="h-4.5 w-4.5 text-primary" /> Mes prochaines missions
            </h2>
            <button onClick={() => navigate('/soignant/missions?onglet=mes_missions')} className="text-xs text-primary font-medium hover:underline">Voir tout →</button>
          </div>
          <div className="space-y-2">
            {mesMissions.map((m: any) => {
              const planningAffichable = !m.planning_indisponible && m.debut_affiche && m.fin_affichee;
              return (
                <div key={m.id} className="card-base hover:shadow-md transition-all flex items-center gap-3 py-3">
                  <Link
                    to={`/soignant/missions/${m.id}`}
                    className="flex flex-1 min-w-0 items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    aria-label={`Voir la mission ${m.intitule}`}
                  >
                    <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px] min-h-[58px]">
                      {planningAffichable ? (
                        <>
                          <span className="text-[10px] font-semibold text-primary uppercase">{formatParis(m.debut_affiche, 'EEE')}</span>
                          <span className="text-lg font-bold text-primary leading-tight">{formatParis(m.debut_affiche, 'd')}</span>
                          <span className="text-[10px] text-primary">{formatParis(m.debut_affiche, 'MMM')}</span>
                        </>
                      ) : (
                        <CalendarDays className="h-5 w-5 text-warning" aria-hidden="true" />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <BadgeStatut statut={m.statut} />
                        {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px]">🔥 Urgent</span>}
                      </div>
                      <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        🏥 {m.etablissements?.nom || m.etab_nom || 'Établissement'}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                      </p>
                      {planningAffichable ? (
                        <p className="text-xs text-muted-foreground mt-0.5">
                          🕐 {formatParis(m.debut_affiche, "EEEE d MMM · HH'h'mm")} → {formatParis(m.fin_affichee, "HH'h'mm")}
                          {m.duree_creneau_heures ? ` · ${m.duree_creneau_heures.toLocaleString('fr-FR')} h` : ''}
                          {m.nb_creneaux_planifies > 1 && m.index_prochain_creneau
                            ? ` · créneau ${m.index_prochain_creneau}/${m.nb_creneaux_planifies}`
                            : ''}
                        </p>
                      ) : (
                        <p className="text-xs font-medium text-warning mt-1">Planning détaillé à confirmer</p>
                      )}
                    </div>
                  </Link>
                  {planningAffichable ? (
                    <BoutonAjouterCalendrier
                      mission={{ ...m, debut_le: m.debut_affiche, fin_le: m.fin_affichee }}
                    />
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      )}
      </SectionErrorBoundary>


      {/* ✦ Missions pour toi — opportunités du pool ouvert (Lot 1). Placé APRÈS les
          widgets de pointage imminent (pointer prime sur prospecter), mais haut dans
          la page : la valeur est montrée avant l'effort, profil incomplet inclus.
          Tap → détail/postuler. Si aucune mission : bloc vendeur, jamais un trou. */}
      <SectionErrorBoundary section="missions-suggerees">
      <div className="mb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-base font-bold text-foreground flex items-center gap-2">
            <Sparkles className="h-4.5 w-4.5 text-primary" /> Missions pour toi
          </h2>
          <button onClick={() => navigate('/soignant/recherche-missions')} className="text-xs text-primary font-medium hover:underline">Tout voir →</button>
        </div>
        {missionsOuvertes.length > 0 ? (
          <div className="space-y-2">
            {missionsOuvertes.slice(0, 2).map((m: any) => {
              const planningAffichable = !m.planning_indisponible && m.debut_affiche && m.fin_affichee;
              const duree = Number(m.duree_planifiee_heures) > 0 ? Number(m.duree_planifiee_heures) : 0;
              const finance = montantFinanceAfficheMission(m);
              const brutDirect = Number(m.total_brut ?? m.brut_estime);
              const estimation = finance
                ? { montant: Math.round(finance.montant), libelle: finance.libelleCourt, approximatif: finance.approximatif }
                : Number.isFinite(brutDirect) && brutDirect > 0
                  ? { montant: Math.round(brutDirect), libelle: 'brut indicatif', approximatif: true }
                  : m.taux_horaire_base && duree
                    ? { montant: Math.round(Number(m.taux_horaire_base) * duree), libelle: 'brut indicatif', approximatif: true }
                    : null;
              return (
                <div key={m.id} className="card-base hover:shadow-md transition-all flex items-center gap-3 py-3">
                  <Link
                    to={`/soignant/missions/${m.id}`}
                    className="flex flex-1 min-w-0 items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    aria-label={`Voir la mission ${m.intitule}`}
                  >
                    <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px] min-h-[58px]">
                      {planningAffichable ? (
                        <>
                          <span className="text-[10px] font-semibold text-primary uppercase">{formatParis(m.debut_affiche, 'EEE')}</span>
                          <span className="text-lg font-bold text-primary leading-tight">{formatParis(m.debut_affiche, 'd')}</span>
                          <span className="text-[10px] text-primary">{formatParis(m.debut_affiche, 'MMM')}</span>
                        </>
                      ) : (
                        <CalendarDays className="h-5 w-5 text-warning" aria-hidden="true" />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px] mb-0.5 inline-block">🔥 Urgent</span>}
                      <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                      <p className="text-xs text-muted-foreground mt-0.5 truncate">🏥 {m.etab_nom || 'Établissement'}{m.service ? ` · ${m.service}` : ''}</p>
                      <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                        {planningAffichable ? (
                          <span>
                            🕐 {formatParis(m.debut_affiche, "EEEE d MMM · HH'h'mm")} → {formatParis(m.fin_affichee, "HH'h'mm")}
                            {m.nb_creneaux_planifies > 1 ? ` · ${m.nb_creneaux_planifies} créneaux au total` : ''}
                          </span>
                        ) : (
                          <span className="font-medium text-warning">Planning détaillé à confirmer</span>
                        )}
                        {m.taux_horaire_base && <span className="font-semibold text-primary">{m.taux_horaire_base} €/h</span>}
                        {estimation && <span>{estimation.approximatif ? '~' : ''}{estimation.montant} € {estimation.libelle}</span>}
                      </div>
                    </div>
                  </Link>
                  <BoutonY2K
                    size="sm"
                    variant="primary"
                    className="shrink-0"
                    onClick={(e: React.MouseEvent) => {
                      e.stopPropagation();
                      navigate(`/soignant/missions/${m.id}`);
                    }}
                  >
                    Voir le planning et postuler
                  </BoutonY2K>
                </div>
              );
            })}
          </div>
        ) : (
          <button onClick={() => navigate('/soignant/recherche-missions?alerte=1')} className="w-full rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 text-left hover:shadow-md transition-shadow">
            <p className="font-semibold text-foreground">De nouvelles missions arrivent 🔔</p>
            <p className="text-sm text-muted-foreground mt-0.5">Active les alertes pour être prévenu·e dès qu'une mission près de chez toi correspond à ton profil.</p>
          </button>
        )}
      </div>
      </SectionErrorBoundary>

      {/* Missions proposées depuis le pool — opportunités urgentes */}
      <SectionErrorBoundary section="propositions">
      {propositions.length > 0 && (
        <div className="mb-6 rounded-xl border-2 border-orange-400 bg-orange-50/50 dark:bg-orange-950/10 dark:border-orange-600 p-4">
          <h2 className="text-base font-bold text-foreground flex items-center gap-2 mb-3">
            <Bell className="h-5 w-5 text-orange-500" /> 🚨 Missions proposées
          </h2>
          <div className="space-y-3">
            {propositions.map((p) => (
              <CarteProposition
                key={p.id}
                proposition={p}
                onTraitee={retirerPropositionTraitee}
              />
            ))}
          </div>
        </div>
      )}
      </SectionErrorBoundary>

      {/* Tes revenus du mois — déplacé hors des onglets (Accueil linéaire) */}
      {gainsCeMois.nb > 0 && (
        <button type="button" className="card-base mb-6 w-full text-left hover:shadow-md transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50" onClick={() => navigate('/soignant/mes-gains')}>
          <div className="flex items-center gap-3">
            <div className="rounded-xl p-2.5 bg-primary/10"><Banknote className="h-5 w-5 text-primary" /></div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">
                💰 Ce mois : {[
                  gainsCeMois.honoraires > 0
                    ? `${new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(gainsCeMois.honoraires)} d’honoraires`
                    : null,
                  gainsCeMois.netSalarie > 0
                    ? `${new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(gainsCeMois.netSalarie)} net salarié estimé*`
                    : null,
                  gainsCeMois.brutIndicatif > 0
                    ? `${new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(gainsCeMois.brutIndicatif)} brut indicatif`
                    : null,
                ].filter(Boolean).join(' + ')} sur {gainsCeMois.nb} mission{gainsCeMois.nb > 1 ? 's' : ''}
              </p>
              <p className="text-xs text-primary mt-0.5">Voir le détail →</p>
            </div>
          </div>
          {(gainsCeMois.netSalarie > 0 || gainsCeMois.brutIndicatif > 0) && <NoteNetEstime className="mt-2" />}
        </button>
      )}

      {/* ═══ ZONE 3 : ALERTES & ADMIN (repoussées sous le contenu utile) ═══ */}

      {!activation.visible && soignant && (
        <div className="mb-4">
          <BandeauGraceDocuments
            premiereMissionLe={(soignant as any).premiere_mission_le}
            tousDocumentsValides={soignant.tous_documents_valides}
          />
        </div>
      )}
      {!activation.visible && (
        <BandeauCompletionProfil soignant={soignant as any} variant="compact" className="mb-4" />
      )}
      {/* Lot 6b.4 : la carte évaluation remplace la checklist quand celle-ci a
          disparu — jamais les deux (max UNE carte d'action système). */}
      {!activation.visible && <BandeauEvaluationsEnAttente role="SOIGNANT" />}

      {/* Les nudges paiement/mandat/RIB just-in-time sont ABSORBÉS par la
          checklist d'activation unique (étapes ③ mandat + ④ paiement). */}

      {soignantWithCounts.type_exercice !== 'LIBERAL' && <BandeauAlerte48h heuresSemaine={heuresSemaine} />}

      {soignantWithCounts.type_exercice === 'MIXTE' && !(soignantWithCounts as any).attestation_cumul_activite && (
        <div className="bg-warning/5 border-l-4 border-warning p-4 rounded-r-xl mb-4">
          <p className="text-sm text-warning font-medium mb-2">
            ⚠️ Cumul d'activité : tes heures sur Jolene doivent être compatibles avec ton contrat salarié.
          </p>
          <button
            onClick={() => navigate('/soignant/profil')}
            className="text-xs text-warning underline font-semibold"
          >
            Attester la compatibilité →
          </button>
        </div>
      )}

      {docsExpirant.map(d => (
        <div key={d.id} className="bg-destructive/5 border border-destructive/20 rounded-xl p-3 mb-3 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-destructive">
            ⏰ Votre {TYPES_DOCUMENTS[d.type_document] || d.type_document} expire dans {differenceInDays(new Date(d.valide_jusqua), new Date())} jour{differenceInDays(new Date(d.valide_jusqua), new Date()) > 1 ? 's' : ''}.{' '}
            <button onClick={() => navigate('/soignant/documents')} className="text-primary font-medium hover:underline">Mettre à jour →</button>
          </p>
        </div>
      ))}

      {/* §7.2 Lot 7a — parrainage « présent sans polluer » : carte discrète en
          BAS d'Accueil (niveau 2 de l'architecture §5). Le banner permanent de
          Revenus a été retiré — cet écran-là a un seul job, la confiance paiement. */}
      <button
        type="button"
        onClick={() => navigate('/soignant/parrainage')}
        className="w-full mt-2 mb-4 rounded-xl border border-border/60 bg-card/50 px-4 py-3 flex items-center justify-between gap-3 text-left hover:border-jolene-rose-200 transition-colors min-h-[44px]"
      >
        <span className="text-sm text-muted-foreground">🎁 Parraine un collègue — une prime pour chacun</span>
        <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" aria-hidden="true" />
      </button>

    </LayoutApp>
  );
}

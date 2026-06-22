import React, { useState, useMemo, useEffect, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useQuery } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { CheckCircle, Star, Clock, ShieldCheck, ShieldAlert, Search, Info, X, AlertCircle, Banknote, Rocket, MapPin, Bell, TrendingUp, Activity, GraduationCap, Home, CalendarDays, CreditCard, FileText, Sparkles } from 'lucide-react';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { CarteProposition } from '@/components/CarteProposition';
import { estEligibleLiberal, getRegleInstallation } from '@/lib/regles-installation-liberal';
import { RappelsFiscaux } from '@/components/RappelsFiscaux';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { WidgetAllerPointer } from '@/components/WidgetAllerPointer';
import { BandeauOubliDepart } from '@/components/BandeauOubliDepart';
import { BadgeNiveau } from '@/components/BadgeNiveau';
import { BandeauGoalGradient, CelebrationJalonManager } from '@/components/GoalGradient';
import { LayoutApp } from '@/components/LayoutApp';
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { EmptyState, IllustrationTirelire } from '@/components/ui/EmptyState';
import { JaugeProgression } from '@/components/JaugeProgression';
import { ChecklistActivation, useActivationSoignant } from '@/components/dashboard/ChecklistActivation';
import type { SoignantActivation, DocumentActivation } from '@/components/dashboard/ChecklistActivation';
import { BandeauCompletionProfil } from '@/components/profil-soignant/BandeauCompletionProfil';
import { BadgeStatut } from '@/components/BadgeStatut';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';
import { BandeauAlerte48h } from '@/components/BandeauAlerte48h';
import { BandeauGraceDocuments } from '@/components/BandeauGraceDocuments';
const GraphiqueGains6Mois = lazy(() =>
  import('@/components/GraphiqueGains6Mois').then(m => ({ default: m.GraphiqueGains6Mois }))
);
import { ProgressionCirculaire3200h } from '@/components/ProgressionCirculaire3200h';
import { ProchainBadgeWidget } from '@/components/ProchainBadgeWidget';
import { CalendrierMiniSemaine } from '@/components/CalendrierMiniSemaine';
import { CalendrierTogglable } from '@/components/dashboard/CalendrierTogglable';
import { BannerEncourageNotation } from '@/components/BannerEncourageNotation';
import { SuggestionsMissions } from '@/components/dashboard/SuggestionsMissions';
import { TopEtablissements } from '@/components/dashboard/TopEtablissements';
import { GraphiqueRepartitionHeures } from '@/components/dashboard/GraphiqueRepartitionHeures';
import { JaugeSpeedometer } from '@/components/JaugeSpeedometer';
import { BoutonAjouterCalendrier } from '@/components/SyncCalendrier';
import { SectionErrorBoundary } from '@/components/SectionErrorBoundary';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { getLabelProfession } from '@/lib/constantes';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import type { BadgeStats } from '@/components/BadgesGamification';
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

export default function DashboardSoignant() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [propositions, setPropositions] = useState<any[]>([]);

  const { data: dashboard, isLoading } = useQuery({
    queryKey: ['dashboard-soignant', user?.id],
    queryFn: async () => {
      const { data } = await supabase.rpc('fn_dashboard_soignant_complet' as any);
      if (!data) return { profil: null, missions_ouvertes: [], mes_missions: [], documents: [], heures_semaine: 0, gains_mois: { net_total: 0, brut_total: 0, nb_missions: 0 }, gains_6mois: [], missions_semaine_cal: [], propositions: [], heures_totales_terminees: 0, missions_oubliees_count: 0, notifs_non_lues: 0, hasStripeConnect: true };

      // Vérifier Stripe Connect
      const { data: connectData } = await supabase.from('stripe_connect_onboarding').select('statut').eq('soignant_id', user!.id).maybeSingle();

      return { ...data, hasStripeConnect: connectData?.statut === 'COMPLET' };
    },
    staleTime: 60_000,
    enabled: !!user,
  });

  // Keep propositions in local state so they can be removed on action
  const dashboardPropositions = dashboard?.propositions;
  useEffect(() => {
    if (dashboardPropositions) setPropositions(dashboardPropositions);
  }, [dashboardPropositions]);

  // Derive all values from the dashboard RPC response
  const soignant = dashboard?.profil as SoignantData | undefined ?? null;
  const missions = (dashboard?.missions_ouvertes ?? []) as any[];
  const mesMissions = (dashboard?.mes_missions ?? []) as any[];
  const gains6Mois = (dashboard?.gains_6mois ?? []) as { debut_le: string; net_a_payer: number | null }[];
  const missionsSemaine = (dashboard?.missions_semaine_cal ?? []) as { debut_le: string; statut: string }[];
  const heuresSemaine = (dashboard?.heures_semaine ?? 0) as number;
  const hasStripeConnect = dashboard?.hasStripeConnect ?? true;
  const hasMandatFacturation = !!(soignant as any)?.mandat_facturation_signe;
  const missionsWeekend = (dashboard?.missions_weekend ?? []) as any[];

  const docsExpirant = useMemo(() => {
    const docs = (dashboard?.documents ?? []) as any[];
    return docs.filter((d: any) =>
      d.valide_jusqua && d.statut_verification === 'VERIFIE' &&
      new Date(d.valide_jusqua) > new Date() &&
      differenceInDays(new Date(d.valide_jusqua), new Date()) < 30
    );
  }, [dashboard?.documents]);

  const missionProchaine = useMemo(() => {
    return (mesMissions as any[]).find((m: any) => {
      const mins = (new Date(m.debut_le).getTime() - Date.now()) / 60000;
      return mins > -30 && mins <= 60;
    }) || null;
  }, [mesMissions]);

  const missionsOubliDepart = useMemo(() => {
    const count = (dashboard?.missions_oubliees_count ?? 0) as number;
    // The RPC returns a count; if we need full mission objects, fall back to empty
    // For BandeauOubliDepart we need mission objects - kept as empty when only count available
    return count > 0 ? [{ id: 'oubli', count }] : [];
  }, [dashboard?.missions_oubliees_count]);

  const gainsCeMois = useMemo(() => {
    // RPC returns { net_total, brut_total, nb_missions } as an object
    const gm = (dashboard?.gains_mois ?? { net_total: 0, brut_total: 0, nb_missions: 0 }) as { net_total: number; brut_total: number; nb_missions: number };
    return { net: Number(gm.net_total) || 0, nb: Number(gm.nb_missions) || 0 };
  }, [dashboard?.gains_mois]);

  const { missionsTermineesCount, heuresCumuleesTotal } = useMemo(() => {
    // RPC returns heures_totales_terminees as a number (SUM of duree_heures)
    const heuresTotales = Number(dashboard?.heures_totales_terminees ?? 0);
    return {
      missionsTermineesCount: soignant?.total_missions_terminees ?? 0,
      heuresCumuleesTotal: Math.max(soignant?.heures_cumulees || 0, heuresTotales),
    };
  }, [dashboard?.heures_totales_terminees, soignant]);

  const badgeStats = useMemo<BadgeStats | null>(() => {
    return {
      missionsTerminees: missionsTermineesCount,
      scoreFiabilite: soignant?.score_fiabilite || 0,
      heuresCumulees: heuresCumuleesTotal,
      annulations: 0,
      missionsNuit: 0,
      missionsWeekend: 0,
      maxMissionsMemeEtab: 0,
      retards: 0,
      totalMissions: missionsTermineesCount,
    };
  }, [soignant, missionsTermineesCount, heuresCumuleesTotal]);

  // Override soignant counts with real computed values
  const emptySoignant = { prenom: '', nom: '', telephone: '', profession: null, rpps_verifie: false, adresse_lat: null, adresse_lng: null, tous_documents_valides: false, identite_verifiee: false, score_fiabilite: 0, total_missions_terminees: 0, heures_cumulees: 0, type_exercice: 'SALARIE' } as unknown as SoignantData;
  const soignantWithCounts = useMemo(() => ({
    ...(soignant ?? emptySoignant),
    total_missions_terminees: missionsTermineesCount,
    heures_cumulees: heuresCumuleesTotal,
  }) as SoignantData, [soignant, missionsTermineesCount, heuresCumuleesTotal]);

  // Session E-3 — checklist d'activation unique (remplace OnboardingGuide +
  // bandeaux concurrents tant que l'activation n'est pas complète).
  const activation = useActivationSoignant({
    soignant: soignant as unknown as SoignantActivation | null,
    documents: (dashboard?.documents ?? []) as DocumentActivation[],
    missionsActives: mesMissions.length,
  });

  if (isLoading) return <LayoutApp role="SOIGNANT"><SkeletonDashboard /></LayoutApp>;

  const missionsTerminees = soignantWithCounts?.total_missions_terminees ?? 0;
  const score = soignantWithCounts.score_fiabilite;
  const hasEvaluations = missionsTerminees > 0;
  const heures = soignantWithCounts.heures_cumulees ?? 0;
  const regleInstallation = soignantWithCounts.profession ? getRegleInstallation(soignantWithCounts.profession) : null;
  const seuilHeures = regleInstallation?.heures_requises ?? null;
  // Onglet "Parcours" (vers le libéral) : seulement pour les professions éligibles.
  const afficheParcours = !!(soignantWithCounts.profession && estEligibleLiberal(soignantWithCounts.profession));

  const aDocuments = !!(soignantWithCounts as any).tous_documents_valides;

  return (
    <LayoutApp role="SOIGNANT">
      {/* Checklist d'activation EN PREMIER pour un profil incomplet (elle se
          masque seule — return null — quand le profil est complet, donc aucun
          coût pour un soignant activé qui voit alors directement le CTA). */}
      <ChecklistActivation state={activation} className="mb-4" />

      {/* ═══ ZONE 1 : HERO + CTA (ce que le soignant voit en premier) ═══ */}

      {/* Header Y2K compact : mascotte + nom + chips gamification */}
      <div className="mb-4 flex items-start gap-4">
        <Mascotte
          etat={soignantWithCounts.tous_documents_valides ? 'happy' : 'thinking'}
          taille="md"
          className="shrink-0"
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-xl font-bold text-foreground">
              Hiii, <span className="text-gradient-hero">{soignantWithCounts.prenom}</span>
            </h1>
            <BadgeRPPS rppsVerifie={(soignantWithCounts as any).rpps_verifie} rpps={(soignantWithCounts as any).numero_rpps} profession={soignantWithCounts.profession} />
          </div>
          {!soignantWithCounts.tous_documents_valides ? (
            <p className="text-sm text-warning mt-1">Complétez votre profil pour postuler</p>
          ) : (
            <p className="text-sm text-muted-foreground mt-1">Prête à trouver votre prochaine mission ?</p>
          )}
        </div>
      </div>

      {/* CTA principal : la boucle de vente, en haut, pas dans un onglet */}
      <div className="flex gap-3 mb-6 overflow-x-auto pb-1">
        <BoutonY2K variant="primary" size="sm" onClick={() => navigate('/soignant/recherche-missions')} className="whitespace-nowrap flex-1">
          🔥 Trouver une mission
        </BoutonY2K>
        <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/mes-matches')} className="whitespace-nowrap flex-1" iconeGauche={<Sparkles className="h-4 w-4" />}>
          Mes matchs
        </BoutonY2K>
      </div>

      {/* ═══ ZONE 2 : CONTEXTE IMMÉDIAT (missions en cours / pointage) ═══ */}

      {missionsOubliDepart.map(m => (
        <BandeauOubliDepart key={m.id} mission={m} onPointer={() => navigate('/soignant/presences')} />
      ))}

      {missionProchaine && <WidgetAllerPointer mission={missionProchaine} />}

      {/* Missions proposées depuis le pool — opportunités urgentes */}
      <SectionErrorBoundary section="propositions">
      {propositions.length > 0 && (
        <div className="mb-6 rounded-xl border-2 border-orange-400 bg-orange-50/50 dark:bg-orange-950/10 dark:border-orange-600 p-4">
          <h2 className="text-base font-bold text-foreground flex items-center gap-2 mb-3">
            <Bell className="h-5 w-5 text-orange-500" /> 🚨 Missions proposées
          </h2>
          <div className="space-y-3">
            {propositions.map((p: any) => (
              <CarteProposition
                key={p.id}
                proposition={p}
                onTraitee={(id) => setPropositions(prev => prev.filter(x => x.id !== id))}
              />
            ))}
          </div>
        </div>
      )}
      </SectionErrorBoundary>

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
            {mesMissions.map((m: any) => (
              <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3">
                <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                  <span className="text-[10px] font-semibold text-primary uppercase">{format(new Date(m.debut_le), 'EEE', { locale: fr })}</span>
                  <span className="text-lg font-bold text-primary leading-tight">{format(new Date(m.debut_le), 'd')}</span>
                  <span className="text-[10px] text-primary">{format(new Date(m.debut_le), 'MMM', { locale: fr })}</span>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <BadgeStatut statut={m.statut} />
                    {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px]">🔥 Urgent</span>}
                  </div>
                  <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    🏥 {m.etablissements?.nom}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                  </p>
                  <div className="flex items-center gap-3 mt-0.5">
                    <p className="text-xs text-muted-foreground">
                      🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                    <BoutonAjouterCalendrier mission={m} />
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      </SectionErrorBoundary>

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
      <BandeauEvaluationsEnAttente role="SOIGNANT" />

      {!activation.visible && soignant && !aDocuments && (
        <div
          onClick={() => navigate('/soignant/mes-documents')}
          className="rounded-xl border border-warning/30 bg-warning/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-warning/50 transition-colors"
        >
          <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="font-semibold text-foreground">Documents requis</p>
            <p className="text-sm text-muted-foreground">
              Téléversez vos documents (CNI, diplôme, RC Pro) pour pouvoir candidater à toutes les missions.
            </p>
          </div>
          <span className="text-sm text-primary font-medium shrink-0">Aller au centre →</span>
        </div>
      )}

      {!hasStripeConnect && (soignantWithCounts as any)?.type_exercice !== 'SALARIE' && (
        <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-primary/50 transition-colors" onClick={() => navigate('/soignant/stripe-connect')}>
          <CreditCard className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <p className="font-semibold text-foreground">Activez votre compte de paiement</p>
            <p className="text-sm text-muted-foreground">Liez votre compte Stripe Connect pour recevoir vos paiements directement. Cela prend 5 minutes.</p>
          </div>
        </div>
      )}
      {((soignantWithCounts as any).type_exercice === 'LIBERAL' || (soignantWithCounts as any).type_exercice === 'MIXTE') && !hasMandatFacturation && (
        <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-warning/50 transition-colors" onClick={() => navigate('/soignant/mandat-facturation')}>
          <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
          <div>
            <p className="font-semibold text-foreground">Signez votre mandat de facturation</p>
            <p className="text-sm text-muted-foreground">Jolene pourra générer automatiquement vos factures d'honoraires et vous donner accès au paiement rapide (24-48h).</p>
          </div>
        </div>
      )}

      {soignantWithCounts.type_exercice !== 'LIBERAL' && <BandeauAlerte48h heuresSemaine={heuresSemaine} />}

      {soignantWithCounts.type_exercice === 'MIXTE' && !(soignantWithCounts as any).attestation_cumul_activite && (
        <div className="bg-warning/5 border-l-4 border-warning p-4 rounded-r-xl mb-4">
          <p className="text-sm text-warning font-medium mb-2">
            ⚠️ Cumul d'activité : vos heures sur Jolene doivent être compatibles avec votre contrat salarié.
          </p>
          <button
            onClick={() => navigate('/soignant/profil')}
            className="text-xs text-warning underline font-semibold"
          >
            Attester la compatibilité →
          </button>
        </div>
      )}

      <BandeauGoalGradient heures={heures} />
      <CelebrationJalonManager heures={heures} />

      {docsExpirant.map(d => (
        <div key={d.id} className="bg-destructive/5 border border-destructive/20 rounded-xl p-3 mb-3 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-destructive">
            ⏰ Votre {TYPES_DOCUMENTS[d.type_document] || d.type_document} expire dans {differenceInDays(new Date(d.valide_jusqua), new Date())} jours.{' '}
            <button onClick={() => navigate('/soignant/documents')} className="text-primary font-medium hover:underline">Mettre à jour →</button>
          </p>
        </div>
      ))}

      {/* ═══ ZONE 4 : ONGLETS DÉTAILLÉS (chiffres, activité, gains) ═══ */}
      <Tabs defaultValue="accueil" className="mb-6">
        <TabsList className={`w-full grid ${afficheParcours ? 'grid-cols-2 sm:grid-cols-4' : 'grid-cols-3'} mb-4`}>
          <TabsTrigger value="accueil" className="text-xs gap-1"><Home className="h-3.5 w-3.5 hidden sm:block" />Accueil</TabsTrigger>
          <TabsTrigger value="activite" className="text-xs gap-1"><Activity className="h-3.5 w-3.5 hidden sm:block" />Activité</TabsTrigger>
          <TabsTrigger value="gains" className="text-xs gap-1"><TrendingUp className="h-3.5 w-3.5 hidden sm:block" />Gains</TabsTrigger>
          {afficheParcours && (
            <TabsTrigger value="parcours" className="text-xs gap-1"><GraduationCap className="h-3.5 w-3.5 hidden sm:block" />Parcours</TabsTrigger>
          )}
        </TabsList>

        {/* ─── ONGLET ACCUEIL ─── */}
        <TabsContent value="accueil">
          <SectionErrorBoundary section="accueil">
          <BannerEncourageNotation role="SOIGNANT" />

          {/* Prochain badge à débloquer — gamification visible dès l'accueil */}
          {badgeStats && (
            <div className="mb-6">
              <FadeInView>
                <ProchainBadgeWidget stats={badgeStats} />
              </FadeInView>
            </div>
          )}

          <SuggestionsMissions />

          {/* Missions disponibles */}
          <div className="mb-6">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-foreground">Missions disponibles</h2>
              <button onClick={() => navigate('/soignant/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
            </div>
            {missions.length > 0 ? (
              <div className="space-y-3">
                {missions.map((m: any) => (
                  <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md transition-shadow cursor-pointer">
                    <div className="flex items-start justify-between mb-2">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          {m.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
                          <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">{m.etablissements?.nom} · {m.etablissements?.adresse_ville}</p>
                      </div>
                      <span className="text-primary font-bold text-sm whitespace-nowrap ml-2">{m.taux_horaire_base} €/h</span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(m.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState
                mascotte="thinking"
                titre="Aucune mission disponible pour le moment"
                description="Créez une alerte : on vous prévient dès qu'une mission est publiée dans votre zone."
                cta={{ label: '🔔 Créer une alerte', onClick: () => navigate('/soignant/recherche-missions?alerte=1') }}
              />
            )}
          </div>

          {/* « Mes missions en cours » supprimé (Session E-3) — doublon de
              « Mes prochaines missions » affiché avant les onglets. */}

          {/* Chiffres clés — secondaires, placés sous les missions/planning */}
          <h2 className="text-base font-bold text-foreground mb-3">Mes chiffres</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
            <FadeInView delay={0}>
              <CarteKPIY2K
                icone={<CheckCircle className="h-4 w-4" />}
                valeur={missionsTerminees}
                label="Missions terminées"
                variant="holographic"
                onClick={() => navigate('/soignant/historique-missions')}
              />
            </FadeInView>
            <FadeInView delay={100}>
              {hasEvaluations ? (
                <JaugeSpeedometer score={score ?? 50} onClick={() => navigate('/soignant/fiabilite')} />
              ) : (
                <div className="card-kpi flex flex-col items-center justify-center text-center cursor-pointer" onClick={() => navigate('/soignant/fiabilite')}>
                  <Star className="h-6 w-6 text-muted-foreground/40 mb-1" />
                  <p className="text-xs font-semibold text-muted-foreground">Pas encore d'évaluation</p>
                  <p className="text-[10px] text-muted-foreground/60 mt-0.5">Complétez votre 1ère mission</p>
                </div>
              )}
            </FadeInView>
            <FadeInView delay={200}>
              <CarteKPIY2K
                icone={<Clock className="h-4 w-4" />}
                valeur={`${heures}h`}
                label="Heures cumulées"
                contexte={seuilHeures ? `sur ${seuilHeures.toLocaleString('fr-FR')}h objectif` : undefined}
                variant="default"
                onClick={() => navigate(seuilHeures ? '/soignant/passer-en-liberal' : '/soignant/planning?tab=historique')}
              />
            </FadeInView>
            <FadeInView delay={300}>
              <CarteKPIY2K
                icone={<CalendarDays className="h-4 w-4" />}
                valeur={mesMissions.length}
                label="Planning"
                contexte="missions à venir"
                variant="default"
                onClick={() => navigate('/soignant/planning')}
              />
            </FadeInView>
          </div>

          {/* Teaser classement — concours amical, découverte de la page */}
          {missionsTerminees > 0 && (
            <div
              onClick={() => navigate('/soignant/classement')}
              className="card-base mb-6 cursor-pointer hover:shadow-md transition-all flex items-center gap-3"
            >
              <div className="rounded-xl p-2.5 bg-gradient-to-br from-jolene-rose-100 to-jolene-mauve-100 dark:from-jolene-rose-900/30 dark:to-jolene-mauve-900/30">
                <span className="text-xl">🏆</span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground">Classement des soignants</p>
                <p className="text-xs text-muted-foreground">Où en êtes-vous parmi les soignants Jolene cette semaine ?</p>
              </div>
              <span className="text-xs text-primary font-medium shrink-0">Voir →</span>
            </div>
          )}

          </SectionErrorBoundary>
        </TabsContent>

        {/* ─── ONGLET ACTIVITÉ ─── */}
        <TabsContent value="activite">
          <SectionErrorBoundary section="activite">
          {/* Calendrier semaine/mois (toggle persistant) */}
          <FadeInView>
            <CalendrierTogglable missionsSemaine={missionsSemaine} />
          </FadeInView>

          <TopEtablissements />

          {/* Compteur hebdomadaire */}
          <div className="mb-6">
            <CompteurHebdomadaire />
          </div>

          {/* Progression 3200h — IDE/IBODE/IADE uniquement
              (ProchainBadgeWidget remonté sur l'onglet Accueil — Session B) */}
          {regleInstallation?.categorie === 'AVEC_HEURES_IDE' && (
            <div className="mb-6">
              <FadeInView delay={0}>
                <ProgressionCirculaire3200h heures={heures} />
              </FadeInView>
            </div>
          )}

          {/* Missions weekend */}
          {missionsWeekend.length > 0 && (
            <div className="mb-6">
              <div className="flex items-center justify-between mb-3">
                <h2 className="text-lg font-bold text-foreground flex items-center gap-2">
                  <MapPin className="h-5 w-5 text-primary" /> Missions ce week-end
                </h2>
                <button onClick={() => navigate('/soignant/recherche-missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
              </div>
              <div className="space-y-3">
                {missionsWeekend.map((m: any) => (
                  <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md transition-shadow cursor-pointer">
                    <div className="flex items-start justify-between mb-2">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          {m.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
                          <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">{m.etablissements?.nom} · {m.etablissements?.adresse_ville}</p>
                      </div>
                      <span className="text-primary font-bold text-sm whitespace-nowrap ml-2">{m.taux_horaire_base} €/h</span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {format(new Date(m.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}
          </SectionErrorBoundary>
        </TabsContent>

        {/* ─── ONGLET GAINS ─── */}
        <TabsContent value="gains">
          <SectionErrorBoundary section="gains">
          {/* Graphique gains 6 mois */}
          <FadeInView>
            {gains6Mois.length > 0 ? (
              <Suspense fallback={<div className="h-64 animate-pulse bg-muted rounded-lg" />}>
                <GraphiqueGains6Mois missions={gains6Mois} />
              </Suspense>
            ) : (
              <div className="mb-6">
                <EmptyState illustration={<IllustrationTirelire />} titre="Pas encore de gains" description="Vos gains apparaîtront ici après votre première mission terminée." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
              </div>
            )}
          </FadeInView>

          <GraphiqueRepartitionHeures />

          {/* Gains ce mois */}
          {gainsCeMois.nb > 0 && (
            <div className="card-base mb-6 cursor-pointer hover:shadow-md transition-all" onClick={() => navigate('/soignant/mes-gains')}>
              <div className="flex items-center gap-3">
                <div className="rounded-xl p-2.5 bg-primary/10"><Banknote className="h-5 w-5 text-primary" /></div>
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">💰 Ce mois : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(gainsCeMois.net)} net estimé* sur {gainsCeMois.nb} mission{gainsCeMois.nb > 1 ? 's' : ''}</p>
                  <p className="text-xs text-primary mt-0.5">Voir le détail →</p>
                </div>
              </div>
            </div>
          )}

          {/* Rappels fiscaux libéral (LIBERAL ou MIXTE) */}
          {((soignantWithCounts as any).type_exercice === 'LIBERAL' || (soignantWithCounts as any).type_exercice === 'MIXTE') && (
            <RappelsFiscaux />
          )}
          </SectionErrorBoundary>
        </TabsContent>

        {/* ─── ONGLET PARCOURS ─── (professions éligibles libéral uniquement) */}
        {afficheParcours && (
        <TabsContent value="parcours">
          <SectionErrorBoundary section="parcours">
          {soignantWithCounts.type_exercice === 'LIBERAL' ? (
            <div className="rounded-2xl bg-success/5 border border-success/20 p-6 text-center">
              <div className="flex items-center justify-center mb-3">
                <div className="rounded-full bg-success/10 p-3">
                  <CheckCircle className="h-8 w-8 text-success" />
                </div>
              </div>
              <h2 className="text-base font-bold text-foreground mb-1">Vous exercez déjà en libéral</h2>
              <p className="text-sm text-muted-foreground">Votre statut libéral est actif. Bénéficiez de tous les avantages de votre indépendance professionnelle.</p>
              <button onClick={() => navigate('/soignant/profil')} className="mt-4 text-sm text-primary font-semibold hover:underline">
                Gérer mon profil libéral →
              </button>
            </div>
          ) : soignantWithCounts.profession && estEligibleLiberal(soignantWithCounts.profession) ? (
            <div className="space-y-4">
              <div className="rounded-2xl bg-gradient-to-r from-rose-light to-rose/5 dark:from-rose/10 dark:to-rose/5 border border-rose/20 p-4 md:p-6 cursor-pointer" onClick={() => navigate('/soignant/parcours-3200h')}>
                <div className="flex items-center justify-between mb-1">
                  <h2 className="text-base font-bold text-foreground">Mon parcours vers le libéral</h2>
                  <span className="text-xs text-rose font-medium">Détails →</span>
                </div>
                <p className="text-xs text-muted-foreground mb-4">Objectif : 3 200 heures d'exercice</p>
                <JaugeProgression valeur={heures} max={3200} marqueurs={[800, 1600, 2400, 3200]} couleurBarre="bg-gradient-to-r from-rose to-primary" couleurFond="bg-rose/10" />
                <div className="flex justify-between text-[10px] text-muted-foreground mt-1.5"><span>0h</span><span>800h</span><span>1600h</span><span>2400h</span><span>3200h</span></div>
                <p className="text-sm font-semibold text-foreground mt-3"><span className="text-rose">{heures}h</span> / 3 200h</p>
              </div>

              {(() => {
                if ((soignantWithCounts as any).statut_liberal === 'ACTIF') return null;
                // Sans heures requises (médecin, sage-femme, orthophoniste...) : toujours afficher
                // Avec heures requises (IDE 3200, KINE 2240) : afficher dès 25% du seuil
                const seuil = regleInstallation?.heures_requises;
                const seuilAtteint = !seuil || heures >= seuil * 0.25;
                if (!seuilAtteint) return null;
                return (
                  <div className="rounded-2xl bg-gradient-to-r from-rose/5 to-rose-light dark:to-rose/10 border border-rose/20 p-4 cursor-pointer hover:shadow-md transition-all" onClick={() => navigate('/soignant/passer-en-liberal')}>
                    <div className="flex items-center gap-3">
                      <div className="rounded-xl p-2.5 bg-primary/10"><Rocket className="h-5 w-5 text-primary" /></div>
                      <div>
                        <p className="text-sm font-bold text-foreground">🎉 Passer en libéral</p>
                        <p className="text-xs text-muted-foreground">Vous êtes éligible ! Découvrez le module Free Transition.</p>
                        <p className="text-xs text-primary mt-0.5">Commencer →</p>
                      </div>
                    </div>
                  </div>
                );
              })()}

              {/* Prévoyance CTA */}
              {!(soignantWithCounts as any).prevoyance_inscrit && (
                <div className="rounded-2xl bg-gradient-to-r from-rose-light to-rose/5 dark:from-rose/10 dark:to-rose/5 border border-rose/20 p-4 cursor-pointer" onClick={() => navigate('/soignant/prevoyance')}>
                  <h3 className="text-sm font-bold text-foreground mb-1">🛡️ Protégez-vous avec la Prévoyance Jolene</h3>
                  <p className="text-xs text-muted-foreground mb-2">Assurance santé subventionnée jusqu'à 30%. Bonus : +3 points de fiabilité.</p>
                  <span className="text-xs text-primary font-medium">Découvrir les plans →</span>
                </div>
              )}
            </div>
          ) : soignantWithCounts.profession ? (
            <div className="card-base text-center py-8">
              <p className="text-sm text-muted-foreground">
                Votre profession ({getLabelProfession(soignantWithCounts.profession)}) n'est pas éligible à l'exercice libéral via Jolene.
              </p>
            </div>
          ) : (
            <div className="card-base text-center py-8">
              <p className="text-sm text-muted-foreground">
                Vérifiez votre RPPS pour débloquer votre parcours professionnel.
              </p>
              <BoutonY2K variant="primary" size="sm" onClick={() => navigate('/soignant/profil')} className="mt-3">
                Compléter mon profil
              </BoutonY2K>
            </div>
          )}
          </SectionErrorBoundary>
        </TabsContent>
        )}
      </Tabs>
    </LayoutApp>
  );
}

import React, { useState, useMemo, useEffect, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Link, useNavigate } from 'react-router-dom';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { AlertCircle, Banknote, Bell, CalendarDays, ChevronRight, CreditCard, FileText, Sparkles } from 'lucide-react';
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
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { hapticNotification } from '@/lib/haptics';
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

export default function DashboardSoignant() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user } = useAuth();
  // 7f : consomme le code parrainage capté (?ref=/?parrain=) à la 1ʳᵉ session.
  useAppliquerParrainage(user?.id);
  const [propositions, setPropositions] = useState<PropositionMission[]>([]);
  // Postuler 1-tap depuis l'accueil : mission_id → candidature_id (pour l'undo).
  const [candidatingId, setCandidatingId] = useState<string | null>(null);
  const [postulees, setPostulees] = useState<Record<string, string>>({});

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
    if (Array.isArray(dashboardPropositions)) {
      setPropositions(dashboardPropositions as PropositionMission[]);
    }
  }, [dashboardPropositions]);
  const retirerPropositionTraitee = useCallback((id: string) => {
    setPropositions(prev => prev.filter(proposition => proposition.id !== id));
  }, []);

  // Derive all values from the dashboard RPC response
  const soignant = dashboard?.profil as SoignantData | undefined ?? null;
  const mesMissions = (dashboard?.mes_missions ?? []) as any[];
  // Lot 1 — opportunités à montrer en page d'accueil (valeur avant l'effort).
  const missionsOuvertes = (dashboard?.missions_ouvertes ?? []) as any[];
  const heuresSemaine = (dashboard?.heures_semaine ?? 0) as number;
  const hasStripeConnect = dashboard?.hasStripeConnect ?? true;

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

  const missionsOubliDepartCount = Math.max(0, Number(dashboard?.missions_oubliees_count) || 0);

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

  // Override soignant counts with real computed values
  const emptySoignant = { prenom: '', nom: '', telephone: '', profession: null, rpps_verifie: false, adresse_lat: null, adresse_lng: null, tous_documents_valides: false, identite_verifiee: false, score_fiabilite: 0, total_missions_terminees: 0, heures_cumulees: 0, type_exercice: 'SALARIE' } as unknown as SoignantData;
  const soignantWithCounts = useMemo(() => ({
    ...(soignant ?? emptySoignant),
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

  // Postuler directement depuis la carte d'accueil (funnel candidature). Feedback
  // inline immédiat + annulation « dans la foulée » (fn_retirer_candidature) sans
  // page de confirmation. Si la mission exige un choix de contrat → on bascule sur
  // le détail (le dialogue de choix y vit déjà).
  const retirerCandidature = async (missionId: string, candidatureId: string) => {
    const { data, error } = await supabase.rpc('fn_retirer_candidature' as any, { p_candidature_id: candidatureId });
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error ?? error?.message ?? 'Retrait impossible');
      return;
    }
    setPostulees(prev => { const n = { ...prev }; delete n[missionId]; return n; });
    toast.success('Candidature retirée');
  };

  const postulerDepuisAccueil = async (m: any) => {
    if (candidatingId) return;
    setCandidatingId(m.id);
    const { data, error } = await supabase.rpc('fn_postuler_mission_rate_limited' as any, {
      p_mission_id: m.id,
      p_message: "Candidature rapide depuis l'accueil",
      p_choix_contrat: null,
    });
    setCandidatingId(null);
    if (error) { toast.error(error.message); return; }
    const r = data as any;
    if (r?.choix_requis) {
      toast('Choisis ton type de contrat pour postuler');
      navigate(`/soignant/missions/${m.id}`);
      return;
    }
    if (r?.success || r?.candidature_id) {
      const candId = (r.candidature_id as string | undefined) ?? '';
      setPostulees(prev => ({ ...prev, [m.id]: candId }));
      void hapticNotification('success');
      toast.success('Candidature envoyée ✓', candId ? {
        action: { label: 'Annuler', onClick: () => retirerCandidature(m.id, candId) },
        duration: 8000,
      } : undefined);
    } else {
      toast.error(r?.error ?? 'Candidature impossible');
    }
  };

  if (isLoading) return <LayoutApp role="SOIGNANT"><SkeletonDashboard /></LayoutApp>;


  return (
    <LayoutApp role="SOIGNANT">
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
                ? `${missionsOuvertes.length} mission${missionsOuvertes.length > 1 ? 's' : ''} pour toi aujourd'hui 🔥`
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
            {mesMissions.map((m: any) => (
              <div key={m.id} className="card-base hover:shadow-md transition-all flex items-center gap-3 py-3">
                <Link
                  to={`/soignant/missions/${m.id}`}
                  className="flex flex-1 min-w-0 items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                  aria-label={`Voir la mission ${m.intitule}`}
                >
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
                      🏥 {m.etablissements?.nom || 'Établissement'}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                    </p>
                    <div className="flex items-center gap-3 mt-0.5">
                      <p className="text-xs text-muted-foreground">
                        🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                      </p>
                    </div>
                  </div>
                </Link>
                <BoutonAjouterCalendrier mission={m} />
              </div>
            ))}
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
              const duree = Number(m.duree_heures) > 0 ? Number(m.duree_heures) : 0;
              const netDirect = Number(m.net_estime ?? m.net_a_payer);
              const brutDirect = Number(m.total_brut ?? m.brut_estime);
              const estimation = Number.isFinite(netDirect) && netDirect > 0
                ? { montant: Math.round(netDirect), libelle: 'net' }
                : Number.isFinite(brutDirect) && brutDirect > 0
                  ? { montant: Math.round(brutDirect), libelle: 'brut' }
                  : m.taux_horaire_base && duree
                    ? { montant: Math.round(Number(m.taux_horaire_base) * duree), libelle: 'brut' }
                    : null;
              return (
                <div key={m.id} className="card-base hover:shadow-md transition-all flex items-center gap-3 py-3">
                  <Link
                    to={`/soignant/missions/${m.id}`}
                    className="flex flex-1 min-w-0 items-center gap-3 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    aria-label={`Voir la mission ${m.intitule}`}
                  >
                    <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                      <span className="text-[10px] font-semibold text-primary uppercase">{format(new Date(m.debut_le), 'EEE', { locale: fr })}</span>
                      <span className="text-lg font-bold text-primary leading-tight">{format(new Date(m.debut_le), 'd')}</span>
                      <span className="text-[10px] text-primary">{format(new Date(m.debut_le), 'MMM', { locale: fr })}</span>
                    </div>
                    <div className="flex-1 min-w-0">
                      {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px] mb-0.5 inline-block">🔥 Urgent</span>}
                      <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                      <p className="text-xs text-muted-foreground mt-0.5 truncate">🏥 {m.etab_nom || 'Établissement'}{m.service ? ` · ${m.service}` : ''}</p>
                      <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                        <span>🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}</span>
                        {m.taux_horaire_base && <span className="font-semibold text-primary">{m.taux_horaire_base} €/h</span>}
                        {estimation && <span>~{estimation.montant} € {estimation.libelle}</span>}
                      </div>
                    </div>
                  </Link>
                  {m.id in postulees ? (
                    <div className="shrink-0 flex flex-col items-end gap-0.5">
                      <span className="text-xs font-semibold text-success inline-flex items-center gap-1">✓ Envoyée</span>
                      {postulees[m.id] && (
                        <button onClick={() => retirerCandidature(m.id, postulees[m.id])} className="text-[10px] text-muted-foreground hover:text-destructive hover:underline">Annuler</button>
                      )}
                    </div>
                  ) : (
                    <BoutonY2K size="sm" variant="primary" className="shrink-0" loading={candidatingId === m.id} disabled={candidatingId === m.id} onClick={(e: React.MouseEvent) => { e.stopPropagation(); postulerDepuisAccueil(m); }}>
                      Postuler
                    </BoutonY2K>
                  )}
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
              <p className="text-sm font-semibold text-foreground">💰 Ce mois : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(gainsCeMois.net)} net estimé* sur {gainsCeMois.nb} mission{gainsCeMois.nb > 1 ? 's' : ''}</p>
              <p className="text-xs text-primary mt-0.5">Voir le détail →</p>
            </div>
          </div>
          <NoteNetEstime className="mt-2" />
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

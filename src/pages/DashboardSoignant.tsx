import React, { useState, useMemo, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { AlertCircle, Banknote, Bell, CalendarDays, CreditCard, FileText, Sparkles } from 'lucide-react';
import { CarteProposition } from '@/components/CarteProposition';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { WidgetAllerPointer } from '@/components/WidgetAllerPointer';
import { BandeauOubliDepart } from '@/components/BandeauOubliDepart';
import { LayoutApp } from '@/components/LayoutApp';
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { ChecklistActivation, useActivationSoignant } from '@/components/dashboard/ChecklistActivation';
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
  const mesMissions = (dashboard?.mes_missions ?? []) as any[];
  // Lot 1 — opportunités à montrer en page d'accueil (valeur avant l'effort).
  const missionsOuvertes = (dashboard?.missions_ouvertes ?? []) as any[];
  const heuresSemaine = (dashboard?.heures_semaine ?? 0) as number;
  const hasStripeConnect = dashboard?.hasStripeConnect ?? true;
  const hasMandatFacturation = !!(soignant as any)?.mandat_facturation_signe;

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
  });

  // Moyen de paiement prêt ? (pour le nudge paiement just-in-time, après la 1ʳᵉ
  // mission terminée). Libéral : Stripe OU RIB + mandat ; salarié : RIB.
  const aRib = (dashboard?.documents ?? []).some(
    (d: any) => d.type_document === 'RIB' && d.statut_verification !== 'REJETE',
  );
  const estLiberalPaie =
    (soignant as any)?.type_exercice === 'LIBERAL' || (soignant as any)?.type_exercice === 'MIXTE';
  const moyenPaiementPret = estLiberalPaie
    ? (hasStripeConnect || aRib) && hasMandatFacturation
    : aRib;

  if (isLoading) return <LayoutApp role="SOIGNANT"><SkeletonDashboard /></LayoutApp>;

  const missionsTerminees = soignantWithCounts?.total_missions_terminees ?? 0;

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

      {/* CTA principal : la boucle de vente, en haut, pas dans un onglet */}
      <div className="flex gap-3 mb-3 overflow-x-auto pb-1">
        <BoutonY2K variant="primary" size="sm" onClick={() => navigate('/soignant/recherche-missions')} className="whitespace-nowrap flex-1">
          🔥 Trouver une mission
        </BoutonY2K>
        <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/missions')} className="whitespace-nowrap flex-1" iconeGauche={<Sparkles className="h-4 w-4" />}>
          Mes missions
        </BoutonY2K>
      </div>

      {/* ═══ ZONE 2 : CONTEXTE IMMÉDIAT (missions en cours / pointage) ═══ */}

      {missionsOubliDepart.map(m => (
        <BandeauOubliDepart key={m.id} mission={m} onPointer={() => navigate('/soignant/presences')} />
      ))}

      {missionProchaine && <WidgetAllerPointer mission={missionProchaine} />}

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
              const duree = m.fin_le && m.debut_le ? (new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime()) / 3600000 : 0;
              const brutEstime = m.taux_horaire_base && duree ? Math.round(m.taux_horaire_base * duree) : null;
              return (
                <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3">
                  <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                    <span className="text-[10px] font-semibold text-primary uppercase">{format(new Date(m.debut_le), 'EEE', { locale: fr })}</span>
                    <span className="text-lg font-bold text-primary leading-tight">{format(new Date(m.debut_le), 'd')}</span>
                    <span className="text-[10px] text-primary">{format(new Date(m.debut_le), 'MMM', { locale: fr })}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px] mb-0.5 inline-block">🔥 Urgent</span>}
                    <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-0.5 truncate">🏥 {m.etab_nom}{m.service ? ` · ${m.service}` : ''}</p>
                    <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                      <span>🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}</span>
                      {m.taux_horaire_base && <span className="font-semibold text-primary">{m.taux_horaire_base} €/h</span>}
                      {brutEstime && <span>~{brutEstime} € brut</span>}
                    </div>
                  </div>
                  <BoutonY2K size="sm" variant="primary" className="shrink-0" onClick={(e: React.MouseEvent) => { e.stopPropagation(); navigate(`/soignant/missions/${m.id}`); }}>
                    Postuler
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

      {/* Tes revenus du mois — déplacé hors des onglets (Accueil linéaire) */}
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

      {/* Nudge paiement JUST-IN-TIME : seulement après la 1ʳᵉ mission terminée et
          si le moyen de paiement n'est pas prêt — pour que les fonds soient
          libérables sans attente. Avant la 1ʳᵉ mission terminée : aucun nudge. */}
      {missionsTerminees >= 1 && !moyenPaiementPret && (
        estLiberalPaie ? (
          !hasMandatFacturation ? (
            <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-warning/50 transition-colors" onClick={() => navigate('/soignant/mandat-facturation')}>
              <FileText className="h-5 w-5 text-warning shrink-0 mt-0.5" />
              <div className="flex-1">
                <p className="font-semibold text-foreground">Signe ton mandat de facturation</p>
                <p className="text-sm text-muted-foreground">Indispensable pour que Jolene émette tes factures d'honoraires et débloque ton paiement (24-48 h).</p>
              </div>
              <span className="text-sm text-primary font-medium shrink-0">Signer →</span>
            </div>
          ) : (
            <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-primary/50 transition-colors" onClick={() => navigate('/soignant/stripe-connect')}>
              <CreditCard className="h-5 w-5 text-primary shrink-0 mt-0.5" />
              <div className="flex-1">
                <p className="font-semibold text-foreground">Reçois ton paiement</p>
                <p className="text-sm text-muted-foreground">Connecte Stripe pour être payé·e en 24-48 h (recommandé), ou ajoute un RIB pour un virement de l'établissement.</p>
              </div>
              <span className="text-sm text-primary font-medium shrink-0">Activer →</span>
            </div>
          )
        ) : (
          <div className="rounded-xl border-2 border-primary/30 bg-primary/5 p-4 mb-4 flex items-start gap-3 cursor-pointer hover:border-primary/50 transition-colors" onClick={() => navigate('/soignant/mes-documents')}>
            <Banknote className="h-5 w-5 text-primary shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Ajoute ton RIB</p>
              <p className="text-sm text-muted-foreground">Pour que l'établissement puisse te verser ta rémunération. Une photo suffit.</p>
            </div>
            <span className="text-sm text-primary font-medium shrink-0">Ajouter →</span>
          </div>
        )
      )}

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

    </LayoutApp>
  );
}

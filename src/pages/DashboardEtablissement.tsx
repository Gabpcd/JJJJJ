import React, { useState, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { logger } from '@/lib/logger';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, ClipboardList, FileText, Users, ClipboardCheck, ShieldAlert, CreditCard, BarChart3, ChevronDown, AlertTriangle, Timer, Scale, MessageCircle, Clock, type LucideIcon } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { CarteMission } from '@/components/CarteMission';
import { ModalConfirmation } from '@/components/ModalConfirmation';
// Sprint 8 ter-G PR 2 — lazy load modale annulation (code splitting)
const ModaleAnnulationMissionEtab = lazy(() =>
  import('@/components/etablissement/ModaleAnnulationMissionEtab').then((m) => ({
    default: m.ModaleAnnulationMissionEtab,
  })),
);
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { BandeauBlocageAuto } from '@/components/BandeauBlocageAuto';

import { BadgePalier } from '@/components/BadgePalier';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K } from '@/components/y2k/CardY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

import { TopSoignants } from '@/components/dashboard/TopSoignants';
import { SectionPlanning } from '@/components/dashboard/SectionPlanning';
import { GraphiqueEvolutionMissions } from '@/components/dashboard/GraphiqueEvolutionMissions';
import { CarteBFAInfo } from '@/components/dashboard/CarteBFAInfo';
import { IndicateursAvancesEtab } from '@/components/dashboard/IndicateursAvancesEtab';
import { CardScoreQualiteEtab } from '@/components/dashboard/CardScoreQualiteEtab';


export default function DashboardEtablissement() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  interface EtabInfo {
    nom: string;
    paliers_commission?: { nom: string } | null;
    taux_commission_negocie?: number | null;
    groupes_sante?: { nom: string } | null;
    groupe_sante_id?: string | null;
    peut_publier_missions?: boolean;
    bloque_auto_le?: string | null;
    bloque_auto_raisons?: {
      paiements_retard_nb?: number;
      paiements_retard_montant?: number;
      factures_retard_nb?: number;
      factures_retard_montant?: number;
      seuil_jours?: number;
    } | null;
  }
  interface MissionSummary {
    id: string;
    intitule: string;
    statut: string;
    soignant_assigne_id?: string | null;
    soignants?: Record<string, unknown> | null;
    [key: string]: unknown;
  }
  interface DashboardStats {
    missions_ouvertes: number;
    missions_assignees: number;
    missions_en_cours: number;
    missions_terminees: number;
    candidatures_en_attente: number;
    candidatures_recentes: Array<{ candidature_id: string; mission_id: string; soignant_nom: string; mission_intitule: string }>;
    missions_assignees_detail: Array<{ mission_id: string; intitule: string; soignant_nom: string; debut_le?: string }>;
    pool_urgence_count: number;
    messages_non_lus: number;
    missions_a_payer: number;
    missions_terminees_ce_mois: number;
    soignants_ce_mois: number;
    commissions_impayees: number;
    nb_factures_impayees: number;
    litiges_ouverts: number;
  }
  interface PalierCommission {
    id: string;
    nom: string;
    missions_min: number;
    missions_max: number;
    ordre: number;
  }

  const [modalDupliquer, setModalDupliquer] = useState<MissionSummary | null>(null);
  const [modalAnnuler, setModalAnnuler] = useState<MissionSummary | null>(null);
  // Densité dashboard : les stats détaillées (analytics) sont repliées par
  // défaut pour garder la vue par défaut focalisée sur l'action.
  const [statsOuvertes, setStatsOuvertes] = useState(false);

  const { data: dashData, isLoading: loading } = useQuery({
    queryKey: ['dashboard-etablissement', user?.id, etablissementId],
    queryFn: async () => {
      let partialError = false;
      const now = new Date();
      const debutMois = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

      let etabResult: EtabInfo | null = null;
      let missionsResult: MissionSummary[] = [];
      let aDejaPublieResult: boolean | null = null;
      let paliersResult: PalierCommission[] = [];
      let statsResult: DashboardStats = {
        missions_ouvertes: 0, missions_assignees: 0, missions_en_cours: 0, missions_terminees: 0,
        candidatures_en_attente: 0, candidatures_recentes: [], missions_assignees_detail: [],
        pool_urgence_count: 0, messages_non_lus: 0, missions_a_payer: 0,
        missions_terminees_ce_mois: 0, soignants_ce_mois: 0, commissions_impayees: 0,
        nb_factures_impayees: 0, litiges_ouverts: 0,
      };
      let topSoignantsResult: any[] = [];
      let prochainesResult: any[] = [];

      try {
        // Primary data: RPC stats + etab + recent missions + paliers
        const [resEtab, resMissions, resPaliers, resDashStats, resSoignants] = await Promise.all([
          supabase.rpc('fn_mon_etablissement_complet' as any),
          supabase.from('missions')
            .select('id, intitule, description, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer, statut, est_urgente, niveau_urgence, soignant_assigne_id, cree_le')
            .eq('etablissement_id', etablissementId)
            .order('cree_le', { ascending: false })
            .limit(5),
          supabase.from('paliers_commission').select('id, nom, missions_min, missions_max, ordre').eq('est_actif', true).order('ordre', { ascending: true }),
          supabase.rpc('fn_stats_dashboard_etablissement' as any),
          supabase.rpc('fn_mes_soignants_etablissement'),
        ]);

        if (resEtab.error) { logger.error('[DashboardEtab] Erreur établissement', resEtab.error); partialError = true; }
        else if (resEtab.data) etabResult = resEtab.data;

        // Build soignant map
        const sgMap: Record<string, any> = {};
        if (Array.isArray(resSoignants.data)) {
          for (const s of resSoignants.data) sgMap[s.id] = s;
        }
        if (Object.keys(sgMap).length === 0 && resMissions.data) {
          const sgIds = [...new Set((resMissions.data as any[]).map((m: any) => m.soignant_assigne_id).filter(Boolean))];
          if (sgIds.length > 0) {
            const { data: sgDirect } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite, numero_rpps').in('id', sgIds);
            if (sgDirect) for (const s of sgDirect) sgMap[s.id] = s;
          }
        }

        if (resMissions.error) { logger.error('[DashboardEtab] Erreur missions', resMissions.error); partialError = true; }
        if (resMissions.data) {
          missionsResult = resMissions.data.map((m: any) => ({
            ...m,
            soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null,
          }));
          aDejaPublieResult = resMissions.data.length > 0;
        }

        if (resPaliers.data) paliersResult = resPaliers.data;

        // Dashboard stats RPC — single source of truth for all KPIs
        if (resDashStats.data) {
          const d = resDashStats.data;
          statsResult = {
            missions_ouvertes: d.missions_ouvertes ?? 0,
            missions_assignees: d.missions_assignees ?? 0,
            missions_en_cours: d.missions_en_cours ?? 0,
            missions_terminees: d.missions_terminees ?? 0,
            candidatures_en_attente: d.candidatures_en_attente ?? 0,
            candidatures_recentes: d.candidatures_recentes ?? [],
            missions_assignees_detail: d.missions_assignees_detail ?? [],
            pool_urgence_count: d.pool_urgence_count ?? 0,
            messages_non_lus: d.messages_non_lus ?? 0,
            missions_a_payer: d.missions_a_payer ?? 0,
            missions_terminees_ce_mois: d.missions_terminees_ce_mois ?? 0,
            soignants_ce_mois: d.soignants_ce_mois ?? 0,
            commissions_impayees: d.commissions_impayees ?? 0,
            nb_factures_impayees: d.nb_factures_impayees ?? 0,
            litiges_ouverts: d.litiges_ouverts ?? 0,
          };
        } else if (resDashStats.error) {
          logger.error('[DashboardEtab] Erreur stats RPC', resDashStats.error);
          partialError = true;
        }

        // --- Minimal secondary queries (top soignants + prochaines missions) ---
        try {
          const [resCout, resProchaines] = await Promise.all([
            supabase.from('missions').select('id, total_brut, duree_heures, soignant_assigne_id, fin_le')
              .eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
            supabase.from('missions')
              .select('id, intitule, debut_le, fin_le, statut, duree_heures, profession_requise, soignant_assigne_id')
              .eq('etablissement_id', etablissementId)
              .gte('debut_le', now.toISOString())
              .lte('debut_le', new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString())
              .in('statut', ['OUVERTE', 'ASSIGNEE', 'EN_COURS'])
              .order('debut_le', { ascending: true }),
          ]);

          if (resCout.data) {
            const counts: Record<string, number> = {};
            const derniereMission: Record<string, { id: string; fin: string }> = {};
            for (const m of resCout.data as any[]) {
              if (m.soignant_assigne_id) {
                counts[m.soignant_assigne_id] = (counts[m.soignant_assigne_id] || 0) + 1;
                const cur = derniereMission[m.soignant_assigne_id];
                if (!cur || (m.fin_le && m.fin_le > cur.fin)) {
                  derniereMission[m.soignant_assigne_id] = { id: m.id, fin: m.fin_le || '' };
                }
              }
            }
            const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);
            const missingIds = sorted.map(([id]) => id).filter(id => !sgMap[id]);
            if (missingIds.length > 0) {
              const { data: sgExtra } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite').in('id', missingIds);
              if (sgExtra) for (const s of sgExtra) sgMap[s.id] = s;
            }
            topSoignantsResult = sorted.map(([id, count]) => {
              const sg = sgMap[id];
              return { id, prenom: sg?.prenom || 'Soignant', nom: sg?.nom || '', score_fiabilite: sg?.score_fiabilite ?? 0, count, derniere_mission_id: derniereMission[id]?.id || null };
            });
          }

          if (resProchaines.data) {
            prochainesResult = resProchaines.data.map((m: any) => ({
              ...m,
              soignant_nom: m.soignant_assigne_id && sgMap[m.soignant_assigne_id]
                ? `${sgMap[m.soignant_assigne_id].prenom} ${sgMap[m.soignant_assigne_id].nom}`
                : null,
            }));
          }
        } catch (err) {
          logger.warn('[DashboardEtab] Erreur secondaire (top soignants / prochaines)', err);
        }

      } catch (err) {
        handleErrorSilent(err, '[DashboardEtab] Erreur critique');
        partialError = true;
      }

      // Audit HDS
      try {
        await supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user!.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'etablissement', p_id_ressource: user!.id, p_cle_s3: null,
          p_details: { page: 'dashboard_etablissement' }, p_ip: null, p_navigateur: navigator.userAgent,
        });
      } catch (err) {
        logger.warn('[DashboardEtab] Erreur audit HDS', err);
      }

      return {
        etab: etabResult,
        missions: missionsResult,
        aDejaPublie: aDejaPublieResult,
        paliers: paliersResult,
        stats: statsResult,
        topSoignants: topSoignantsResult,
        prochaines: prochainesResult,
        erreurPartielle: partialError,
      };
    },
    staleTime: 60_000,
    enabled: !!user && !!etablissementId,
  });

  const etab = useMemo(() => dashData?.etab ?? null, [dashData]);
  const missions = useMemo(() => dashData?.missions ?? [], [dashData]);
  const aDejaPublie = useMemo(() => dashData?.aDejaPublie ?? null, [dashData]);
  const paliers = useMemo(() => dashData?.paliers ?? [], [dashData]);
  const stats = useMemo<DashboardStats>(() => dashData?.stats ?? {
    missions_ouvertes: 0, missions_assignees: 0, missions_en_cours: 0, missions_terminees: 0,
    candidatures_en_attente: 0, candidatures_recentes: [], missions_assignees_detail: [],
    pool_urgence_count: 0, messages_non_lus: 0, missions_a_payer: 0,
    missions_terminees_ce_mois: 0, soignants_ce_mois: 0, commissions_impayees: 0,
    nb_factures_impayees: 0, litiges_ouverts: 0,
  }, [dashData]);
  const topSoignants = useMemo(() => dashData?.topSoignants ?? [], [dashData]);
  const prochaines = useMemo(() => dashData?.prochaines ?? [], [dashData]);
  const erreurPartielle = useMemo(() => dashData?.erreurPartielle ?? false, [dashData]);

  const queryClient = useQueryClient();

  // handleAnnuler legacy supprimé : remplacé par ModaleAnnulationMissionEtab (Sprint 5.5 PR 3).

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  // F1 — Mode « première mission » : l'établissement n'a jamais publié de mission.
  // aDejaPublie peut valoir null si le fetch a échoué → on ne bascule en mode hero
  // QUE si on est sûr qu'il n'y a aucune mission (=== false), pour ne pas masquer
  // le dashboard complet sur un simple incident réseau.
  const premiereMission = aDejaPublie === false;

  // Blocage dur : compte bloqué automatiquement OU vérification requise.
  // Doit rester visible y compris en mode « première mission » (jamais masqué
  // derrière le hero).
  const blocageBanner = etab?.bloque_auto_le ? (
    <BandeauBlocageAuto
      raisons={etab.bloque_auto_raisons}
      bloque_le={etab.bloque_auto_le}
    />
  ) : etab && !etab.peut_publier_missions ? (
    <div className="bg-amber-50 dark:bg-amber-950/20 border border-amber-300 dark:border-amber-700 rounded-xl p-4 mb-4 flex items-start gap-3">
      <ShieldAlert className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
      <div className="flex-1">
        <p className="text-sm font-medium text-amber-800 dark:text-amber-300"><Clock className="inline-block h-4 w-4 mr-1 align-text-bottom" aria-hidden="true" />Votre compte est en cours de vérification</p>
        <p className="text-xs text-amber-600 dark:text-amber-400 mt-1">Vérifiez votre établissement (FINESS + rattachement du représentant) pour pouvoir publier des missions. À défaut, l'équipe Jolene valide votre dossier.</p>
        <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => navigate('/etablissement/activer')}>
          Vérifier mon établissement
        </BoutonY2K>
      </div>
    </div>
  ) : null;

  // F1 — Mode « première mission » : une seule section hero focalisée.
  if (premiereMission) {
    const etabVerifie = !!etab && etab.peut_publier_missions !== false && !etab.bloque_auto_le;
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        {/* Blocage dur conservé EN PREMIER même en mode hero (jamais masqué) */}
        {blocageBanner}
        {erreurPartielle && (
          <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 text-sm text-warning">
            <AlertTriangle className="inline-block h-4 w-4 mr-1 align-text-bottom" aria-hidden="true" />Certaines données n'ont pas pu être chargées.
          </div>
        )}

        <FadeInView delay={0}>
          <CardY2K variant="default" className="mb-6">
            <div className="flex flex-col items-center text-center gap-4 py-4">
              <Mascotte etat="thinking" taille="lg" />
              <div>
                <h1 className="text-2xl font-bold text-foreground">
                  Publiez votre <span className="text-gradient-hero">première mission</span>
                </h1>
                <p className="text-sm text-muted-foreground mt-2 max-w-md mx-auto">
                  2 minutes, et vous recevez des candidatures de soignants vérifiés.
                </p>
              </div>

              {/* Checklist d'activation */}
              <div className="w-full max-w-sm space-y-2 text-left mt-2">
                <div className="flex items-center gap-3 rounded-xl border border-border bg-card/50 p-3">
                  {etabVerifie ? (
                    <CheckCircle className="h-5 w-5 text-success flex-shrink-0" />
                  ) : (
                    <ShieldAlert className="h-5 w-5 text-amber-500 flex-shrink-0" />
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground">Établissement vérifié</p>
                    <p className="text-xs text-muted-foreground">
                      {etabVerifie ? 'Validé' : 'Vérification en cours'}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3 rounded-xl border border-border bg-card/50 p-3">
                  <ClipboardList className="h-5 w-5 text-muted-foreground flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground">Première mission publiée</p>
                    <p className="text-xs text-muted-foreground">À faire</p>
                  </div>
                </div>
              </div>

              <BoutonY2K
                variant="primary"
                onClick={() => navigate('/etablissement/missions/creer')}
                iconeGauche={<FileText className="h-4 w-4" />}
                className="mt-2"
              >
                Publier une mission
              </BoutonY2K>
            </div>
          </CardY2K>
        </FadeInView>
      </LayoutApp>
    );
  }

  // F6 — « À faire maintenant » : on consolide les ~6 bannières concurrentes en
  // une seule carte qui ne surface QUE les 1-2 actions prioritaires.
  // Ordre de priorité : blocage compte/vérif > candidatures > litiges > évaluations > messages.
  interface ActionAFaire { cle: string; icone: LucideIcon; label: string; sousTexte?: string; urgent?: boolean; cta: string; onClick: () => void; }
  const actionsAFaire: ActionAFaire[] = [];
  if (stats.candidatures_en_attente > 0) {
    const n = stats.candidatures_en_attente;
    actionsAFaire.push({
      cle: 'candidatures',
      icone: Timer,
      // Loss-aversion : un soignant non répondu peut accepter une autre mission
      // → la mission ne se remplit pas. On pousse à répondre vite.
      label: `${n} soignant${n > 1 ? 's' : ''} attend${n > 1 ? 'ent' : ''} votre réponse`,
      sousTexte: 'Répondez vite — ils peuvent accepter ailleurs',
      urgent: true,
      cta: 'Répondre',
      onClick: () => navigate('/etablissement/missions?statut=OUVERTE'),
    });
  }
  if (stats.litiges_ouverts > 0) {
    actionsAFaire.push({
      cle: 'litiges',
      icone: Scale,
      label: `${stats.litiges_ouverts} litige${stats.litiges_ouverts > 1 ? 's' : ''} en cours`,
      cta: 'Gérer',
      onClick: () => navigate('/etablissement/litiges'),
    });
  }
  if (stats.messages_non_lus > 0) {
    actionsAFaire.push({
      cle: 'messages',
      icone: MessageCircle,
      label: `${stats.messages_non_lus} message${stats.messages_non_lus > 1 ? 's' : ''} non lu${stats.messages_non_lus > 1 ? 's' : ''}`,
      cta: 'Ouvrir',
      onClick: () => navigate('/etablissement/messagerie'),
    });
  }
  // On n'affiche que les 2 actions les plus prioritaires.
  const actionsTop = actionsAFaire.slice(0, 2);

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      {/* F6 — bannière évaluations conservée mais discrète (composant existant) */}
      <BandeauEvaluationsEnAttente role="ETABLISSEMENT" />
      <CardScoreQualiteEtab />
      {erreurPartielle && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 text-sm text-warning">
          <AlertTriangle className="inline-block h-4 w-4 mr-1 align-text-bottom" aria-hidden="true" />Certaines données n'ont pas pu être chargées.
        </div>
      )}

      {/* Sprint 9-C PR 4 — Header Y2K avec mascotte cœur Jolene */}
      {etab ? (
        <div className="mb-6 flex items-start gap-4">
          <Mascotte etat="happy" taille="md" className="shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-xl font-bold text-foreground">
                Bonjour, <span className="text-gradient-hero">{etab.nom}</span>
              </h1>
              {etab.paliers_commission && (
                <BadgePalier palierNom={etab.paliers_commission.nom || 'Standard'} taux={etab.taux_commission_negocie ?? 15} />
              )}
            </div>
            {etab.groupes_sante && (
              <div className="flex items-center gap-2 mt-1">
                <span className="text-sm text-muted-foreground">Groupe</span>
                <span className="badge-base bg-primary/10 text-primary">{etab.groupes_sante.nom}</span>
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="mb-6 flex items-center gap-4">
          <Mascotte etat="idle" taille="md" />
          <h1 className="text-xl font-bold text-foreground">Tableau de bord</h1>
        </div>
      )}

      {/* F6 — Blocage dur conservé en premier (jamais masqué) */}
      {blocageBanner}

      {/* F6 — « À faire maintenant » : carte unique consolidant les bannières concurrentes */}
      {actionsTop.length > 0 && (
        <FadeInView delay={0}>
          <CardY2K className="mb-4">
            <p className="text-sm font-bold text-foreground mb-3">À faire maintenant</p>
            <div className="space-y-2">
              {actionsTop.map((a) => (
                <button
                  key={a.cle}
                  onClick={a.onClick}
                  className={`w-full flex items-center justify-between gap-3 p-2.5 rounded-xl transition-colors text-left ${
                    a.urgent
                      ? 'bg-primary/10 hover:bg-primary/15 border border-primary/30'
                      : 'bg-muted/40 hover:bg-muted/70'
                  }`}
                >
                  <span className="flex items-center gap-2 min-w-0">
                    <span aria-hidden="true" className="shrink-0"><a.icone className="h-4 w-4" /></span>
                    <span className="min-w-0">
                      <span className="block text-sm font-medium text-foreground truncate">{a.label}</span>
                      {a.sousTexte && <span className="block text-[11px] text-muted-foreground truncate">{a.sousTexte}</span>}
                    </span>
                  </span>
                  <span className="text-xs font-semibold text-primary shrink-0">{a.cta} →</span>
                </button>
              ))}
            </div>
          </CardY2K>
        </FadeInView>
      )}

      {/* Action principale : publier une mission, toujours accessible en haut */}
      <div className="flex gap-3 mb-6 overflow-x-auto pb-1">
        <BoutonY2K variant="primary" size="sm" onClick={() => navigate('/etablissement/missions/creer')} className="whitespace-nowrap" iconeGauche={<FileText className="h-4 w-4" />}>
          Publier une mission
        </BoutonY2K>
        <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/etablissement/missions')} className="whitespace-nowrap" iconeGauche={<ClipboardList className="h-4 w-4" />}>
          Mes missions
        </BoutonY2K>
        {etab?.groupe_sante_id && (
          <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/etablissement/mon-groupe')} className="whitespace-nowrap" iconeGauche={<Users className="h-4 w-4" />}>
            Mon groupe
          </BoutonY2K>
        )}
      </div>

      {/* KPI row 1 — All from RPC */}
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 mb-4">
        <FadeInView delay={0}>
          <CarteKPIY2K
            icone={<Briefcase className="h-4 w-4" />}
            valeur={stats.missions_ouvertes}
            label="Missions ouvertes"
            variant="holographic"
            onClick={() => navigate('/etablissement/missions?statut=OUVERTE')}
          />
        </FadeInView>
        <FadeInView delay={50}>
          <CarteKPIY2K
            icone={<ClipboardCheck className="h-4 w-4" />}
            valeur={stats.missions_assignees}
            label="Assignées"
            variant="default"
            onClick={() => navigate('/etablissement/missions?statut=ASSIGNEE')}
          />
        </FadeInView>
        <FadeInView delay={100}>
          <CarteKPIY2K
            icone={<PlayCircle className="h-4 w-4" />}
            valeur={stats.missions_en_cours}
            label="En cours"
            variant="default"
            onClick={() => navigate('/etablissement/missions?statut=EN_COURS')}
          />
        </FadeInView>
        <FadeInView delay={150}>
          <CarteKPIY2K
            icone={<CheckCircle className="h-4 w-4" />}
            valeur={stats.missions_terminees}
            label="Terminées"
            variant="default"
            onClick={() => navigate('/etablissement/missions?statut=TERMINEE')}
          />
        </FadeInView>
      </div>

      {/* KPI row 2 — Soignants ce mois + Impayés. « Candidatures en attente »
          retirée : doublon (même destination que « Missions ouvertes » et déjà
          surfacée dans la carte « À faire maintenant »). */}
      <div className="grid grid-cols-2 gap-3 mb-6">
        <FadeInView delay={250}>
          <CarteKPIY2K
            icone={<Users className="h-4 w-4" />}
            valeur={stats.soignants_ce_mois}
            label="Soignants ce mois"
            contexte={`Pool urgence : ${stats.pool_urgence_count}`}
            variant="default"
            onClick={() => navigate('/etablissement/pool-urgence')}
          />
        </FadeInView>
        <FadeInView delay={300}>
          {(() => {
            const totalImpayes = stats.missions_a_payer + stats.nb_factures_impayees;
            const hasImpayes = totalImpayes > 0;
            const sousLabelParts: string[] = [];
            if (stats.missions_a_payer > 0) sousLabelParts.push(`${stats.missions_a_payer} soignant(s)`);
            if (stats.nb_factures_impayees > 0) sousLabelParts.push(`${stats.nb_factures_impayees} facture(s) Jolene`);
            const IconeImpayes = hasImpayes ? CreditCard : CheckCircle;
            return (
              <CarteKPIY2K
                icone={<IconeImpayes className="h-4 w-4" />}
                valeur={hasImpayes ? totalImpayes : 0}
                label={hasImpayes ? 'Impayés — Cliquez pour payer' : 'Paiements à jour'}
                contexte={sousLabelParts.length > 0 ? sousLabelParts.join(' + ') : undefined}
                variant="default"
                onClick={() => navigate('/etablissement/facturation')}
              />
            );
          })()}
        </FadeInView>
      </div>

      {/* Planning missions à venir (30j) */}
      <FadeInView delay={600}>
        <SectionPlanning missions={prochaines} />
      </FadeInView>

      {/* Statistiques détaillées — repliées par défaut (densité). Le manager
          voit d'abord action + pipeline + planning ; il déplie les analytics
          (turnover, évolution 6 mois, top soignants) à la demande. */}
      <div className="mb-6">
        <button
          type="button"
          onClick={() => setStatsOuvertes((v) => !v)}
          aria-expanded={statsOuvertes}
          className="w-full flex items-center justify-between gap-2 rounded-2xl border border-border bg-card px-4 py-3 hover:border-jolene-rose-200 transition-colors"
        >
          <span className="inline-flex items-center gap-2 text-sm font-bold text-foreground">
            <BarChart3 className="h-4 w-4 text-primary" /> Statistiques détaillées
          </span>
          <ChevronDown className={`h-4 w-4 text-muted-foreground transition-transform ${statsOuvertes ? 'rotate-180' : ''}`} />
        </button>

        {statsOuvertes && (
          <div className="mt-4 space-y-6">
            {/* Indicateurs avancés (J5.B.2) — turnover, taux remplissage, coût moyen */}
            <IndicateursAvancesEtab soignantsCeMois={Number(stats.soignants_ce_mois) || 0} />

            {/* Évolution missions 6 mois */}
            <GraphiqueEvolutionMissions />

            {/* Top soignants */}
            <TopSoignants soignants={topSoignants} etablissementId={etablissementId!} onSelectSoignant={(soignantId) => navigate(`/etablissement/soignants/${soignantId}`)} />
          </div>
        )}
      </div>

      {/* Commission Jolene — carte compacte */}
      {etab && (
        <div className="card-base cursor-pointer hover:shadow-md mb-6" onClick={() => navigate('/etablissement/facturation?tab=commissions')}>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-foreground">Commission Jolene</p>
              <p className="text-xs text-muted-foreground">
                Palier {etab.paliers_commission?.nom || paliers[0]?.nom || 'Découverte'}
              </p>
            </div>
            <div className="text-right">
              <p className="text-lg font-bold text-primary">{etab.taux_commission_negocie ?? 15}%</p>
              {paliers[1] && (
                <p className="text-[10px] text-muted-foreground">
                  Prochain : {paliers[1].nom} →
                </p>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Bonus fidélité annuel (BFA) — s'auto-masque si l'étab n'est pas éligible.
          Levier de rétention : « publie plus → gagne un bonus ». */}
      {etablissementId && <CarteBFAInfo etablissementId={etablissementId} />}

      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Dernières missions</h2>
          <button onClick={() => navigate('/etablissement/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
        </div>

        {missions.length > 0 ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {missions.map((m, i) => (
              <FadeInView key={m.id} delay={i * 100}>
                <CarteMission mission={m}
                  onDupliquer={(m) => setModalDupliquer(m)}
                  onAnnuler={(m) => setModalAnnuler(m)}
                  onRepublier={(m, dates) => {
                    // Session F (F3) — republier avec nouvelles dates optionnelles.
                    const params = new URLSearchParams({ dupliquer: m.id });
                    if (dates?.debut) params.set('debut', dates.debut);
                    if (dates?.fin) params.set('fin', dates.fin);
                    navigate(`/etablissement/missions/creer?${params.toString()}`);
                  }}
                />
              </FadeInView>
            ))}
          </div>
        ) : (
          /* Mode « première mission » géré en amont (hero) → ici on a déjà publié
             mais aucune mission récente dans les 5 dernières remontées. */
          <p className="text-sm text-muted-foreground text-center py-6">Aucune mission récente.</p>
        )}
      </div>


      <ModalConfirmation ouvert={!!modalDupliquer} onFermer={() => setModalDupliquer(null)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${modalDupliquer.id}`)}
        titre="Dupliquer cette mission ?" message={`Une copie de « ${modalDupliquer?.intitule} » sera créée.`} labelConfirmer="Dupliquer" />
      {/* Sprint 5.5 PR 3 : modale annulation avec décomposition L1243-8 / 1231-5
          Sprint 8 ter-G : lazy mount (code splitting) */}
      {modalAnnuler && (
        <Suspense fallback={null}>
        <ModaleAnnulationMissionEtab
          ouvert={true}
          onFermer={() => setModalAnnuler(null)}
          onAnnulee={() => {
            setModalAnnuler(null);
            queryClient.invalidateQueries({ queryKey: ['dashboard-etablissement'] });
          }}
          mission={{
            id: (modalAnnuler as any).id,
            intitule: (modalAnnuler as any).intitule,
            statut: (modalAnnuler as any).statut,
            debut_le: (modalAnnuler as any).debut_le,
            fin_le: (modalAnnuler as any).fin_le,
            duree_heures: (modalAnnuler as any).duree_heures,
            taux_horaire_base: (modalAnnuler as any).taux_horaire_base,
            total_brut: (modalAnnuler as any).total_brut,
            type_contrat_applique: (modalAnnuler as any).type_contrat_applique,
            type_contrat_recherche: (modalAnnuler as any).type_contrat_recherche,
          }}
        />
        </Suspense>
      )}
    </LayoutApp>
  );
}

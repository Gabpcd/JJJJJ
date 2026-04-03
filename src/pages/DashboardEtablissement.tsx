import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { logger } from '@/lib/logger';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, ClipboardList, FileText, Users, Star, ClipboardCheck, ShieldAlert, MessageCircle, CreditCard, Zap } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { CarteMission } from '@/components/CarteMission';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { FABCreerMission } from '@/components/FABCreerMission';
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { WidgetPalierFidelite } from '@/components/WidgetPalierFidelite';
import { BadgePalier } from '@/components/BadgePalier';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { OnboardingGuide } from '@/components/OnboardingGuide';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

import { TopSoignants } from '@/components/dashboard/TopSoignants';
import { ProchaineMissions } from '@/components/dashboard/ProchaineMissions';
import { CarteCommissionJolene } from '@/components/dashboard/CarteCommissionJolene';
import { CarteBFAInfo } from '@/components/dashboard/CarteBFAInfo';

export default function DashboardEtablissement() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [etab, setEtab] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [aDejaPublie, setADejaPublie] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const [erreurPartielle, setErreurPartielle] = useState(false);
  const [modalDupliquer, setModalDupliquer] = useState<any>(null);
  const [modalAnnuler, setModalAnnuler] = useState<any>(null);
  const [paliers, setPaliers] = useState<any[]>([]);

  // All stats from RPC
  const [stats, setStats] = useState<any>({
    missions_ouvertes: 0,
    missions_assignees: 0,
    missions_en_cours: 0,
    missions_terminees: 0,
    candidatures_en_attente: 0,
    candidatures_recentes: [],
    missions_assignees_detail: [],
    pool_urgence_count: 0,
    messages_non_lus: 0,
    missions_a_payer: 0,
    missions_terminees_ce_mois: 0,
    soignants_ce_mois: 0,
    commissions_impayees: 0,
    nb_factures_impayees: 0,
  });

  const [topSoignants, setTopSoignants] = useState<any[]>([]);
  const [prochaines, setProchaines] = useState<any[]>([]);

  const charger = async () => {
    if (!user || !etablissementId) return;
    let partialError = false;
    const now = new Date();
    const debutMois = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();

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
      else if (resEtab.data) setEtab(resEtab.data);

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
        setMissions(resMissions.data.map((m: any) => ({
          ...m,
          soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null,
        })));
        setADejaPublie(resMissions.data.length > 0);
      }

      if (resPaliers.data) setPaliers(resPaliers.data);

      // Dashboard stats RPC — single source of truth for all KPIs
      if (resDashStats.data) {
        const d = resDashStats.data;
        setStats({
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
        });
      } else if (resDashStats.error) {
        logger.error('[DashboardEtab] Erreur stats RPC', resDashStats.error);
        partialError = true;
      }

      // --- HR QUERIES (non-blocking) ---
      // --- Minimal secondary queries (top soignants + prochaines missions) ---
      try {
        const [resCout, resProchaines] = await Promise.all([
          supabase.from('missions').select('total_brut, duree_heures, soignant_assigne_id')
            .eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
          supabase.from('missions')
            .select('id, intitule, debut_le, statut, soignant_assigne_id')
            .eq('etablissement_id', etablissementId).gte('debut_le', now.toISOString())
            .in('statut', ['OUVERTE', 'ASSIGNEE', 'EN_COURS'])
            .order('debut_le', { ascending: true }).limit(5),
        ]);

        if (resCout.data) {
          const counts: Record<string, number> = {};
          for (const m of resCout.data) {
            if (m.soignant_assigne_id) counts[m.soignant_assigne_id] = (counts[m.soignant_assigne_id] || 0) + 1;
          }
          const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);
          const missingIds = sorted.map(([id]) => id).filter(id => !sgMap[id]);
          if (missingIds.length > 0) {
            const { data: sgExtra } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite').in('id', missingIds);
            if (sgExtra) for (const s of sgExtra) sgMap[s.id] = s;
          }
          setTopSoignants(sorted.map(([id, count]) => {
            const sg = sgMap[id];
            return { id, prenom: sg?.prenom || 'Soignant', nom: sg?.nom || '', score_fiabilite: sg?.score_fiabilite ?? 0, count };
          }));
        }

        if (resProchaines.data) {
          setProchaines(resProchaines.data.map((m: any) => ({
            ...m,
            soignant_nom: m.soignant_assigne_id && sgMap[m.soignant_assigne_id]
              ? `${sgMap[m.soignant_assigne_id].prenom} ${sgMap[m.soignant_assigne_id].nom}`
              : null,
          })));
        }
      } catch {}

    } catch (err) {
      handleErrorSilent(err, '[DashboardEtab] Erreur critique');
      partialError = true;
    }

    // Audit HDS
    try {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'ADMIN_ETABLISSEMENT', p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'etablissement', p_id_ressource: user.id, p_cle_s3: null,
        p_details: { page: 'dashboard_etablissement' }, p_ip: null, p_navigateur: navigator.userAgent,
      });
    } catch {}

    setErreurPartielle(partialError);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, etablissementId]);

  const handleAnnuler = async (mission: Record<string, unknown>) => {
    const { data, error } = await supabase.rpc('fn_annuler_mission_etablissement' as any, { p_mission_id: mission.id });
    const result = data as unknown as { success?: boolean; error?: string } | null;
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else if (result?.success === false) afficherNotification({ type: 'erreur', message: result.error || 'Erreur' });
    else { afficherNotification({ type: 'succes', message: 'Mission annulée.' }); charger(); }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <BandeauEvaluationsEnAttente role="ETABLISSEMENT" />
      <OnboardingGuide role="ADMIN_ETABLISSEMENT" userId={user!.id} />
      {erreurPartielle && (
        <div className="bg-warning/10 border border-warning/30 rounded-xl p-3 mb-4 text-sm text-warning">
          ⚠️ Certaines données n'ont pas pu être chargées.
        </div>
      )}

      {etab ? (
        <div className="mb-6">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-xl font-bold text-foreground">Bienvenue, <span className="text-primary">{etab.nom}</span></h1>
            {etab.paliers_commission && (
              <BadgePalier palierNom={etab.paliers_commission.nom} taux={etab.taux_commission_negocie ?? 15} />
            )}
          </div>
          {etab.groupes_sante && (
            <div className="flex items-center gap-2 mt-1">
              <span className="text-sm text-muted-foreground">Groupe</span>
              <span className="badge-base bg-primary/10 text-primary">{etab.groupes_sante.nom}</span>
            </div>
          )}
        </div>
      ) : (
        <div className="mb-6">
          <h1 className="text-xl font-bold text-foreground">Tableau de bord</h1>
        </div>
      )}

      {/* 🔔 Candidatures en attente */}
      {stats.candidatures_en_attente > 0 && (
        <FadeInView delay={0}>
          <div className="card-base border-warning/30 bg-warning/5 mb-4">
            <p className="text-sm font-semibold text-warning flex items-center gap-2 mb-2">
              🔔 {stats.candidatures_en_attente} candidature{stats.candidatures_en_attente > 1 ? 's' : ''} en attente
            </p>
            <div className="space-y-1.5">
              {stats.candidatures_recentes.slice(0, 5).map((c: any) => (
                <button key={c.candidature_id} onClick={() => navigate(`/etablissement/missions/${c.mission_id}`)}
                  className="w-full flex items-center justify-between text-sm p-1.5 rounded-lg hover:bg-muted/50 transition-colors text-left">
                  <span className="text-foreground">
                    👤 {c.soignant_nom} · <span className="text-muted-foreground">{c.mission_intitule}</span>
                  </span>
                  <span className="text-xs text-primary shrink-0">Voir →</span>
                </button>
              ))}
            </div>
          </div>
        </FadeInView>
      )}

      {/* ✅ Missions confirmées */}
      {stats.missions_assignees_detail.length > 0 && (
        <FadeInView delay={50}>
          <div className="card-base border-success/30 bg-success/5 mb-4">
            <p className="text-sm font-semibold text-success flex items-center gap-2 mb-2">
              ✅ {stats.missions_assignees_detail.length} mission{stats.missions_assignees_detail.length > 1 ? 's' : ''} confirmée{stats.missions_assignees_detail.length > 1 ? 's' : ''}
            </p>
            <div className="space-y-1.5">
              {stats.missions_assignees_detail.slice(0, 5).map((m: any) => (
                <button key={m.mission_id} onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                  className="w-full flex items-center justify-between text-sm p-1.5 rounded-lg hover:bg-muted/50 transition-colors text-left">
                  <span className="text-foreground">
                    {m.intitule} · <span className="text-muted-foreground">{m.soignant_nom}</span>
                    {m.debut_le && <span className="text-muted-foreground"> · {new Date(m.debut_le).toLocaleDateString('fr-FR')}</span>}
                  </span>
                  <span className="text-xs text-primary shrink-0">Voir →</span>
                </button>
              ))}
            </div>
          </div>
        </FadeInView>
      )}

      {/* 💬 Messages non lus */}
      {stats.messages_non_lus > 0 && (
        <FadeInView delay={75}>
          <button
            className="w-full card-base border-primary/30 bg-primary/5 mb-4 hover:bg-primary/10 transition-colors text-left"
            onClick={() => navigate('/etablissement/messagerie')}
          >
            <p className="text-sm font-semibold text-primary flex items-center gap-2">
              <MessageCircle className="h-4 w-4" />
              💬 {stats.messages_non_lus} message{stats.messages_non_lus > 1 ? 's' : ''} non lu{stats.messages_non_lus > 1 ? 's' : ''}
            </p>
            <p className="text-xs text-muted-foreground mt-1">Cliquez pour ouvrir la messagerie</p>
          </button>
        </FadeInView>
      )}

      <div className="flex gap-3 mb-6 overflow-x-auto pb-1">
        <button onClick={() => navigate('/etablissement/missions/creer')} className="btn-primary text-sm whitespace-nowrap flex items-center gap-2">
          <FileText className="h-4 w-4" /> Publier une mission
        </button>
        <button onClick={() => navigate('/etablissement/missions')} className="btn-secondary text-sm whitespace-nowrap flex items-center gap-2">
          <ClipboardList className="h-4 w-4" /> Mes missions
        </button>
        {etab?.groupe_sante_id && (
          <button onClick={() => navigate('/etablissement/mon-groupe')} className="btn-secondary text-sm whitespace-nowrap flex items-center gap-2">
            <Users className="h-4 w-4" /> Mon groupe
          </button>
        )}
      </div>

      {etab && !etab.peut_publier_missions && (
        <div className="bg-amber-50 dark:bg-amber-950/20 border border-amber-300 dark:border-amber-700 rounded-xl p-4 mb-4 flex items-start gap-3">
          <ShieldAlert className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-amber-800 dark:text-amber-300">⏳ Votre compte est en cours de vérification</p>
            <p className="text-xs text-amber-600 dark:text-amber-400 mt-1">Vous pourrez publier des missions une fois votre établissement vérifié par l'équipe Jolene (24-48h).</p>
          </div>
        </div>
      )}

      {/* KPI row 1 — All from RPC */}
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 mb-4">
        <FadeInView delay={0}>
          <CarteKPI icone={Briefcase} valeur={stats.missions_ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/etablissement/missions?statut=OUVERTE" />
        </FadeInView>
        <FadeInView delay={50}>
          <CarteKPI icone={ClipboardCheck} valeur={stats.missions_assignees} label="Assignées" couleurIcone="text-info" couleurFond="bg-info/10" lien="/etablissement/missions?statut=ASSIGNEE" />
        </FadeInView>
        <FadeInView delay={100}>
          <CarteKPI icone={PlayCircle} valeur={stats.missions_en_cours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/etablissement/missions?statut=EN_COURS" />
        </FadeInView>
        <FadeInView delay={150}>
          <CarteKPI icone={CheckCircle} valeur={stats.missions_terminees} label="Terminées" couleurIcone="text-success" couleurFond="bg-success/10" lien="/etablissement/missions?statut=TERMINEE" />
        </FadeInView>
      </div>

      {/* KPI row 2 — Candidatures, Soignants ce mois, À payer, Commissions */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
        <FadeInView delay={200}>
          <CarteKPI icone={Star} valeur={stats.candidatures_en_attente} label="Candidatures en attente" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/etablissement/missions?statut=OUVERTE" />
        </FadeInView>
        <FadeInView delay={250}>
          <CarteKPI icone={Users} valeur={stats.soignants_ce_mois} label="Soignants ce mois" sousLabel={`Pool urgence : ${stats.pool_urgence_count}`} couleurIcone="text-info" couleurFond="bg-info/10" lien="/etablissement/pool-soignants" />
        </FadeInView>
        <FadeInView delay={300}>
          <CarteKPI icone={CreditCard} valeur={stats.missions_a_payer} label="Soignants à payer" couleurIcone="text-warning" couleurFond="bg-warning/10" lien="/etablissement/facturation" />
        </FadeInView>
        <FadeInView delay={350}>
          {stats.commissions_impayees > 0 ? (
            <CarteKPI icone={FileText} valeur={new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(stats.commissions_impayees)} label={`⚠️ ${stats.nb_factures_impayees} facture(s) impayée(s)`} couleurIcone="text-destructive" couleurFond="bg-destructive/10" lien="/etablissement/facturation?tab=commissions" />
          ) : (
            <CarteKPI icone={FileText} valeur="✅ À jour" label="Commissions Jolene" couleurIcone="text-success" couleurFond="bg-success/10" lien="/etablissement/facturation?tab=commissions" />
          )}
        </FadeInView>
      </div>

      {/* Top soignants + Prochaines missions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <FadeInView delay={600}>
          <TopSoignants soignants={topSoignants} etablissementId={etablissementId!} onSelectSoignant={(soignantId) => navigate(`/etablissement/soignants/${soignantId}`)} />
        </FadeInView>
        <FadeInView delay={650}>
          <ProchaineMissions missions={prochaines} />
        </FadeInView>
      </div>

      {/* Carte Commission Jolene */}
      {etab && <CarteCommissionJolene etablissementId={etablissementId!} />}

      {/* Widget Palier de Fidélité */}
      {etab && paliers.length > 0 && <WidgetPalierFidelite etab={etab} paliers={paliers} missionsCeMois={stats.missions_terminees_ce_mois} />}

      {/* Carte BFA Info */}
      {etab && <CarteBFAInfo etablissementId={etablissementId!} />}

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
                  onRepublier={(m) => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)}
                />
              </FadeInView>
            ))}
          </div>
        ) : aDejaPublie === false ? (
          <EtatVide icone={ClipboardList} titre="Publiez votre première mission" sousTitre="Les soignants qualifiés de votre zone seront notifiés immédiatement" boutonLabel="Publier une mission" boutonRoute="/etablissement/missions/creer" />
        ) : (
          <p className="text-sm text-muted-foreground text-center py-6">Aucune mission récente.</p>
        )}
      </div>

      <FABCreerMission />

      <ModalConfirmation ouvert={!!modalDupliquer} onFermer={() => setModalDupliquer(null)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${modalDupliquer.id}`)}
        titre="Dupliquer cette mission ?" message={`Une copie de « ${modalDupliquer?.intitule} » sera créée.`} labelConfirmer="Dupliquer" />
      <ModalConfirmation ouvert={!!modalAnnuler} onFermer={() => setModalAnnuler(null)}
        onConfirmer={() => handleAnnuler(modalAnnuler)}
        titre="Annuler cette mission ?" message={`La mission « ${modalAnnuler?.intitule} » sera définitivement annulée.`}
        labelConfirmer="Annuler la mission" variante="danger" />
    </LayoutApp>
  );
}

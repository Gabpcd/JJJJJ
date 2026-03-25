import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { SkeletonDashboard, SkeletonList } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp, ClipboardList, FileText, Users, Star, ClipboardCheck, ShieldAlert } from 'lucide-react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { CarteMission } from '@/components/CarteMission';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { FABCreerMission } from '@/components/FABCreerMission';
import { BandeauEvaluationsEnAttente } from '@/components/BandeauEvaluationsEnAttente';
import { WidgetPalierFidelite } from '@/components/WidgetPalierFidelite';
import { WidgetBFA } from '@/components/WidgetBFA';
import { BadgePalier } from '@/components/BadgePalier';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { OnboardingGuide } from '@/components/OnboardingGuide';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

import { KPICoutMoyenHeure } from '@/components/dashboard/KPICoutMoyenHeure';
import { JaugeTauxRemplissage } from '@/components/dashboard/JaugeTauxRemplissage';
import { TopSoignants } from '@/components/dashboard/TopSoignants';
import { IndicateurTurnover } from '@/components/dashboard/IndicateurTurnover';
import { ProchaineMissions } from '@/components/dashboard/ProchaineMissions';
import { CompteurSoignantsDisponibles } from '@/components/dashboard/CompteurSoignantsDisponibles';
import { CarteCommissionJolene } from '@/components/dashboard/CarteCommissionJolene';
import { CarteBFAInfo } from '@/components/dashboard/CarteBFAInfo';

export default function DashboardEtablissement() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const [etab, setEtab] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [kpi, setKpi] = useState({ ouvertes: 0, enCours: 0, terminees: 0, taux: 0 });
  const [contratsCount, setContratsCount] = useState(0);
  const [presencesCount, setPresencesCount] = useState(0);
  const [facturesImpayees, setFacturesImpayees] = useState(0);
  const [loading, setLoading] = useState(true);
  const [erreurPartielle, setErreurPartielle] = useState(false);
  const [modalDupliquer, setModalDupliquer] = useState<any>(null);
  const [modalAnnuler, setModalAnnuler] = useState<any>(null);
  const [paliers, setPaliers] = useState<any[]>([]);
  const [missionsCeMois, setMissionsCeMois] = useState(0);
  const [missionsParSemaine, setMissionsParSemaine] = useState<any[]>([]);
  const [coutParMois, setCoutParMois] = useState<any[]>([]);
  const [favoris, setFavoris] = useState<any[]>([]);

  // New HR state
  const [coutMoyen, setCoutMoyen] = useState({ totalBrut: 0, totalHeures: 0 });
  const [remplissage, setRemplissage] = useState({ pourvues: 0, total: 0 });
  const [topSoignants, setTopSoignants] = useState<any[]>([]);
  const [turnover, setTurnover] = useState({ ceMois: 0, moisPrec: 0 });
  const [prochaines, setProchaines] = useState<any[]>([]);

  const charger = async () => {
    if (!user || !etablissementId) return;
    let partialError = false;
    const now = new Date();
    const debutMois = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const debutMoisPrec = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString();
    const finMoisPrec = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59).toISOString();

    try {
      const [resEtab, resMissions, resPaliers, resMissionsCeMois, resSoignants] = await Promise.all([
        supabase.from('etablissements').select('id, nom, type, email_contact, groupe_sante_id, taux_commission_negocie, palier_commission_id, peut_publier_missions, statut_verification, groupes_sante(nom), paliers_commission(nom)').eq('id', etablissementId).maybeSingle(),
        supabase.from('missions')
          .select('id, intitule, description, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer, statut, est_urgente, niveau_urgence, soignant_assigne_id, cree_le')
          .eq('etablissement_id', etablissementId)
          .order('cree_le', { ascending: false })
          .limit(5),
        supabase.from('paliers_commission').select('id, nom, missions_min, missions_max, ordre').eq('est_actif', true).order('ordre', { ascending: true }),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
        supabase.rpc('fn_mes_soignants_etablissement'),
      ]);

      if (resEtab.error) { console.error('[DashboardEtab] Erreur établissement:', resEtab.error); handleErrorSilent(resEtab.error, '[DashboardEtab] Erreur établissement'); partialError = true; }
      else if (!resEtab.data) { console.warn('[DashboardEtab] Aucun établissement trouvé pour user.id:', user.id); partialError = true; }
      else if (resEtab.data) setEtab(resEtab.data);

      const sgMap: Record<string, any> = {};
      if (Array.isArray(resSoignants.data)) {
        for (const s of resSoignants.data) sgMap[s.id] = s;
      }

      // Fallback: fetch soignant names directly if RPC returned empty
      if (Object.keys(sgMap).length === 0 && resMissions.data) {
        const sgIds = [...new Set((resMissions.data as any[]).map((m: any) => m.soignant_assigne_id).filter(Boolean))];
        if (sgIds.length > 0) {
          const { data: sgDirect } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite, numero_rpps').in('id', sgIds);
          if (sgDirect) for (const s of sgDirect) sgMap[s.id] = s;
        }
      }

      if (resMissions.error) { console.error('[DashboardEtab] Erreur missions:', resMissions.error); handleErrorSilent(resMissions.error, '[DashboardEtab] Erreur missions'); partialError = true; }
      if (resSoignants.error) { console.error('[DashboardEtab] Erreur soignants RPC:', resSoignants.error); }
      else if (resMissions.data) setMissions(resMissions.data.map((m: any) => ({
        ...m,
        soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null,
      })));

      if (resPaliers.data) setPaliers(resPaliers.data);
      setMissionsCeMois(resMissionsCeMois.count ?? 0);

      // --- NEW HR QUERIES (non-blocking) ---
      try {
        // Coût moyen + remplissage + turnover + top soignants + prochaines
        const [resCout, resTotalMois, resPourvues, resSgCeMois, resSgMoisPrec, resProchaines] = await Promise.all([
          // Missions terminées ce mois avec montants
          supabase.from('missions').select('total_brut, duree_heures, soignant_assigne_id')
            .eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
          // Total missions publiées ce mois
          supabase.from('missions').select('id', { count: 'exact', head: true })
            .eq('etablissement_id', etablissementId).gte('cree_le', debutMois),
          // Missions pourvues ce mois
          supabase.from('missions').select('id', { count: 'exact', head: true })
            .eq('etablissement_id', etablissementId).gte('cree_le', debutMois).not('soignant_assigne_id', 'is', null),
          // Soignants distincts ce mois
          supabase.from('missions').select('soignant_assigne_id')
            .eq('etablissement_id', etablissementId).not('soignant_assigne_id', 'is', null).gte('debut_le', debutMois),
          // Soignants distincts mois précédent
          supabase.from('missions').select('soignant_assigne_id')
            .eq('etablissement_id', etablissementId).not('soignant_assigne_id', 'is', null)
            .gte('debut_le', debutMoisPrec).lt('debut_le', debutMois),
          // 5 prochaines missions
          supabase.from('missions')
            .select('id, intitule, debut_le, statut, soignant_assigne_id')
            .eq('etablissement_id', etablissementId).gte('debut_le', now.toISOString())
            .in('statut', ['OUVERTE', 'ASSIGNEE', 'EN_COURS'])
            .order('debut_le', { ascending: true }).limit(5),
        ]);

        // Coût moyen
        if (resCout.data) {
          const tb = resCout.data.reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
          const th = resCout.data.reduce((s: number, m: any) => s + (m.duree_heures || 0), 0);
          setCoutMoyen({ totalBrut: tb, totalHeures: th });

          // Top 3 soignants from terminated missions
          const counts: Record<string, number> = {};
          for (const m of resCout.data) {
            if (m.soignant_assigne_id) counts[m.soignant_assigne_id] = (counts[m.soignant_assigne_id] || 0) + 1;
          }
          const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 3);

          // Fetch missing soignant names if not in sgMap
          const missingIds = sorted.map(([id]) => id).filter(id => !sgMap[id]);
          if (missingIds.length > 0) {
            const { data: sgExtra } = await supabase.from('soignants').select('id, prenom, nom, profession, score_fiabilite').in('id', missingIds);
            if (sgExtra) for (const s of sgExtra) sgMap[s.id] = s;
          }

          const top = sorted.map(([id, count]) => {
            const sg = sgMap[id];
            return {
              id,
              prenom: sg?.prenom || 'Soignant',
              nom: sg?.nom || '',
              score_fiabilite: sg?.score_fiabilite ?? 0,
              count,
            };
          });
          setTopSoignants(top);
        }

        // Remplissage
        setRemplissage({ pourvues: resPourvues.count ?? 0, total: resTotalMois.count ?? 0 });

        // Turnover
        const distinctCe = new Set((resSgCeMois.data || []).map((m: any) => m.soignant_assigne_id)).size;
        const distinctPrec = new Set((resSgMoisPrec.data || []).map((m: any) => m.soignant_assigne_id)).size;
        setTurnover({ ceMois: distinctCe, moisPrec: distinctPrec });

        // Prochaines missions
        if (resProchaines.data) {
          setProchaines(resProchaines.data.map((m: any) => ({
            ...m,
            soignant_nom: m.soignant_assigne_id && sgMap[m.soignant_assigne_id]
              ? `${sgMap[m.soignant_assigne_id].prenom} ${sgMap[m.soignant_assigne_id].nom}`
              : null,
          })));
        }
      } catch {}

      // Graphiques + favoris (non-bloquant)
      try {
        const semaines: { label: string; count: number }[] = [];
        for (let i = 7; i >= 0; i--) {
          const end = new Date(now); end.setDate(end.getDate() - i * 7);
          const start = new Date(end); start.setDate(start.getDate() - 7);
          const { count } = await supabase.from('missions').select('id', { count: 'exact', head: true })
            .eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE')
            .gte('fin_le', start.toISOString()).lt('fin_le', end.toISOString());
          semaines.push({ label: `S-${i}`, count: count ?? 0 });
        }
        setMissionsParSemaine(semaines);

        const mois: { label: string; total: number }[] = [];
        for (let i = 3; i >= 0; i--) {
          const moisDate = new Date(now.getFullYear(), now.getMonth() - i, 1);
          const finMoisD = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59);
          const { data: mData } = await supabase.from('missions').select('total_brut')
            .eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE')
            .gte('fin_le', moisDate.toISOString()).lte('fin_le', finMoisD.toISOString());
          const total = (mData || []).reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
          mois.push({ label: moisDate.toLocaleDateString('fr-FR', { month: 'short' }), total });
        }
        setCoutParMois(mois);

          const { data: favData } = await (supabase.from('favoris' as any) as any).select('soignant_id, cree_le').eq('etablissement_id', etablissementId).order('cree_le', { ascending: false }).limit(5);
        if (favData && favData.length > 0) {
          const enriched = favData.map((f: any) => ({ ...(sgMap[f.soignant_id] || { id: f.soignant_id }), soignant_id: f.soignant_id }));
          setFavoris(enriched);
        }
      } catch {}

    } catch (err) {
      handleErrorSilent(err, '[DashboardEtab] Erreur critique');
      partialError = true;
    }

    // KPI
    try {
      const [resO, resEC, resT, resTotal, resAssigned, resContrats, resPresences, resFactures] = await Promise.all([
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).eq('statut', 'OUVERTE'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).eq('statut', 'EN_COURS'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).not('soignant_assigne_id', 'is', null),
        supabase.from('contrats_mission').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId),
        (supabase.from('presences' as any) as any).select('id, missions!inner(id)', { count: 'exact', head: true }).eq('missions.etablissement_id', etablissementId),
        supabase.from('factures').select('id', { count: 'exact', head: true }).eq('etablissement_id', etablissementId).eq('statut', 'EMISE'),
      ]);
      if (resO.error || resEC.error || resT.error || resTotal.error || resAssigned.error) partialError = true;
      const totalN = resTotal.count ?? 0;
      setKpi({
        ouvertes: resO.count ?? 0,
        enCours: resEC.count ?? 0,
        terminees: resT.count ?? 0,
        taux: totalN > 0 ? Math.round(((resAssigned.count ?? 0) / totalN) * 100) : 0,
      });
      setContratsCount(resContrats.count ?? 0);
      setPresencesCount(resPresences.count ?? 0);
      setFacturesImpayees(resFactures.count ?? 0);
    } catch (err) {
      handleErrorSilent(err, '[DashboardEtab] Erreur KPI');
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

  const handleAnnuler = async (mission: any) => {
    const { data, error } = await supabase.rpc('fn_annuler_mission_etablissement' as any, { p_mission_id: mission.id });
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else if ((data as any)?.success === false) afficherNotification({ type: 'erreur', message: (data as any).error });
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

      {/* Actions rapides */}
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

      {/* Compteur soignants disponibles — clickable */}
      <div className="mb-6 cursor-pointer" onClick={() => navigate('/etablissement/pool-urgence?disponibles=1')}>
        <FadeInView delay={50}>
          <CompteurSoignantsDisponibles etablissementId={etablissementId!} />
        </FadeInView>
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

      {/* KPI row 1 */}
      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 mb-4">
        <FadeInView delay={0}><div className="cursor-pointer" onClick={() => navigate('/etablissement/missions?statut=OUVERTE')}><CarteKPI icone={Briefcase} valeur={kpi.ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" /></div></FadeInView>
        <FadeInView delay={100}><div className="cursor-pointer" onClick={() => navigate('/etablissement/missions?statut=EN_COURS')}><CarteKPI icone={PlayCircle} valeur={kpi.enCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" /></div></FadeInView>
        <FadeInView delay={200}><div className="cursor-pointer" onClick={() => navigate('/etablissement/contrats?statut=SIGNE_COMPLET')}><CarteKPI icone={FileText} valeur={contratsCount} label="Contrats" couleurIcone="text-info" couleurFond="bg-info/10" /></div></FadeInView>
        <FadeInView delay={300}><div className="cursor-pointer" onClick={() => navigate('/etablissement/presences?tab=validees')}><CarteKPI icone={ClipboardCheck} valeur={presencesCount} label="Présences" couleurIcone="text-success" couleurFond="bg-success/10" /></div></FadeInView>
      </div>

      {/* KPI row 2 — HR indicators */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <FadeInView delay={400}>
          <div className="cursor-pointer" onClick={() => navigate('/etablissement/rh?vue=cout-moyen')}>
            <KPICoutMoyenHeure totalBrut={coutMoyen.totalBrut} totalHeures={coutMoyen.totalHeures} />
          </div>
        </FadeInView>
        <FadeInView delay={500}>
          <div className="cursor-pointer" onClick={() => navigate('/etablissement/missions?periode=mois')}>
            <JaugeTauxRemplissage pourvues={remplissage.pourvues} total={remplissage.total} />
          </div>
        </FadeInView>
        <FadeInView delay={600}>
          <div className="cursor-pointer" onClick={() => navigate('/etablissement/rh?vue=soignants-mois')}>
            <IndicateurTurnover soignantsCeMois={turnover.ceMois} soignantsMoisPrecedent={turnover.moisPrec} />
          </div>
        </FadeInView>
        <FadeInView delay={700}>
          <div className="cursor-pointer" onClick={() => navigate('/etablissement/missions?statut=TERMINEE&periode=mois')}>
            <CarteKPI icone={CheckCircle} valeur={missionsCeMois} label="Missions terminées ce mois" couleurIcone="text-success" couleurFond="bg-success/10" />
          </div>
        </FadeInView>
      </div>

      {/* Top soignants + Prochaines missions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <FadeInView delay={800}>
          <TopSoignants soignants={topSoignants} etablissementId={etablissementId!} onSelectSoignant={(soignantId) => navigate(`/etablissement/soignants/${soignantId}`)} />
        </FadeInView>
        <FadeInView delay={900}>
          <ProchaineMissions missions={prochaines} />
        </FadeInView>
      </div>

      {/* Carte Commission Jolene */}
      {etab && (
        <CarteCommissionJolene etablissementId={etablissementId!} />
      )}

      {/* Widget Palier de Fidélité */}
      {etab && paliers.length > 0 && (
        <WidgetPalierFidelite etab={etab} paliers={paliers} missionsCeMois={missionsCeMois} />
      )}

      {/* Carte BFA Info */}
      {etab && (
        <CarteBFAInfo etablissementId={etablissementId!} />
      )}

      {/* Widget BFA (legacy) */}
      {etab && (
        <WidgetBFA etablissementId={etablissementId!} groupeId={etab.groupe_sante_id} />
      )}

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
        ) : (
          <EtatVide icone={ClipboardList} titre="Publiez votre première mission" sousTitre="Les soignants qualifiés de votre zone seront notifiés immédiatement" boutonLabel="Publier une mission" boutonRoute="/etablissement/missions/creer" />
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

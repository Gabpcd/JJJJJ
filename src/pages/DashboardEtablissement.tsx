import React, { useState, useEffect } from 'react';
import { handleErrorSilent } from '@/lib/handleError';
import { SkeletonDashboard, SkeletonList } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp, ClipboardList, FileText, Users, Star } from 'lucide-react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { CarteMission } from '@/components/CarteMission';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { EtatVide } from '@/components/EtatVide';
import { ChargementPage } from '@/components/ChargementPage';
import { FABCreerMission } from '@/components/FABCreerMission';
import { WidgetPalierFidelite } from '@/components/WidgetPalierFidelite';
import { WidgetBFA } from '@/components/WidgetBFA';
import { BadgePalier } from '@/components/BadgePalier';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { OnboardingGuide } from '@/components/OnboardingGuide';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

export default function DashboardEtablissement() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [etab, setEtab] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [kpi, setKpi] = useState({ ouvertes: 0, enCours: 0, terminees: 0, taux: 0 });
  const [loading, setLoading] = useState(true);
  const [erreurPartielle, setErreurPartielle] = useState(false);
  const [modalDupliquer, setModalDupliquer] = useState<any>(null);
  const [modalAnnuler, setModalAnnuler] = useState<any>(null);
  const [paliers, setPaliers] = useState<any[]>([]);
  const [missionsCeMois, setMissionsCeMois] = useState(0);
  const [missionsParSemaine, setMissionsParSemaine] = useState<any[]>([]);
  const [coutParMois, setCoutParMois] = useState<any[]>([]);
  const [favoris, setFavoris] = useState<any[]>([]);

  const charger = async () => {
    if (!user) return;
    let partialError = false;

    try {
      const debutMois = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();

      const [resEtab, resMissions, resPaliers, resMissionsCeMois, resSoignants] = await Promise.all([
        supabase.from('etablissements').select('id, nom, type, email_contact, groupe_sante_id, taux_commission_negocie, palier_commission_id, groupes_sante(nom), paliers_commission(nom)').eq('id', user.id).single(),
        supabase.from('missions')
          .select('id, intitule, description, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer, statut, est_urgente, niveau_urgence, soignant_assigne_id, cree_le')
          .eq('etablissement_id', user.id)
          .order('cree_le', { ascending: false })
          .limit(5),
        supabase.from('paliers_commission').select('id, nom, missions_min, missions_max, ordre').eq('est_actif', true).order('ordre', { ascending: true }),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'TERMINEE').gte('fin_le', debutMois),
        supabase.rpc('fn_mes_soignants_etablissement'),
      ]);

      if (resEtab.error) { handleErrorSilent(resEtab.error, '[DashboardEtab] Erreur établissement'); partialError = true; }
      else if (resEtab.data) setEtab(resEtab.data);

      // Map soignant data by ID
      const sgMap: Record<string, any> = {};
      if (Array.isArray(resSoignants.data)) {
        for (const s of resSoignants.data) sgMap[s.id] = s;
      }

      if (resMissions.error) { handleErrorSilent(resMissions.error, '[DashboardEtab] Erreur missions'); partialError = true; }
      else if (resMissions.data) setMissions(resMissions.data.map((m: any) => ({
        ...m,
        soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null,
      })));

      if (resPaliers.data) setPaliers(resPaliers.data);
      setMissionsCeMois(resMissionsCeMois.count ?? 0);

      // Graphiques + favoris (non-bloquant)
      try {
        const now = new Date();
        // Missions terminées par semaine (8 dernières semaines)
        const semaines: { label: string; count: number }[] = [];
        for (let i = 7; i >= 0; i--) {
          const end = new Date(now);
          end.setDate(end.getDate() - i * 7);
          const start = new Date(end);
          start.setDate(start.getDate() - 7);
          const { count } = await supabase.from('missions').select('id', { count: 'exact', head: true })
            .eq('etablissement_id', user.id).eq('statut', 'TERMINEE')
            .gte('fin_le', start.toISOString()).lt('fin_le', end.toISOString());
          semaines.push({ label: `S-${i}`, count: count ?? 0 });
        }
        setMissionsParSemaine(semaines);

        // Coût par mois (4 derniers mois)
        const mois: { label: string; total: number }[] = [];
        for (let i = 3; i >= 0; i--) {
          const moisDate = new Date(now.getFullYear(), now.getMonth() - i, 1);
          const finMois = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59);
          const { data: mData } = await supabase.from('missions').select('total_brut')
            .eq('etablissement_id', user.id).eq('statut', 'TERMINEE')
            .gte('fin_le', moisDate.toISOString()).lte('fin_le', finMois.toISOString());
          const total = (mData || []).reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
          mois.push({ label: moisDate.toLocaleDateString('fr-FR', { month: 'short' }), total });
        }
        setCoutParMois(mois);

        // Favoris
        const { data: favData } = await (supabase.from('favoris' as any) as any).select('soignant_id, cree_le').eq('etablissement_id', user.id).order('cree_le', { ascending: false }).limit(5);
        if (favData && favData.length > 0) {
          const sgIds = favData.map((f: any) => f.soignant_id);
          const enriched = sgIds.map((sid: string) => ({ ...(sgMap[sid] || { id: sid }), soignant_id: sid }));
          setFavoris(enriched);
        }
      } catch {}

    } catch (err) {
      handleErrorSilent(err, '[DashboardEtab] Erreur critique');
      partialError = true;
    }

    // KPI
    try {
      const [resO, resEC, resT, resTotal, resAssigned] = await Promise.all([
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'OUVERTE'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'EN_COURS'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'TERMINEE').gte('modifie_le', new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id),
        supabase.from('missions').select('id', { count: 'exact', head: true }).eq('etablissement_id', user.id).not('soignant_assigne_id', 'is', null),
      ]);

      if (resO.error || resEC.error || resT.error || resTotal.error || resAssigned.error) partialError = true;

      const totalN = resTotal.count ?? 0;
      setKpi({
        ouvertes: resO.count ?? 0,
        enCours: resEC.count ?? 0,
        terminees: resT.count ?? 0,
        taux: totalN > 0 ? Math.round(((resAssigned.count ?? 0) / totalN) * 100) : 0,
      });
    } catch (err) {
      handleErrorSilent(err, '[DashboardEtab] Erreur KPI');
      partialError = true;
    }

    // Audit HDS (non bloquant)
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

  useEffect(() => { charger(); }, [user]);

  const handleAnnuler = async (mission: any) => {
    const { data, error } = await supabase.rpc('fn_annuler_mission_etablissement' as any, { p_mission_id: mission.id });
    if (error) afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    else if ((data as any)?.success === false) afficherNotification({ type: 'erreur', message: (data as any).error });
    else { afficherNotification({ type: 'succes', message: 'Mission annulée.' }); charger(); }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonDashboard /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
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

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <FadeInView delay={0}><CarteKPI icone={Briefcase} valeur={kpi.ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" /></FadeInView>
        <FadeInView delay={100}><CarteKPI icone={PlayCircle} valeur={kpi.enCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" /></FadeInView>
        <FadeInView delay={200}><CarteKPI icone={CheckCircle} valeur={kpi.terminees} label="Terminées ce mois" couleurIcone="text-success" couleurFond="bg-success/10" /></FadeInView>
        <FadeInView delay={300}><CarteKPI icone={TrendingUp} valeur={`${kpi.taux}%`} label="Taux d'occupation" couleurIcone={kpi.taux > 70 ? 'text-success' : 'text-warning'} couleurFond={kpi.taux > 70 ? 'bg-success/10' : 'bg-warning/10'} /></FadeInView>
      </div>

      {/* Widget Palier de Fidélité */}
      {etab && paliers.length > 0 && (
        <WidgetPalierFidelite etab={etab} paliers={paliers} missionsCeMois={missionsCeMois} />
      )}

      {/* Widget BFA */}
      {etab && (
        <WidgetBFA etablissementId={user!.id} groupeId={etab.groupe_sante_id} />
      )}

      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Dernières missions</h2>
          <button onClick={() => navigate('/etablissement/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
        </div>

        {missions.length > 0 ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {missions.map(m => (
              <CarteMission key={m.id} mission={m}
                onDupliquer={(m) => setModalDupliquer(m)}
                onAnnuler={(m) => setModalAnnuler(m)}
                onRepublier={(m) => navigate(`/etablissement/missions/creer?dupliquer=${m.id}`)}
              />
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

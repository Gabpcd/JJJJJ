import React, { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { SkeletonDashboard } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { CheckCircle, Star, Clock, ShieldCheck, ShieldAlert, Circle, CheckCircle2, Search, Info, X, AlertCircle, Banknote, Rocket, MapPin, Bell, TrendingUp, Activity, GraduationCap, Home, CalendarDays } from 'lucide-react';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { CarteProposition } from '@/components/CarteProposition';
import { PROFESSIONS_NON_LIBERAL } from '@/lib/constantes';
import { RappelsFiscaux } from '@/components/RappelsFiscaux';
import { BadgeRPPS } from '@/components/BadgeRPPS';
import { WidgetAllerPointer } from '@/components/WidgetAllerPointer';
import { BandeauOubliDepart } from '@/components/BandeauOubliDepart';
import { BadgeNiveau } from '@/components/BadgeNiveau';
import { BandeauGoalGradient, CelebrationJalonManager } from '@/components/GoalGradient';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { EtatVide, IllustrationTirelire } from '@/components/EtatVide';
import { JaugeProgression } from '@/components/JaugeProgression';
import { OnboardingGuide } from '@/components/OnboardingGuide';
import { BarreCompletionProfil } from '@/components/BarreCompletionProfil';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { CompteurHebdomadaire } from '@/components/CompteurHebdomadaire';
import { BandeauAlerte48h } from '@/components/BandeauAlerte48h';
import { GraphiqueGains6Mois } from '@/components/GraphiqueGains6Mois';
import { ProgressionCirculaire3200h } from '@/components/ProgressionCirculaire3200h';
import { ProchainBadgeWidget } from '@/components/ProchainBadgeWidget';
import { CalendrierMiniSemaine } from '@/components/CalendrierMiniSemaine';
import { JaugeSpeedometer } from '@/components/JaugeSpeedometer';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TYPES_DOCUMENTS } from '@/lib/documents';
import { format, differenceInDays, startOfWeek, addDays } from 'date-fns';
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

function calculerCompletionProfil(s: SoignantData) {
  const checks: [boolean, string][] = [
    [!!s.prenom, 'Prénom'], [!!s.nom, 'Nom'], [!!s.telephone, 'Téléphone'],
    [!!s.date_naissance, 'Date de naissance'], [!!s.profession, 'Profession'],
    [!!s.type_contrat, 'Type de contrat'], [!!(s.numero_rpps || s.numero_adeli), 'Numéro RPPS/ADELI'],
    [!!(s.adresse_lat && s.adresse_lng), 'Adresse géolocalisée'],
    [!!s.tous_documents_valides, 'Documents validés'], [!!s.identite_verifiee, 'Identité vérifiée'],
  ];
  const completes = checks.filter(([ok]) => ok).map(([, l]) => l);
  const manquants = checks.filter(([ok]) => !ok).map(([, l]) => l);
  return { pourcentage: Math.round((completes.length / checks.length) * 100), manquants, completes };
}

export default function DashboardSoignant() {
  usePageTitle('Dashboard');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [mesMissions, setMesMissions] = useState<any[]>([]);
  const [docsExpirant, setDocsExpirant] = useState<any[]>([]);
  const [propositions, setPropositions] = useState<any[]>([]);
  const [heuresSemaine, setHeuresSemaine] = useState(0);
  const [loading, setLoading] = useState(true);
  const [missionProchaine, setMissionProchaine] = useState<any>(null);
  const [missionsOubliDepart, setMissionsOubliDepart] = useState<any[]>([]);
  const [gainsCeMois, setGainsCeMois] = useState({ net: 0, nb: 0 });
  const [missionsWeekend, setMissionsWeekend] = useState<any[]>([]);
  const [gains6Mois, setGains6Mois] = useState<{ debut_le: string; net_a_payer: number | null }[]>([]);
  const [missionsSemaine, setMissionsSemaine] = useState<{ debut_le: string; statut: string }[]>([]);
  const [badgeStats, setBadgeStats] = useState<BadgeStats | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const now = new Date();
      const jour = now.getDay();
      const lundi = new Date(now);
      lundi.setDate(now.getDate() - (jour === 0 ? 6 : jour - 1));
      lundi.setHours(0, 0, 0, 0);
      const dimanche = new Date(lundi);
      dimanche.setDate(lundi.getDate() + 7);

      const debutMois = new Date(now.getFullYear(), now.getMonth(), 1);
      const finMois = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

      // 6 months ago for gains chart
      const sixMoisAgo = new Date(now.getFullYear(), now.getMonth() - 5, 1);

      const { data: sg } = await supabase.from('soignants').select('prenom, nom, telephone, date_naissance, profession, type_contrat, numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng, tous_documents_valides, identite_verifiee, score_fiabilite, total_missions_terminees, heures_cumulees, eligible_conversion_3200h, type_exercice').eq('id', user.id).single();

      const profession = sg?.profession;

      let missionsQuery = supabase.from('missions').select('id, intitule, service, debut_le, fin_le, taux_horaire_base, est_urgente, etablissement_id').eq('statut', 'OUVERTE').order('debut_le', { ascending: true }).limit(3);
      if (profession) missionsQuery = missionsQuery.eq('profession_requise', profession);

      const [{ data: ms }, { data: mm }, { data: docs }, { data: msSemaine }, { data: missionsOubliees }, { data: gainsMois }, { data: gains6m }, { data: msSemaineCal }, { data: props }, { data: missionsTermineesData }] = await Promise.all([
        missionsQuery,
        supabase.from('missions').select('id, intitule, debut_le, fin_le, statut, etablissement_id').eq('soignant_assigne_id', user.id).in('statut', ['ASSIGNEE', 'EN_COURS']).order('debut_le', { ascending: true }).limit(3),
        supabase.from('documents_soignants').select('id, type_document, valide_jusqua, statut_verification').eq('soignant_id', user.id).is('supprime_le', null),
        supabase.from('missions').select('duree_heures').eq('soignant_assigne_id', user.id).in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE']).gte('debut_le', lundi.toISOString()).lt('debut_le', dimanche.toISOString()),
        supabase.from('missions').select('id, intitule, fin_le, presences(id, pointage_arrivee_le, pointage_depart_le)').eq('soignant_assigne_id', user.id).eq('statut', 'EN_COURS').lt('fin_le', new Date(Date.now() - 30 * 60000).toISOString()),
        supabase.from('missions').select('net_a_payer, net_estime').eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE').gte('debut_le', debutMois.toISOString()).lte('debut_le', finMois.toISOString()),
        supabase.from('missions').select('debut_le, net_a_payer').eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE').gte('debut_le', sixMoisAgo.toISOString()).order('debut_le', { ascending: true }),
        supabase.from('missions').select('debut_le, statut').eq('soignant_assigne_id', user.id).in('statut', ['ASSIGNEE', 'EN_COURS']).gte('debut_le', lundi.toISOString()).lt('debut_le', dimanche.toISOString()),
        // Propositions from pool
        supabase.from('candidatures').select('id, mission_id, cree_le, missions(id, intitule, debut_le, fin_le, taux_horaire_base, etablissement_id, est_urgente)').eq('soignant_id', user.id).eq('statut', 'PROPOSEE').order('cree_le', { ascending: false }).limit(5),
        // Missions terminées réelles (pour compteur fiable)
        supabase.from('missions').select('duree_heures').eq('soignant_assigne_id', user.id).eq('statut', 'TERMINEE'),
      ]);

      // Enrich missions with safe establishment data
      const allMissionItems = [...(ms || []), ...(mm || [])];
      if (allMissionItems.length > 0) {
        const { fetchEtablissementsSafe } = await import('@/lib/etablissements');
        const etabMap = await fetchEtablissementsSafe(allMissionItems.map((m: any) => m.etablissement_id));
        const enrichMission = (m: any) => ({ ...m, etablissements: etabMap[m.etablissement_id] || null });
        if (ms) setMissions(ms.map(enrichMission) as any);
        if (mm) setMesMissions(mm.map(enrichMission) as any);
      } else {
        if (ms) setMissions(ms as any);
        if (mm) setMesMissions(mm as any);
      }
      if (sg) setSoignant(sg as any);
      if (msSemaine) {
        setHeuresSemaine(msSemaine.reduce((t: number, m: any) => t + (m.duree_heures || 0), 0));
      }
      if (docs) {
        setDocsExpirant((docs as any[]).filter(d =>
          d.valide_jusqua && d.statut_verification === 'VERIFIE' &&
          new Date(d.valide_jusqua) > new Date() &&
          differenceInDays(new Date(d.valide_jusqua), new Date()) < 30
        ));
      }
      if (mm) {
        const prochaine = (mm as any[]).find(m => {
          const mins = (new Date(m.debut_le).getTime() - Date.now()) / 60000;
          return mins > -30 && mins <= 60;
        });
        if (prochaine) setMissionProchaine(prochaine);
      }
      if (missionsOubliees) {
        const oublis = (missionsOubliees as any[]).filter(m =>
          m.presences?.length > 0 && m.presences[0].pointage_arrivee_le && !m.presences[0].pointage_depart_le
        );
        setMissionsOubliDepart(oublis);
      }
      if (gainsMois) {
        const net = (gainsMois as any[]).reduce((s: number, m: any) => s + (m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0)), 0);
        setGainsCeMois({ net, nb: (gainsMois as any[]).length });
      }
      if (gains6m) setGains6Mois(gains6m as any);
      if (msSemaineCal) setMissionsSemaine(msSemaineCal as any);
      if (props) setPropositions(props as any);

      // Compute real counts from mission data
      const realMissionsTerminees = missionsTermineesData?.length || 0;
      const realHeuresCumulees = missionsTermineesData?.reduce((t: number, m: any) => t + (m.duree_heures || 0), 0) || 0;

      // Override soignant data with real counts if higher
      if (sg) {
        sg.total_missions_terminees = Math.max(sg.total_missions_terminees || 0, realMissionsTerminees);
        sg.heures_cumulees = Math.max(sg.heures_cumulees || 0, realHeuresCumulees);
      }

      // Badge stats (simple computation from soignant data)
      if (sg) {
        setBadgeStats({
          missionsTerminees: sg.total_missions_terminees || 0,
          scoreFiabilite: sg.score_fiabilite || 0,
          heuresCumulees: sg.heures_cumulees || 0,
          annulations: 0,
          missionsNuit: 0,
          missionsWeekend: 0,
          maxMissionsMemeEtab: 0,
          retards: 0,
          totalMissions: sg.total_missions_terminees || 0,
        });
      }

      // Missions weekend
      if (profession) {
        const today = new Date();
        const dayOfWeek = today.getDay();
        const daysToSat = dayOfWeek === 0 ? 6 : (6 - dayOfWeek);
        const samedi = new Date(today);
        samedi.setDate(today.getDate() + daysToSat);
        samedi.setHours(0, 0, 0, 0);
        const lundiProchain = new Date(samedi);
        lundiProchain.setDate(samedi.getDate() + 2);
        lundiProchain.setHours(23, 59, 59);

        const { data: wkData } = await supabase.from('missions')
          .select('id, intitule, debut_le, fin_le, taux_horaire_base, est_urgente, etablissement_id')
          .eq('statut', 'OUVERTE')
          .eq('profession_requise', profession)
          .gte('debut_le', samedi.toISOString())
          .lte('debut_le', lundiProchain.toISOString())
          .order('debut_le', { ascending: true })
          .limit(3);

        if (wkData && wkData.length > 0) {
          const { fetchEtablissementsSafe } = await import('@/lib/etablissements');
          const etabMap2 = await fetchEtablissementsSafe(wkData.map((m: any) => m.etablissement_id));
          setMissionsWeekend(wkData.map((m: any) => ({ ...m, etablissements: etabMap2[m.etablissement_id] || null })));
        }
      }

      setLoading(false);
    };
    load();
  }, [user]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><SkeletonDashboard /></LayoutApp>;

  const profil = calculerCompletionProfil(soignant);
  const missionsTerminees = soignant.total_missions_terminees ?? 0;
  const score = soignant.score_fiabilite;
  const hasEvaluations = missionsTerminees > 0;
  const heures = soignant.heures_cumulees ?? 0;

  const aDocuments = !!(soignant as any).tous_documents_valides || missions.length > 0;

  return (
    <LayoutApp role="SOIGNANT">
      <OnboardingGuide role="SOIGNANT" userId={user!.id} />

      <BarreCompletionProfil
        nom={!!soignant.nom}
        rppsVerifie={!!(soignant as any).rpps_verifie}
        auMoinsUnDocument={aDocuments}
        adresseRenseignee={!!(soignant.adresse_lat && soignant.adresse_lng)}
        telephoneRenseigne={!!soignant.telephone}
      />

      <div className="mb-6">
        <div className="flex items-center gap-2 flex-wrap">
          <h1 className="text-xl font-bold text-foreground">Bonjour, <span className="text-primary">{soignant.prenom}</span> 👋</h1>
          <BadgeRPPS rppsVerifie={(soignant as any).rpps_verifie} rpps={(soignant as any).numero_rpps} profession={soignant.profession} />
        </div>
        {!soignant.tous_documents_valides ? (
          <p className="text-sm text-warning mt-1">⚠️ Complétez votre profil pour postuler aux missions</p>
        ) : (
          <p className="text-sm text-muted-foreground mt-1">Voici votre activité</p>
        )}
      </div>

      {/* 48h banner: hidden for LIBERAL, shown for SALARIE & MIXTE */}
      {soignant.type_exercice !== 'LIBERAL' && <BandeauAlerte48h heuresSemaine={heuresSemaine} />}

      {/* Cumul d'activité warning for MIXTE */}
      {soignant.type_exercice === 'MIXTE' && (
        <div className="bg-warning/5 border-l-4 border-warning p-4 rounded-r-xl mb-4">
          <p className="text-sm text-warning font-medium">
            ⚠️ Cumul d'activité : pensez à vérifier que vos heures sur Jolene sont compatibles avec votre contrat salarié.
          </p>
        </div>
      )}

      {/* Missions proposées depuis le pool */}
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

      {missionsOubliDepart.map(m => (
        <BandeauOubliDepart key={m.id} mission={m} onPointer={() => navigate('/soignant/presences')} />
      ))}

      {missionProchaine && <WidgetAllerPointer mission={missionProchaine} />}

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

      {profil.pourcentage < 100 ? (
        <div className="rounded-2xl bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 p-4 md:p-6 mb-6">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-sm font-semibold text-foreground">Profil complété à {profil.pourcentage}%</h2>
            <button onClick={() => navigate('/soignant/profil')} className="text-xs text-primary font-medium hover:underline">Compléter →</button>
          </div>
          <JaugeProgression valeur={profil.pourcentage} max={100} couleurBarre="bg-primary" couleurFond="bg-primary/10" />
          <div className="mt-3 grid grid-cols-2 gap-1.5">
            {profil.completes.map(c => <div key={c} className="flex items-center gap-1.5 text-xs text-primary"><CheckCircle2 className="h-3.5 w-3.5" />{c}</div>)}
            {profil.manquants.map(m => <div key={m} className="flex items-center gap-1.5 text-xs text-muted-foreground"><Circle className="h-3.5 w-3.5" />{m}</div>)}
          </div>
        </div>
      ) : (
        <div className="rounded-2xl bg-gradient-to-r from-success/5 to-primary/5 border border-success/20 p-4 mb-6 text-center">
          <p className="text-sm font-semibold text-success">✨ Profil complet — Vous êtes prêt(e) à postuler !</p>
        </div>
      )}

      {/* Tabs */}
      <Tabs defaultValue="accueil" className="mb-6">
        <TabsList className="w-full grid grid-cols-4 mb-4">
          <TabsTrigger value="accueil" className="text-xs gap-1"><Home className="h-3.5 w-3.5 hidden sm:block" />Accueil</TabsTrigger>
          <TabsTrigger value="activite" className="text-xs gap-1"><Activity className="h-3.5 w-3.5 hidden sm:block" />Activité</TabsTrigger>
          <TabsTrigger value="gains" className="text-xs gap-1"><TrendingUp className="h-3.5 w-3.5 hidden sm:block" />Gains</TabsTrigger>
          <TabsTrigger value="parcours" className="text-xs gap-1"><GraduationCap className="h-3.5 w-3.5 hidden sm:block" />Parcours</TabsTrigger>
        </TabsList>

        {/* ─── ONGLET ACCUEIL ─── */}
        <TabsContent value="accueil">
          {/* KPI */}
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 mb-6">
            <FadeInView delay={0}>
              <div className="cursor-pointer" onClick={() => navigate('/soignant/historique-missions')}>
                <CarteKPI icone={CheckCircle} valeur={missionsTerminees} label="Missions terminées" couleurIcone="text-success" couleurFond="bg-success/10" />
              </div>
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
              <div className="cursor-pointer" onClick={() => navigate('/soignant/historique-missions')}>
                <CarteKPI icone={Clock} valeur={`${heures}h`} label="Heures cumulées" sousLabel="sur 3 200h objectif" couleurIcone="text-purple-600" couleurFond="bg-purple-100" />
              </div>
            </FadeInView>
            <FadeInView delay={300}>
              <div className="cursor-pointer" onClick={() => navigate('/soignant/planning')}>
                <CarteKPI icone={CalendarDays} valeur={mesMissions.length} label="Planning" sousLabel="missions à venir" couleurIcone="text-info" couleurFond="bg-info/10" />
              </div>
            </FadeInView>
          </div>

          {/* Quick actions */}
          <div className="flex gap-3 mb-6 overflow-x-auto pb-1">
            <button onClick={() => navigate('/soignant/planning')} className="btn-secondary text-sm whitespace-nowrap flex items-center gap-2">
              <CalendarDays className="h-4 w-4" /> 📅 Voir mon planning
            </button>
            <button onClick={() => navigate('/soignant/missions')} className="btn-secondary text-sm whitespace-nowrap flex items-center gap-2">
              <Search className="h-4 w-4" /> Chercher des missions
            </button>
          </div>

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
                          <h3 className="font-semibold text-sm text-foreground truncate">{m.intitule}</h3>
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
              <EtatVide icone={Search} titre="Aucune mission disponible" sousTitre="De nouvelles missions sont publiées chaque jour. Revenez bientôt !" />
            )}
          </div>

          {/* Mes missions en cours */}
          {mesMissions.length > 0 && (
            <div className="mb-6">
              <div className="flex items-center justify-between mb-3">
                <h2 className="text-lg font-bold text-foreground">Mes missions en cours</h2>
                <button onClick={() => navigate('/soignant/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
              </div>
              <div className="space-y-3">
                {mesMissions.map((m: any) => (
                  <div key={m.id} onClick={() => navigate(`/soignant/missions/${m.id}`)} className="card-base hover:shadow-md cursor-pointer transition-all">
                    <div className="flex items-center justify-between mb-1">
                      <BadgeStatut statut={m.statut} />
                    </div>
                    <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                    <p className="text-xs text-muted-foreground mt-1">🏥 {m.etablissements?.nom} · {m.etablissements?.adresse_ville}</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      📅 {format(new Date(m.debut_le), "EEE d MMM · HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}
        </TabsContent>

        {/* ─── ONGLET ACTIVITÉ ─── */}
        <TabsContent value="activite">
          {/* Calendrier mini semaine */}
          <FadeInView>
            <CalendrierMiniSemaine missions={missionsSemaine} />
          </FadeInView>

          {/* Compteur hebdomadaire */}
          <div className="mb-6">
            <CompteurHebdomadaire />
          </div>

          {/* Progression 3200h + Prochain badge */}
          {!PROFESSIONS_NON_LIBERAL.includes(soignant.profession) && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-6">
              <FadeInView delay={0}>
                <ProgressionCirculaire3200h heures={heures} />
              </FadeInView>
              <FadeInView delay={100}>
                {badgeStats && <ProchainBadgeWidget stats={badgeStats} />}
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
                          <h3 className="font-semibold text-sm text-foreground truncate">{m.intitule}</h3>
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
        </TabsContent>

        {/* ─── ONGLET GAINS ─── */}
        <TabsContent value="gains">
          {/* Graphique gains 6 mois */}
          <FadeInView>
            {gains6Mois.length > 0 ? (
              <GraphiqueGains6Mois missions={gains6Mois} />
            ) : (
              <div className="mb-6">
                <EtatVide illustration={<IllustrationTirelire />} titre="Pas encore de gains" sousTitre="Vos gains apparaîtront ici après votre première mission terminée." />
              </div>
            )}
          </FadeInView>

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

          {/* Rappels fiscaux libéral */}
          {soignant.type_contrat === 'LIBERAL' && (
            <RappelsFiscaux />
          )}
        </TabsContent>

        {/* ─── ONGLET PARCOURS ─── */}
        <TabsContent value="parcours">
          {!PROFESSIONS_NON_LIBERAL.includes(soignant.profession) ? (
            <div className="space-y-4">
              <div className="rounded-2xl bg-gradient-to-r from-purple-50 to-purple-100/50 dark:from-purple-950/20 dark:to-purple-900/10 border border-purple-200 dark:border-purple-800 p-4 md:p-6 cursor-pointer" onClick={() => navigate('/soignant/parcours-3200h')}>
                <div className="flex items-center justify-between mb-1">
                  <h2 className="text-base font-bold text-foreground">Mon parcours vers le libéral</h2>
                  <span className="text-xs text-primary font-medium">Détails →</span>
                </div>
                <p className="text-xs text-muted-foreground mb-4">Objectif : 3 200 heures d'exercice</p>
                <JaugeProgression valeur={heures} max={3200} marqueurs={[800, 1600, 2400, 3200]} couleurBarre="bg-gradient-to-r from-primary to-primary-dark" couleurFond="bg-primary/10" />
                <div className="flex justify-between text-[10px] text-muted-foreground mt-1.5"><span>0h</span><span>800h</span><span>1600h</span><span>2400h</span><span>3200h</span></div>
                <p className="text-sm font-semibold text-foreground mt-3"><span className="text-primary">{heures}h</span> / 3 200h</p>
              </div>

              {heures >= 800 && (soignant as any).statut_liberal !== 'ACTIF' && (
                <div className="rounded-2xl bg-gradient-to-r from-primary/5 to-purple-50 dark:to-purple-900/10 border border-primary/20 p-4 cursor-pointer hover:shadow-md transition-all" onClick={() => navigate('/soignant/passer-en-liberal')}>
                  <div className="flex items-center gap-3">
                    <div className="rounded-xl p-2.5 bg-primary/10"><Rocket className="h-5 w-5 text-primary" /></div>
                    <div>
                      <p className="text-sm font-bold text-foreground">🎉 Passer en libéral</p>
                      <p className="text-xs text-muted-foreground">Vous êtes éligible ! Découvrez le module Free Transition.</p>
                      <p className="text-xs text-primary mt-0.5">Commencer →</p>
                    </div>
                  </div>
                </div>
              )}

              {/* Prévoyance CTA */}
              {!(soignant as any).prevoyance_inscrit && (
                <div className="rounded-2xl bg-gradient-to-r from-violet-50 to-purple-50 dark:from-violet-950/20 dark:to-purple-900/10 border border-violet-200 dark:border-violet-800 p-4 cursor-pointer" onClick={() => navigate('/soignant/prevoyance')}>
                  <h3 className="text-sm font-bold text-foreground mb-1">🛡️ Protégez-vous avec la Prévoyance Jolene</h3>
                  <p className="text-xs text-muted-foreground mb-2">Assurance santé subventionnée jusqu'à 30%. Bonus : +3 points de fiabilité.</p>
                  <span className="text-xs text-primary font-medium">Découvrir les plans →</span>
                </div>
              )}
            </div>
          ) : (
            <div className="rounded-2xl bg-gradient-to-r from-blue-50 to-cyan-50 dark:from-blue-950/20 dark:to-cyan-900/10 border border-blue-200 dark:border-blue-800 p-4">
              <p className="text-sm font-semibold text-foreground">💊 Vous exercez en pharmacie d'officine</p>
              <p className="text-xs text-muted-foreground mt-1">Les missions sont en CDD de remplacement.</p>
            </div>
          )}
        </TabsContent>
      </Tabs>
    </LayoutApp>
  );
}

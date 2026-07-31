import React, { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { SkeletonList } from '@/components/SkeletonCard';
import { FadeInView } from '@/components/FadeInView';
import { AlertTriangle, Briefcase, History, RefreshCw } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { EmptyState, IllustrationBoussole } from '@/components/ui/EmptyState';
import { CarteMissionSoignant } from '@/components/CarteMissionSoignant';
import { NoteNetEstime } from '@/components/NoteNetEstime';
import { usePullToRefresh } from '@/hooks/usePullToRefresh';
import { IndicateurPullToRefresh } from '@/components/IndicateurPullToRefresh';
import { estMultiJours } from '@/lib/format-mission';
import { CarteSerie, extraireSerieId } from '@/components/CarteSerie';
import { FiltresMissions, type FiltresMissionsState } from '@/components/FiltresMissions';
import { BandeauAlerte48h } from '@/components/BandeauAlerte48h';
import { BandeauProfilIncomplet } from '@/components/BandeauProfilIncomplet';
import { BadgeStatut } from '@/components/BadgeStatut';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { calculerDistanceKm } from '@/lib/geo';
import { getLabelProfession, extraireContratPreference, missionCompatibleContrat, getTypesContratSoignant } from '@/lib/constantes';
import { getMissionsCompatiblesFilter } from '@/lib/profession-hierarchy';
import { ajouterJoursCivilsParis, debutSemaineParis, formatParis } from '@/lib/date-heure-paris';
import { handleErrorSilent } from '@/lib/handleError';
import { netEstimeAfficheMission } from '@/lib/missionFinanceDisplay';
import {
  ajouterRepliMissionPonctuelle,
  creneauxPrevisionnels,
  prochainCreneauPointage,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import {
  construireOccurrencesPlanning,
  decouperOccurrencesParJour,
  type CreneauMissionPlanifiable,
} from '@/lib/occurrences-planning';

type Onglet = 'candidatures' | 'disponibles' | 'mes_missions' | 'historique';

interface SoignantData {
  profession: string;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number;
  tous_documents_valides: boolean;
  type_contrat: string | null;
  types_contrat_acceptes: string | null;
}

type GroupeItem = { type: 'single'; mission: any } | { type: 'serie'; serieId: string; missions: any[] };

async function enrichirAvecPlanning<T extends { id: string; debut_le: string; fin_le: string }>(
  missions: T[],
): Promise<Array<T & {
  creneaux: CreneauPointage[];
  prochainCreneau: CreneauPointage | null;
  nb_creneaux_planifies: number;
  duree_planifiee_heures: number;
}>> {
  if (missions.length === 0) return [];

  const { data, error } = await supabase
    .from('mission_creneaux')
    .select('id, mission_id, debut, fin, est_pause, type_creneau')
    .in('mission_id', missions.map((mission) => mission.id))
    .eq('type_creneau', 'PREVISIONNEL')
    .eq('est_pause', false)
    .order('debut', { ascending: true });
  if (error) throw error;

  const parMission: Record<string, CreneauPointage[]> = {};
  (data || []).forEach((creneau) => {
    (parMission[creneau.mission_id] ||= []).push(creneau);
  });
  const maintenant = new Date();

  return missions.map((mission) => {
    const creneaux = ajouterRepliMissionPonctuelle(parMission[mission.id] || [], mission);
    const planifies = creneauxPrevisionnels(creneaux);
    return {
      ...mission,
      creneaux,
      prochainCreneau: prochainCreneauPointage(creneaux, maintenant),
      nb_creneaux_planifies: planifies.length,
      duree_planifiee_heures: planifies.reduce((total, creneau) => {
        if (!creneau.fin) return total;
        return total + Math.max(
          0,
          (new Date(creneau.fin).getTime() - new Date(creneau.debut).getTime()) / 3_600_000,
        );
      }, 0),
    };
  });
}

export default function MissionsSoignant() {
  usePageTitle('Missions');
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  // Refonte nav : on accepte `?tab=a-venir|passees` (cible des redirects
  // mes-matches → /missions et planning → /missions?tab=a-venir) en plus du
  // legacy `?onglet=mes_missions|historique`.
  const tabParam = searchParams.get('tab');
  const ongletParam = searchParams.get('onglet');
  // Cette page = « Mes missions » : Candidatures (en attente) · À venir · Passées.
  // La recherche de missions disponibles vit uniquement dans /recherche-missions.
  const [onglet, setOnglet] = useState<Onglet>(
    tabParam === 'candidatures' ? 'candidatures'
      : tabParam === 'passees' || ongletParam === 'historique' ? 'historique'
        : 'mes_missions'
  );
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [candidatures, setCandidatures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 50;
  const [filtres, setFiltres] = useState<FiltresMissionsState | null>(null);
  // Pull-to-refresh (Lot 6b.3) : tirer en haut de page relance le fetch.
  const [refreshTick, setRefreshTick] = useState(0);
  const { pullDistance, refreshing } = usePullToRefresh(async () => {
    setRefreshTick(t => t + 1);
    await new Promise(r => setTimeout(r, 700));
  });
  const [heuresSemaine, setHeuresSemaine] = useState(0);
  const [nbAffiche, setNbAffiche] = useState(20);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides, type_contrat, types_contrat_acceptes, type_exercice')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (data) setSoignant(data as any); }).then(undefined, (err) => handleErrorSilent(err, 'MissionsSoignant.soignant'));

    const lundi = debutSemaineParis(new Date());
    const finSemaine = ajouterJoursCivilsParis(lundi, 7);
    const chargerHeuresSemaine = async () => {
      const { data: missionsSemaine, error: missionsError } = await supabase
        .from('missions')
        .select('id, debut_le, fin_le, duree_heures')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .gt('fin_le', lundi.toISOString())
        .lt('debut_le', finSemaine.toISOString());
      if (missionsError) throw missionsError;
      if (!missionsSemaine?.length) {
        setHeuresSemaine(0);
        return;
      }
      const { data: creneauxSemaine, error: creneauxError } = await supabase
        .from('mission_creneaux')
        .select('id, mission_id, debut, fin, est_pause, type_creneau')
        .in('mission_id', missionsSemaine.map((mission) => mission.id));
      if (creneauxError) throw creneauxError;
      const occurrences = decouperOccurrencesParJour(construireOccurrencesPlanning(
        missionsSemaine,
        (creneauxSemaine || []) as CreneauMissionPlanifiable[],
      )).filter((occurrence) => (
        new Date(occurrence.debut_le) >= lundi
        && new Date(occurrence.debut_le) < finSemaine
      ));
      setHeuresSemaine(occurrences.reduce((total, occurrence) => total + occurrence.duree_heures, 0));
    };
    void chargerHeuresSemaine().catch((err) => handleErrorSilent(err, 'MissionsSoignant.heuresSemaine'));
  }, [user]);

  useEffect(() => {
    if (!user) return;
    if (!soignant && onglet !== 'disponibles' && onglet !== 'candidatures') { setLoading(false); setMissions([]); return; }
    setLoading(true);
    setErreurChargement(null);
    const fetchMissions = async () => {
      try {
        const maintenantIso = new Date().toISOString();

        // Onglet Candidatures : candidatures en attente de réponse de l'établissement.
        if (onglet === 'candidatures') {
          const { data, error } = await supabase
            .from('candidatures')
            .select('id, statut, message, type_contrat_choisi, cree_le, missions(id, intitule, debut_le, fin_le, taux_horaire_base, net_estime, etablissements(nom, adresse_ville))')
            .eq('soignant_id', user.id)
            .in('statut', ['EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB'])
            .order('cree_le', { ascending: false });
          if (error) throw error;
          const candidaturesValides = (data ?? []).filter((c: any) => c.missions);
          const missionsCandidatures = await enrichirAvecPlanning(
            candidaturesValides.map((candidature: any) => candidature.missions),
          );
          const planningParMission = new Map(
            missionsCandidatures.map((mission) => [mission.id, mission]),
          );
          setCandidatures(candidaturesValides.map((candidature: any) => ({
            ...candidature,
            missions: planningParMission.get(candidature.missions.id) ?? candidature.missions,
          })));
          return;
        }

        let query = supabase.from('missions').select(`
          id, intitule, description, service, profession_requise,
          specialite_medicale_requise, accepte_non_specialises,
          debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
          total_brut, net_a_payer, net_estime, est_urgente, niveau_urgence, statut,
          soignant_assigne_id, cree_le, etablissement_id, type_contrat_recherche,
          type_contrat_applique, choix_contrat_soignant
        `);

        if (onglet === 'disponibles') {
          query = query.eq('statut', 'OUVERTE').gte('debut_le', maintenantIso);
          if (soignant?.profession) {
            const orFiltre = getMissionsCompatiblesFilter(soignant.profession);
            if (orFiltre) {
              query = query.or(orFiltre);
            } else {
              query = query.eq('profession_requise', soignant.profession as any);
            }
          }
          // Contract type compatibility is handled client-side via missionCompatibleContrat
          query = query.order('est_urgente', { ascending: false }).order('niveau_urgence', { ascending: false }).order('debut_le', { ascending: true });
          if (filtres?.dateDebut) query = query.gte('debut_le', filtres.dateDebut);
          if (filtres?.dateFin) query = query.lte('debut_le', filtres.dateFin);
          if (filtres?.tauxMin && filtres.tauxMin > 0) query = query.gte('taux_horaire_base', filtres.tauxMin);
        } else if (onglet === 'mes_missions') {
          query = query.eq('soignant_assigne_id', user.id)
            .in('statut', ['ASSIGNEE', 'EN_COURS']).gte('fin_le', maintenantIso).order('debut_le', { ascending: true });
        } else {
          query = query.eq('soignant_assigne_id', user.id)
            .in('statut', ['TERMINEE', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT', 'ABSENCE'])
            .order('debut_le', { ascending: false });
        }

        // M1: la requête est cumulative ; remplacer la liste évite les doublons
        // quand l'utilisateur demande la page suivante.
        query = query.range(0, (page + 1) * PAGE_SIZE - 1);

        const { data, error } = await query;
        if (error) throw error;
        const enriched = data ? await enrichirEtablissements(data as any[]) : [];
        setMissions(await enrichirAvecPlanning(enriched as any[]));
      } catch (err) {
        handleErrorSilent(err, 'MissionsSoignant.chargement');
        setMissions([]);
        setCandidatures([]);
        setErreurChargement('Impossible de charger les missions et leurs horaires.');
      } finally {
        setLoading(false);
      }
    };
    void fetchMissions();
  }, [user, soignant, onglet, filtres, page, refreshTick]);

  // Reset pagination when tab/filters change
  useEffect(() => { setNbAffiche(20); setPage(0); }, [onglet, filtres]);

  const missionsAvecDistance = useMemo(() => {
    const typesContrat = soignant ? getTypesContratSoignant(soignant) : ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];
    let result = missions.map(m => ({
      ...m,
      distance_km: calculerDistanceKm(soignant?.adresse_lat ?? null, soignant?.adresse_lng ?? null, m.etablissements?.adresse_lat ?? null, m.etablissements?.adresse_lng ?? null),
    }));

    // Filter by contract type compatibility (only for available missions)
    if (onglet === 'disponibles') {
      result = result.filter(m => {
        const type = m.type_contrat_recherche || extraireContratPreference(m.description);
        if (type === 'TOUS') return true;
        // Use soignant's contract types to check compatibility
        return missionCompatibleContrat(type, typesContrat);
      });
    }

    if (onglet === 'disponibles' && filtres) {
      result = result.filter(m => m.distance_km === null || m.distance_km <= filtres.rayonKm);
    }

    if (filtres?.tri === 'proximite') result.sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999));
    else if (filtres?.tri === 'taux') result.sort((a, b) => b.taux_horaire_base - a.taux_horaire_base);
    else if (filtres?.tri === 'duree') result.sort((a, b) => (a.duree_heures ?? 0) - (b.duree_heures ?? 0));

    return result;
  }, [missions, soignant, filtres, onglet]);

  // Group by serie for 'disponibles' tab
  const groupes = useMemo((): GroupeItem[] => {
    if (onglet !== 'disponibles') return missionsAvecDistance.map(m => ({ type: 'single' as const, mission: m }));

    const seriesMap = new Map<string, any[]>();
    const singles: any[] = [];

    for (const m of missionsAvecDistance) {
      const sid = extraireSerieId(m.description);
      if (sid) {
        if (!seriesMap.has(sid)) seriesMap.set(sid, []);
        seriesMap.get(sid)!.push(m);
      } else {
        singles.push(m);
      }
    }

    const result: GroupeItem[] = [];
    for (const [serieId, ms] of seriesMap) {
      if (ms.length >= 2) {
        result.push({ type: 'serie', serieId, missions: ms });
      } else {
        singles.push(...ms);
      }
    }
    for (const m of singles) {
      result.push({ type: 'single', mission: m });
    }
    return result;
  }, [missionsAvecDistance, onglet]);

  const onglets: { id: Onglet; label: string; count?: number }[] = [
    { id: 'candidatures', label: 'Candidatures' },
    { id: 'mes_missions', label: 'À venir' },
    { id: 'historique', label: 'Passées' },
  ];

  const gererNavigationOnglets = (event: React.KeyboardEvent<HTMLButtonElement>, index: number) => {
    let prochainIndex: number | null = null;
    if (event.key === 'ArrowRight') prochainIndex = (index + 1) % onglets.length;
    if (event.key === 'ArrowLeft') prochainIndex = (index - 1 + onglets.length) % onglets.length;
    if (event.key === 'Home') prochainIndex = 0;
    if (event.key === 'End') prochainIndex = onglets.length - 1;
    if (prochainIndex === null) return;

    event.preventDefault();
    const prochainOnglet = onglets[prochainIndex].id;
    setOnglet(prochainOnglet);
    document.getElementById(`missions-tab-${prochainOnglet}`)?.focus();
  };

  return (
    <LayoutApp role="SOIGNANT">
      <IndicateurPullToRefresh distance={pullDistance} refreshing={refreshing} />
      <h1 className="text-xl font-bold text-foreground mb-4">Mes missions</h1>

      {/* Doublon « Découvrir / Recherche » retiré : la découverte de missions vit
          dans l'onglet « Missions » de la barre du bas (swipe + recherche). Cette
          page = candidatures / à venir / passées. Les états vides renvoient déjà
          vers /recherche-missions pour la conversion. */}

      {(!soignant || !soignant.profession) && <BandeauProfilIncomplet />}
      <div role="tablist" aria-label="Catégories de missions" className="flex border-b border-border mb-4 overflow-x-auto">
        {onglets.map((o, index) => (
          <button
            key={o.id}
            type="button"
            id={`missions-tab-${o.id}`}
            role="tab"
            aria-selected={onglet === o.id}
            aria-controls="missions-panel"
            tabIndex={onglet === o.id ? 0 : -1}
            onClick={() => setOnglet(o.id)}
            onKeyDown={(event) => gererNavigationOnglets(event, index)}
            className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 transition-colors
              ${onglet === o.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
            {o.label}
          </button>
        ))}
      </div>

      <div
        id="missions-panel"
        role="tabpanel"
        aria-labelledby={`missions-tab-${onglet}`}
        tabIndex={0}
        className="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
      >
        {onglet === 'disponibles' && (
          <>
            <BandeauAlerte48h heuresSemaine={heuresSemaine} />
            <FiltresMissions rayonDefaut={soignant?.rayon_deplacement_km} onFiltreChange={setFiltres} />
          </>
        )}

        {loading ? <SkeletonList count={4} /> : erreurChargement ? (
          <div className="card-base border-destructive/30" role="alert">
            <div className="flex items-start gap-3">
              <AlertTriangle className="h-5 w-5 shrink-0 text-destructive" aria-hidden="true" />
              <div>
                <p className="font-semibold text-foreground">Missions momentanément indisponibles</p>
                <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
                <button
                  type="button"
                  onClick={() => setRefreshTick((valeur) => valeur + 1)}
                  className="mt-3 inline-flex items-center gap-1.5 text-sm font-semibold text-primary hover:underline"
                >
                  <RefreshCw className="h-4 w-4" /> Réessayer
                </button>
              </div>
            </div>
          </div>
        ) : (
          <>
          {onglet === 'disponibles' && (
            <p className="text-sm text-muted-foreground mb-3">{missionsAvecDistance.length} mission{missionsAvecDistance.length !== 1 ? 's' : ''} trouvée{missionsAvecDistance.length !== 1 ? 's' : ''}</p>
          )}
          {onglet === 'candidatures' && (
            candidatures.length > 0 ? (
              <div className="space-y-2">
                {candidatures.map((c: any) => {
                  const m = c.missions;
                  const creneauAffiche = m.prochainCreneau
                    ?? creneauxPrevisionnels(m.creneaux || [])[0]
                    ?? null;
                  const dateAffichee = creneauAffiche?.debut ?? m.debut_le;
                  const estSuperLike = (c.message || '').toLowerCase().includes('super-like');
                  return (
                    <div
                      key={c.id}
                      role="button"
                      tabIndex={0}
                      onClick={() => navigate(`/soignant/missions/${m.id}`)}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter' || event.key === ' ') {
                          event.preventDefault();
                          navigate(`/soignant/missions/${m.id}`);
                        }
                      }}
                      className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    >
                      <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                        <span className="text-[10px] font-semibold text-primary uppercase">{formatParis(dateAffichee, 'EEE')}</span>
                        <span className="text-lg font-bold text-primary leading-tight">{formatParis(dateAffichee, 'd')}</span>
                        <span className="text-[10px] text-primary">{formatParis(dateAffichee, 'MMM')}</span>
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-1.5 mb-0.5 flex-wrap">
                          <span className="badge-base bg-amber-100 text-amber-700 text-[10px]">⏳ En attente de réponse</span>
                          {estSuperLike && <span className="badge-base bg-jolene-butter-100 text-jolene-midnight border border-jolene-butter-300 text-[10px]">★ Super-like envoyé</span>}
                          {c.type_contrat_choisi && <span className="badge-base bg-muted text-muted-foreground text-[10px]">{c.type_contrat_choisi === 'LIBERAL' ? 'Libéral' : 'Salarié'}</span>}
                        </div>
                        <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          🏥 {m.etablissements?.nom || 'Établissement'}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                        </p>
                        <div className="flex items-center gap-3 mt-0.5 text-xs text-muted-foreground">
                          <span>
                            🕐 {creneauAffiche?.fin
                              ? `${formatParis(creneauAffiche.debut, "d MMM · HH'h'mm")} → ${formatParis(creneauAffiche.fin, "HH'h'mm")}`
                              : 'Planning détaillé à confirmer'}
                          </span>
                          {m.taux_horaire_base && <span className="text-primary font-semibold">{m.taux_horaire_base} €/h</span>}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <EmptyState mascotte="thinking" titre="Pas encore de candidature en attente"
                description="Swipe à droite ou postule à une mission : tes candidatures en attente de réponse apparaîtront ici."
                cta={{ label: 'Trouver une mission 🔥', onClick: () => navigate('/soignant/recherche-missions') }} />
            )
          )}
          {onglet === 'disponibles' && (
            groupes.length > 0 ? (
              <>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {groupes.slice(0, nbAffiche).map((g, i) => {
                    if (g.type === 'serie') {
                      return <FadeInView key={g.serieId} delay={i * 100}><CarteSerie missions={g.missions} role="soignant" soignant={soignant} /></FadeInView>;
                    }
                    return (
                      <FadeInView key={g.mission.id} delay={i * 100}>
                        <CarteMissionSoignant mission={g.mission} soignant={soignant}
                          onClick={() => navigate(`/soignant/missions/${g.mission.id}`)} />
                      </FadeInView>
                    );
                  })}
                </div>
                {nbAffiche < groupes.length && (
                  <div className="flex justify-center mt-6">
                    <button onClick={() => setNbAffiche(n => n + 20)} className="btn-secondary text-sm px-6">
                      Voir plus ({groupes.length - nbAffiche} restante{groupes.length - nbAffiche > 1 ? 's' : ''})
                    </button>
                  </div>
                )}
              </>
            ) : (
              <EmptyState
                illustration={<IllustrationBoussole />}
                titre="Aucune mission pour le moment"
                description="Les missions apparaîtront ici dès qu'un établissement en publiera une correspondant à ton profil."
                cta={{ label: 'Rechercher des missions →', onClick: () => navigate('/soignant/recherche-missions') }}
              />
            )
          )}

          {onglet === 'mes_missions' && (
            missionsAvecDistance.length > 0 ? (
              <div className="space-y-2">
                {missionsAvecDistance.map(m => {
                  const creneauAffiche = m.prochainCreneau;
                  const dateAffichee = creneauAffiche?.debut ?? m.debut_le;
                  const dureeCreneau = creneauAffiche?.fin
                    ? (new Date(creneauAffiche.fin).getTime() - new Date(creneauAffiche.debut).getTime()) / 3_600_000
                    : null;
                  return (
                    <div
                      key={m.id}
                      role="button"
                      tabIndex={0}
                      onClick={() => navigate(`/soignant/missions/${m.id}`)}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter' || event.key === ' ') {
                          event.preventDefault();
                          navigate(`/soignant/missions/${m.id}`);
                        }
                      }}
                      className="card-base hover:shadow-md cursor-pointer transition-all flex items-center gap-3 py-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    >
                      <div className="flex flex-col items-center justify-center rounded-xl bg-primary/10 px-3 py-1.5 min-w-[52px]">
                        <span className="text-[10px] font-semibold text-primary uppercase">{formatParis(dateAffichee, 'EEE')}</span>
                        <span className="text-lg font-bold text-primary leading-tight">{formatParis(dateAffichee, 'd')}</span>
                        <span className="text-[10px] text-primary">{formatParis(dateAffichee, 'MMM')}</span>
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <BadgeStatut statut={m.statut} />
                          {m.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px]" aria-label="Urgent">🔥 Urgent</span>}
                        </div>
                        <h3 className="font-semibold text-sm text-foreground truncate" title={m.intitule}>{m.intitule}</h3>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          🏥 {m.etablissements?.nom || 'Établissement'}{m.etablissements?.adresse_ville ? ` · ${m.etablissements.adresse_ville}` : ''}
                        </p>
                        <div className="flex items-center gap-3 mt-0.5 text-xs text-muted-foreground">
                          <span>
                            🕐 {creneauAffiche?.fin
                              ? `Prochain créneau : ${formatParis(creneauAffiche.debut, "d MMM · HH'h'mm")} → ${formatParis(creneauAffiche.fin, "HH'h'mm")} (${dureeCreneau?.toLocaleString('fr-FR', { maximumFractionDigits: 2 })}h)`
                              : m.nb_creneaux_planifies > 0
                                ? 'Tous les créneaux planifiés sont terminés'
                                : 'Planning détaillé à confirmer'}
                          </span>
                          {m.taux_horaire_base && <span className="text-primary font-semibold">{m.taux_horaire_base} €/h</span>}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <EmptyState icone={<Briefcase />} mascotte="thinking" titre="Tu n'as pas encore de mission en cours" description="Découvre les missions disponibles et postule !" cta={{ label: 'Voir les missions disponibles', onClick: () => navigate('/soignant/recherche-missions') }} />
            )
          )}

          {onglet === 'historique' && (
            missionsAvecDistance.length > 0 ? (
              <>
                <div className="space-y-3">
                  {missionsAvecDistance.slice(0, nbAffiche).map(m => (
                    <div
                      key={m.id}
                      role="button"
                      tabIndex={0}
                      onClick={() => navigate(`/soignant/missions/${m.id}`)}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter' || event.key === ' ') {
                          event.preventDefault();
                          navigate(`/soignant/missions/${m.id}`);
                        }
                      }}
                      className="card-base hover:shadow-md cursor-pointer transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                    >
                      <div className="flex items-center justify-between mb-2">
                        <BadgeStatut statut={m.statut} />
                        <span className="text-xs text-muted-foreground">
                          {estMultiJours(m)
                            ? `${formatParis(m.debut_le, 'd MMM')} → ${formatParis(m.fin_le, 'd MMM yyyy')}`
                            : formatParis(m.debut_le, 'd MMM yyyy')}
                        </span>
                      </div>
                      <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                      <p className="text-xs text-muted-foreground mt-1">🏥 {m.etablissements?.nom || 'Établissement'}</p>
                      {(() => {
                        const net = netEstimeAfficheMission(m);
                        return net != null && net > 0 ? (
                          <p className="text-sm font-bold text-primary mt-1">
                            Net estimé* : {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(net)}
                          </p>
                        ) : null;
                      })()}
                    </div>
                  ))}
                </div>
                {nbAffiche < missionsAvecDistance.length && (
                  <div className="flex justify-center mt-6">
                    <button onClick={() => setNbAffiche(n => n + 20)} className="btn-secondary text-sm px-6">
                      Voir plus ({missionsAvecDistance.length - nbAffiche} restante{missionsAvecDistance.length - nbAffiche > 1 ? 's' : ''})
                    </button>
                  </div>
                )}
                <NoteNetEstime className="mt-4" />
              </>
            ) : (
              <EmptyState icone={<History />} mascotte="empty" titre="Aucune mission dans l'historique"
                description="Tes missions terminées et annulées apparaîtront ici."
                cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
            )
          )}

          {missions.length === (page + 1) * PAGE_SIZE && (
            <button onClick={() => setPage(p => p + 1)} className="btn-secondary w-full mt-4">Charger plus de missions</button>
          )}
          </>
        )}
      </div>
    </LayoutApp>
  );
}

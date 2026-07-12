import React, { useState, useEffect, useMemo } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { SkeletonList } from '@/components/SkeletonCard';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { FadeInView } from '@/components/FadeInView';
import { Search, X } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteMission } from '@/components/CarteMission';
import { CarteSerie, extraireSerieId } from '@/components/CarteSerie';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { ModaleAnnulationMissionEtab } from '@/components/etablissement/ModaleAnnulationMissionEtab';
import { EmptyState, IllustrationMegaphone } from '@/components/ui/EmptyState';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

const STATUTS_FILTRES = [
  { valeur: '', label: 'Toutes' },
  { valeur: 'OUVERTE', label: 'Ouvertes' },
  { valeur: 'ASSIGNEE', label: 'Assignées' },
  { valeur: 'EN_COURS', label: 'En cours' },
  { valeur: 'TERMINEE', label: 'Terminées' },
  { valeur: 'EXPIREE', label: 'Expirées' },
  { valeur: 'ANNULEE_PAR_ETABLISSEMENT', label: 'Annulées' },
  { valeur: 'LITIGE', label: 'Litiges' },
];

type GroupeMission = { type: 'single'; mission: any } | { type: 'serie'; serieId: string; missions: any[] };

export default function ListeMissions() {
  usePageTitle('Mes missions');
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { user } = useAuth();
  const { etablissementId } = useEtablissementScope();
  const { afficherNotification } = useNotification();
  const queryClient = useQueryClient();
  const statutParam = searchParams.get('statut') ?? '';
  // Filter by period: 'mois' restricts to missions ending within the current calendar month (fin_le between 1st and last day)
  const periodeParam = searchParams.get('periode') === 'mois' ? 'mois' : '';
  const [filtreStatut, setFiltreStatut] = useState(STATUTS_FILTRES.some((s) => s.valeur === statutParam) ? statutParam : '');
  const [filtrePeriode, setFiltrePeriode] = useState(periodeParam);
  const [recherche, setRecherche] = useState('');
  const [modalDupliquer, setModalDupliquer] = useState<any>(null);
  const [modalAnnuler, setModalAnnuler] = useState<any>(null);
  const [modalAnnulerSerie, setModalAnnulerSerie] = useState<any[] | null>(null);
  const [nbAffiche, setNbAffiche] = useState(20);

  const debouncedRecherche = useDebounce(recherche, 300);

  useEffect(() => {
    const nextStatut = STATUTS_FILTRES.some((s) => s.valeur === statutParam) ? statutParam : '';
    if (nextStatut !== filtreStatut) setFiltreStatut(nextStatut);
    if (periodeParam !== filtrePeriode) setFiltrePeriode(periodeParam);
  }, [statutParam, periodeParam]);

  // Reset pagination when filters change
  useEffect(() => { setNbAffiche(20); }, [filtreStatut, filtrePeriode, debouncedRecherche]);

  const { data: listData, isLoading: loading } = useQuery({
    queryKey: ['liste-missions', user?.id, etablissementId, filtreStatut, filtrePeriode, debouncedRecherche],
    queryFn: async () => {
      const debutMois = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
      const finMois = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1).toISOString();

      const etabId = etablissementId || user!.id;
      let query = supabase
        .from('missions')
        .select('id, intitule, description, service, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer, statut, est_urgente, niveau_urgence, soignant_assigne_id, cree_le')
        .eq('etablissement_id', etabId)
        .order('debut_le', { ascending: false });

      if (filtreStatut) query = query.eq('statut', filtreStatut as any);
      if (filtrePeriode === 'mois') query = query.gte('fin_le', debutMois).lt('fin_le', finMois);
      if (debouncedRecherche) query = query.ilike('intitule', `%${debouncedRecherche}%`);

      const [{ data }, { data: sgData }, { data: litigesData }] = await Promise.all([
        query,
        supabase.rpc('fn_mes_soignants_etablissement'),
        supabase.from('litiges').select('mission_id').eq('etablissement_id', etabId),
      ]);

      // Map soignant data by ID
      const sgMap: Record<string, any> = {};
      if (Array.isArray(sgData)) {
        for (const s of sgData) sgMap[s.id] = s;
      }

      const litigesMissionIds = new Set((litigesData || []).map((l: any) => l.mission_id));

      // Session F (F4) — candidatures en attente par mission OUVERTE.
      // Pas de count par mission dans le fetch missions : on agrège ici à la volée
      // (count + dernière candidature) à partir de la table `candidatures`, restreint
      // aux missions OUVERTE de la page courante (requête légère, pas de N+1).
      const missionsOuvertesIds = (data || [])
        .filter((m: any) => m.statut === 'OUVERTE')
        .map((m: any) => m.id);
      const candidaturesParMission: Record<string, { count: number; derniere: string | null }> = {};
      if (missionsOuvertesIds.length > 0) {
        const { data: candData } = await supabase
          .from('candidatures')
          .select('mission_id, cree_le')
          .in('mission_id', missionsOuvertesIds)
          .eq('statut', 'EN_ATTENTE');
        for (const c of candData || []) {
          const cur = candidaturesParMission[c.mission_id] || { count: 0, derniere: null };
          cur.count += 1;
          if (!cur.derniere || new Date(c.cree_le) > new Date(cur.derniere)) cur.derniere = c.cree_le;
          candidaturesParMission[c.mission_id] = cur;
        }
      }

      const missions = (data || []).map((m: any) => ({
        ...m,
        soignants: m.soignant_assigne_id ? sgMap[m.soignant_assigne_id] || null : null,
        has_litige: litigesMissionIds.has(m.id),
        nb_candidatures_attente: candidaturesParMission[m.id]?.count ?? 0,
        derniere_candidature_le: candidaturesParMission[m.id]?.derniere ?? null,
      }));

      // M2: Single count query with status grouping instead of 7 parallel queries
      const { data: allData } = await supabase.from('missions').select('statut', { count: 'exact' }).eq('etablissement_id', etabId);
      const c: Record<string, number> = { '': allData?.length ?? 0 };
      const statuts = ['OUVERTE', 'ASSIGNEE', 'EN_COURS', 'TERMINEE', 'EXPIREE', 'ANNULEE_PAR_ETABLISSEMENT', 'LITIGE'];
      for (const s of statuts) {
        c[s] = allData?.filter((m: any) => m.statut === s).length ?? 0;
      }

      return { missions, counts: c };
    },
    staleTime: 60_000,
    enabled: !!user,
  });

  const missions = useMemo(() => listData?.missions ?? [], [listData]);
  const counts = useMemo(() => listData?.counts ?? {}, [listData]);

  const appliquerFiltres = (statut: string, periode: string) => {
    const params = new URLSearchParams();
    if (statut) params.set('statut', statut);
    if (periode) params.set('periode', periode);
    setSearchParams(params, { replace: true });
  };

  // Group missions by serie
  const groupes = useMemo((): GroupeMission[] => {
    const seriesMap = new Map<string, any[]>();
    const singles: any[] = [];

    for (const m of missions) {
      const sid = extraireSerieId(m.description);
      if (sid) {
        if (!seriesMap.has(sid)) seriesMap.set(sid, []);
        seriesMap.get(sid)!.push(m);
      } else {
        singles.push(m);
      }
    }

    // Session F (F4) — « candidates-first » : les missions OUVERTE avec des
    // candidatures en attente remontent en tête. Tri stable (Array.prototype.sort
    // est stable depuis ES2019) : l'ordre relatif `debut_le DESC` est préservé
    // entre missions de même priorité.
    const aDesCandidatures = (m: any) => m.statut === 'OUVERTE' && (m.nb_candidatures_attente ?? 0) > 0;
    singles.sort((a, b) => Number(aDesCandidatures(b)) - Number(aDesCandidatures(a)));

    const result: GroupeMission[] = [];
    // Series first
    for (const [serieId, ms] of seriesMap) {
      result.push({ type: 'serie', serieId, missions: ms });
    }
    // Singles
    for (const m of singles) {
      result.push({ type: 'single', mission: m });
    }
    return result;
  }, [missions]);

  // handleAnnuler legacy supprimé : remplacé par ModaleAnnulationMissionEtab (Sprint 5.5 PR 3)
  // qui appelle fn_annuler_mission_etab avec décomposition L1243-8 / 1231-5.

  // M5: Atomic serie cancellation via RPC (séries OUVERTE uniquement — pas de conséquences)
  const handleAnnulerSerie = async (missionsSerieOuvertes: any[]) => {
    const ids = missionsSerieOuvertes.map((m: any) => m.id);
    const { data, error } = await supabase.rpc('fn_annuler_serie_etablissement' as any, { p_mission_ids: ids });
    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else {
      const reussies = (data as any)?.nb_annulees ?? ids.length;
      afficherNotification({ type: 'succes', message: `${reussies} mission(s) annulée(s).` });
      queryClient.invalidateQueries({ queryKey: ['liste-missions'] });
    }
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><SkeletonList count={4} /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-foreground">Mes missions</h1>
        <button onClick={() => navigate('/etablissement/missions/creer')} className="btn-primary text-sm hidden md:inline-flex">
          + Publier une mission
        </button>
      </div>

      {/* Filtres */}
      <div className="mb-4 overflow-x-auto">
        <div className="flex gap-2 pb-2">
          {STATUTS_FILTRES.map(s => (
            <button key={s.valeur} onClick={() => { setFiltreStatut(s.valeur); appliquerFiltres(s.valeur, filtrePeriode); }}
              className={`badge-base whitespace-nowrap transition-colors ${filtreStatut === s.valeur ? 'bg-primary text-primary-foreground font-semibold' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}>
              {s.label} ({counts[s.valeur] ?? 0})
            </button>
          ))}
        </div>
      </div>

      {/* Recherche */}
      <div className="relative mb-4">
        <Search aria-hidden="true" className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <input value={recherche} onChange={(e) => setRecherche(e.target.value)}
          aria-label="Rechercher une mission" placeholder="Rechercher par intitulé, profession, ville..." className="input-base pl-9 pr-9" />
        {recherche && (
          <button onClick={() => setRecherche('')} aria-label="Effacer la recherche" className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
            <X aria-hidden="true" className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Nombre de résultats */}
      <p className="text-sm text-muted-foreground mb-3">{missions.length} mission{missions.length !== 1 ? 's' : ''} trouvée{missions.length !== 1 ? 's' : ''}</p>

      {/* Liste */}
      {groupes.length > 0 ? (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {groupes.slice(0, nbAffiche).map((g, i) => {
              if (g.type === 'serie') {
                return (
                  <FadeInView key={g.serieId} delay={i * 100}>
                    <CarteSerie
                      missions={g.missions}
                      role="etablissement"
                      onAnnulerSerie={() => setModalAnnulerSerie(g.missions.filter((m: any) => m.statut === 'OUVERTE'))}
                    />
                  </FadeInView>
                );
              }
              return (
                <FadeInView key={g.mission.id} delay={i * 100}>
                  <CarteMission
                    mission={g.mission}
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
      ) : filtreStatut ? (
        <EmptyState
          icone={<Search />}
          mascotte="thinking"
          titre={
            filtreStatut === 'OUVERTE' ? 'Aucune mission ouverte' :
            filtreStatut === 'ASSIGNEE' ? 'Aucune mission assignée' :
            filtreStatut === 'EN_COURS' ? 'Aucune mission en cours' :
            filtreStatut === 'TERMINEE' ? 'Aucune mission terminée' :
            filtreStatut === 'EXPIREE' ? 'Aucune mission expirée' :
            filtreStatut === 'ANNULEE_PAR_ETABLISSEMENT' ? 'Aucune mission annulée' :
            filtreStatut === 'LITIGE' ? 'Aucun litige' :
            'Aucune mission trouvée'
          }
          description="Essayez un autre filtre ou publiez une nouvelle mission."
          cta={{ label: 'Voir toutes les missions', onClick: () => navigate('/etablissement/missions') }}
        />
      ) : (counts[''] ?? 0) > 0 ? (
        <EmptyState
          icone={<Search />}
          mascotte="thinking"
          titre="Aucune mission récente"
          description="Vos missions précédentes n'apparaissent pas dans ce filtre."
          cta={{ label: 'Publier une mission', onClick: () => navigate('/etablissement/missions/creer') }}
        />
      ) : (
        <EmptyState
          illustration={<IllustrationMegaphone />}
          titre="Publiez votre première mission"
          description="Trouvez un soignant qualifié en quelques heures."
          cta={{ label: 'Créer une mission →', onClick: () => navigate('/etablissement/missions/creer') }}
        />
      )}


      <ModalConfirmation ouvert={!!modalDupliquer} onFermer={() => setModalDupliquer(null)}
        onConfirmer={() => navigate(`/etablissement/missions/creer?dupliquer=${modalDupliquer.id}`)}
        titre="Dupliquer cette mission ?" message={`Une copie de « ${modalDupliquer?.intitule} » sera créée.`}
        labelConfirmer="Dupliquer" />

      {/* Sprint 5.5 PR 3 : modale annulation avec décomposition L1243-8 / 1231-5 */}
      {modalAnnuler && (
        <ModaleAnnulationMissionEtab
          ouvert={true}
          onFermer={() => setModalAnnuler(null)}
          onAnnulee={() => {
            setModalAnnuler(null);
            queryClient.invalidateQueries({ queryKey: ['liste-missions'] });
          }}
          mission={{
            id: modalAnnuler.id,
            intitule: modalAnnuler.intitule,
            statut: modalAnnuler.statut,
            debut_le: modalAnnuler.debut_le,
            fin_le: modalAnnuler.fin_le,
            duree_heures: modalAnnuler.duree_heures,
            taux_horaire_base: modalAnnuler.taux_horaire_base,
            total_brut: modalAnnuler.total_brut,
            type_contrat_applique: modalAnnuler.type_contrat_applique,
            type_contrat_recherche: modalAnnuler.type_contrat_recherche,
          }}
        />
      )}

      <ModalConfirmation ouvert={!!modalAnnulerSerie} onFermer={() => setModalAnnulerSerie(null)}
        onConfirmer={() => { if (modalAnnulerSerie) handleAnnulerSerie(modalAnnulerSerie); setModalAnnulerSerie(null); }}
        titre="Annuler toute la série ?" message={`${modalAnnulerSerie?.length || 0} mission(s) ouverte(s) seront annulées. Cette action est irréversible.`}
        labelConfirmer="Annuler la série" variante="danger" />
    </LayoutApp>
  );
}

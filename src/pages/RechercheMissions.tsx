import { preparerAlerteMissions } from '@/lib/alertes-recherche-missions';
import { useRole } from '@/hooks/useRole';
import { useExplorationMissions } from '@/hooks/useExplorationMissions';
import { useMemoireExploration, type HoraireExploration as Horaire, type VueExploration } from '@/hooks/useMemoireExploration';
import React, { useState, useEffect, useMemo, Suspense } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { toast } from 'sonner';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { SearchX, MapPin, List, Map as MapIcon, SlidersHorizontal, LayoutGrid, Sparkles, CalendarDays } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { CarteMissionSoignant } from '@/components/CarteMissionSoignant';
import { NoteNetEstime } from '@/components/NoteNetEstime';
import { usePullToRefresh } from '@/hooks/usePullToRefresh';
import { marquerExplorerVisite } from '@/hooks/useNouvellesMissionsExplorer';
import { QuizPreferencesSwipe, CLE_QUIZ_PREFS, type ReponsesQuiz } from '@/components/swipe/QuizPreferencesSwipe';
import { IndicateurPullToRefresh } from '@/components/IndicateurPullToRefresh';
import { BandeauDocumentsManquants } from '@/components/BandeauDocumentsManquants';
import { BandeauProfilIncomplet } from '@/components/BandeauProfilIncomplet';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { calculerDistanceKm } from '@/lib/geo';
import { PROFESSIONS, getLabelProfession, extraireContratPreference, missionCompatibleContrat, getTypesContratSoignant } from '@/lib/constantes';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import {
  DialogResponsive, DialogResponsiveContent, DialogResponsiveHeader,
  DialogResponsiveTitle, DialogResponsiveDescription, DialogResponsiveBody, DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { FiltresSauvegardes } from '@/components/FiltresSauvegardes';
import { VueSwipeMissions } from '@/components/swipe/VueSwipeMissions';
import { planningCorrespondAuFiltre } from '@/components/planning/planning-candidat';
import type { Json } from '@/integrations/supabase/types';
import { lazyRetry } from '@/lib/lazyRetry';

const CarteMissionsExploration = lazyRetry(() => import('@/components/CarteMissionsExploration'));

export default function RechercheMissions() {
  const { user } = useAuth();
  // Un changement de compte ne doit jamais conserver les filtres du précédent.
  return <RechercheMissionsCompte key={user?.id ?? 'anonyme'} />;
}

function RechercheMissionsCompte() {
  usePageTitle('Trouver une mission');
  const navigate = useNavigate();
  const { user } = useAuth();
  const { parcours, resolved: roleResolved } = useRole();
  const { etat, setEtat, modifier } = useMemoireExploration(user?.id);
  const { vue, profession, rayonKm, tauxMin, typeContrat, urgentesOnly, horaire, villeRecherche, nbAffiche } = etat;
  const setProfession = (v: React.SetStateAction<string>) => modifier('profession', v);
  const setRayonKm = (v: React.SetStateAction<number>) => modifier('rayonKm', v);
  const setTauxMin = (v: React.SetStateAction<number>) => modifier('tauxMin', v);
  const setTypeContrat = (v: React.SetStateAction<string>) => modifier('typeContrat', v);
  const setUrgentesOnly = (v: React.SetStateAction<boolean>) => modifier('urgentesOnly', v);
  const setHoraire = (v: React.SetStateAction<Horaire>) => modifier('horaire', v);
  const setVilleRecherche = (v: React.SetStateAction<string>) => modifier('villeRecherche', v);
  const setNbAffiche = (v: React.SetStateAction<number>) => modifier('nbAffiche', v);
  const basculerVue = (v: VueExploration) => {
    try { localStorage.setItem(`jolene_missions_view_pref:${user?.id}`, v); } catch { /* ignore */ }
    modifier('vue', v);
  };
  const [filtresOpen, setFiltresOpen] = useState(false);
  const debouncedVille = useDebounce(villeRecherche, 300);
  // Alerte 1-tap (Session E-5) : flux « créer une alerte » ouvert via ?alerte=1
  // (deep link depuis SwipeMissions) ou via le CTA de l'état vide.
  const [searchParams, setSearchParams] = useSearchParams();
  // Deep link depuis un établissement favori : n'afficher que ses missions
  // ouvertes. Le filtre reste dans l'URL afin que retour/partage conservent le
  // contexte de navigation.
  const etablissementId = searchParams.get('etablissement');
  const [alerteOpen, setAlerteOpen] = useState(false);
  const [alerteEnCours, setAlerteEnCours] = useState(false);
  const [filtresVersion, setFiltresVersion] = useState(0);
  const { soignant, missions, loading, actualisation, erreurChargement, rcpExpiree, rcpExpireLe, recharger } = useExplorationMissions({
    userId: user?.id, email: user?.email, parcours, roleResolved,
    enabled: vue !== 'swipe' || filtresOpen,
    preferencesInitialisees: etat.profilApplique,
    profession, tauxMin, urgentesOnly, etablissementId,
  });
  const { pullDistance, refreshing } = usePullToRefresh(recharger);

  useEffect(() => {
    if (!soignant || etat.profilApplique) return;
    setEtat((precedent) => ({
      ...precedent,
      rayonKm: precedent.rayonKm === 50 ? soignant.rayon_deplacement_km || 50 : precedent.rayonKm,
      tauxMin: precedent.tauxMin > 0 ? precedent.tauxMin : Number(soignant.taux_horaire_minimum) || 0,
      profilApplique: true,
    }));
  }, [soignant, etat.profilApplique, setEtat]);

  // 6c.4 : visiter Explorer remet à zéro le badge « X nouvelles missions »
  useEffect(() => { marquerExplorerVisite(); }, []);

  // 7d-4 : cold start — mini-quiz 5 questions au VRAI premier contact avec le
  // deck : jamais vu (localStorage) ET zéro swipe en base (une utilisatrice
  // expérimentée qui change d'appareil ne doit pas repasser par le quiz —
  // ses préférences sont déjà apprises).
  const [quizOpen, setQuizOpen] = useState(false);
  useEffect(() => {
    if (!roleResolved || parcours || localStorage.getItem(CLE_QUIZ_PREFS) || !user) return;
    // Comptes E2E : jamais de quiz (même pattern que le filtre missions test).
    if (user.email?.startsWith('playwright-')) return;
    let annule = false;
    supabase
      .from('swipes' as any)
      .select('id', { count: 'exact', head: true })
      .eq('soignant_id', user.id)
      .then(({ count }) => {
        if (!annule && (count ?? 0) === 0) setQuizOpen(true);
        else localStorage.setItem(CLE_QUIZ_PREFS, '1');
      });
    return () => { annule = true; };
  }, [user, parcours, roleResolved]);
  const appliquerQuiz = (r: ReponsesQuiz) => {
    setRayonKm(r.rayonKm);
    setTauxMin(r.tauxMin);
    // Une seule dimension d'horaire dans les filtres : le week-end ne prend le
    // filtre que si l'horaire jour/nuit est indifférent (le scoring, lui,
    // reçoit les deux dimensions).
    if (r.horaire !== 'TOUS') setHoraire(r.horaire);
    else if (r.rythme === 'WEEKEND') setHoraire('WEEKEND');
    if (r.dispoUrgence) setUrgentesOnly(false); // le pool notifie déjà — pas besoin de restreindre le deck
  };

  // Auto-apply filtres pré-stockés depuis PageRecherchesSauvegardees
  useEffect(() => {
    try {
      const raw = sessionStorage.getItem('jolene.filtres_a_appliquer');
      if (!raw) return;
      const parsed = JSON.parse(raw);
      sessionStorage.removeItem('jolene.filtres_a_appliquer');
      if (parsed?.audience !== 'SOIGNANT_RECHERCHE_MISSIONS') return;
      const f = parsed.filtres || {};
      setEtat((precedent) => ({
        ...precedent,
        profession: typeof f.profession === 'string' ? f.profession : precedent.profession,
        rayonKm: typeof f.rayonKm === 'number' ? f.rayonKm : precedent.rayonKm,
        tauxMin: typeof f.tauxMin === 'number' ? f.tauxMin : precedent.tauxMin,
        typeContrat: typeof f.typeContrat === 'string' ? f.typeContrat : precedent.typeContrat,
        urgentesOnly: typeof f.urgentesOnly === 'boolean' ? f.urgentesOnly : precedent.urgentesOnly,
        horaire: typeof f.horaire === 'string' ? f.horaire as Horaire : precedent.horaire,
        villeRecherche: typeof f.villeRecherche === 'string' ? f.villeRecherche : precedent.villeRecherche,
      }));
      if (parsed.nom_source) toast.success(`Filtres « ${parsed.nom_source} » appliqués`);
    } catch (_e) { /* ignore */ }
  }, [setEtat]);

  // ?alerte=1 → ouvre directement le flux « créer une alerte » (1 confirmation)
  useEffect(() => {
    if (searchParams.get('alerte') === '1') {
      setAlerteOpen(true);
      const next = new URLSearchParams(searchParams);
      next.delete('alerte');
      setSearchParams(next, { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Crée (ou réactive) un filtre sauvegardé « alerte » via le module existant
  // filtres_sauvegardes : tous les critères affichés. Seule une recherche
  // strictement identique peut être réactivée sans créer une nouvelle sauvegarde.
  const creerAlerteRapide = async () => {
    setAlerteEnCours(true);
    try {
      const prof = profession || soignant?.profession || '';
      const nomBase = prof ? `Alerte missions ${getLabelProfession(prof)}` : 'Alerte missions';

      const { data: existants, error: erreurListe } = await supabase.rpc('fn_lister_mes_filtres_sauvegardes', {
        p_audience: 'SOIGNANT_RECHERCHE_MISSIONS',
      });
      if (erreurListe || !Array.isArray(existants)) {
        toast.error("Impossible de vérifier vos alertes existantes. Réessayez.");
        return;
      }
      const { deja, nom: nomAlerte, filtres: criteresAlerte } = preparerAlerteMissions(
        { profession, rayonKm, tauxMin, typeContrat, urgentesOnly, horaire, villeRecherche },
        existants as any[], nomBase,
      );

      if (deja) {
        if (!deja.alerte_active) {
          const { data: upd, error: errUpd } = await supabase.rpc('fn_modifier_filtre_sauvegarde', {
            p_id: deja.id, p_alerte_active: true, p_frequence_alerte: 'IMMEDIATE',
          });
          if (errUpd || (upd as any)?.error) {
            toast.error((upd as any)?.error || "Impossible d'activer l'alerte");
            return;
          }
        }
        toast.success("Ton alerte est active : les nouvelles missions seront vérifiées toutes les heures.");
      } else {
        const { data, error } = await supabase.rpc('fn_creer_filtre_sauvegarde', {
          p_nom: nomAlerte,
          p_audience: 'SOIGNANT_RECHERCHE_MISSIONS',
          p_filtres: criteresAlerte as Json,
          p_alerte_active: true,
          p_frequence_alerte: 'IMMEDIATE',
        });
        if (error || (data as any)?.error) {
          toast.error((data as any)?.error || "Impossible de créer l'alerte");
          return;
        }
        toast.success("Alerte créée : les nouvelles missions seront vérifiées toutes les heures.");
      }
      setAlerteOpen(false);
      setFiltresVersion((v) => v + 1); // rafraîchit la liste « Mes recherches sauvegardées »
    } catch {
      toast.error("Impossible d’enregistrer l’alerte. Réessayez.");
    } finally {
      setAlerteEnCours(false);
    }
  };

  const filtered = useMemo(() => {
    const villeSearch = debouncedVille.trim().toLowerCase();

    return missions
      .map(m => ({
        ...m,
        distance_km: calculerDistanceKm(soignant?.adresse_lat ?? null, soignant?.adresse_lng ?? null, m.etablissements?.adresse_lat ?? null, m.etablissements?.adresse_lng ?? null),
      }))
      .filter(m => {
        if (villeSearch) {
          const ville = (m.etablissements?.adresse_ville || '').toLowerCase();
          const cp = (m.etablissements?.adresse_code_postal || '').toLowerCase();
          if (!ville.includes(villeSearch) && !cp.startsWith(villeSearch)) return false;
        }
        // Session E-5 : le rayon s'applique dès que la distance est calculable
        // (position du soignant + position de l'établissement connues). Avant,
        // le slider était inerte sans ville saisie — contrôle mort + libellé
        // « dans un rayon de X km » mensonger. Les missions sans coordonnées
        // restent affichées (distance inconnue ≠ hors rayon).
        if (m.distance_km !== null && m.distance_km > rayonKm) return false;
        // Contract type compatibility: use soignant's accepted types
        const mType = m.type_contrat_recherche || extraireContratPreference(m.description);
        const typesAcceptes = getTypesContratSoignant(soignant);
        if (!missionCompatibleContrat(mType, typesAcceptes)) return false;
        // La matrice a déjà validé la mission sur m.profession_requise côté DB.
        // Ne jamais la recalculer depuis soignant.profession : une IADE peut
        // candidater à une mission IDE, qui suit les règles IDE.
        // Additional UI filter
        if (typeContrat !== 'TOUS') {
          if (typeContrat === 'CDD' && mType === 'LIBERAL') return false;
          if (typeContrat === 'LIBERAL' && mType === 'SALARIE') return false;
        }
        if (!planningCorrespondAuFiltre(m, horaire)) return false;
        return true;
      })
      .sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999));
  }, [missions, soignant, rayonKm, typeContrat, horaire, debouncedVille]);

  // No blocking guard — render even without soignant profile

  const professionAlerteLabel = (profession || soignant?.profession)
    ? getLabelProfession(profession || soignant?.profession || '')
    : null;

  // Badge du bouton filtres : nombre de critères actifs (hors chips rapides,
  // qui portent leur propre état visuel au-dessus du deck).
  const nbFiltresActifs = [
    !!profession,
    !!villeRecherche.trim(),
    tauxMin > 0,
    typeContrat !== 'TOUS',
  ].filter(Boolean).length;

  return (
    <LayoutApp role="SOIGNANT" pleinEcran={vue === 'swipe'}>
      {vue !== 'swipe' && <IndicateurPullToRefresh distance={pullDistance} refreshing={refreshing} />}
      {!parcours && !loading && (!soignant || !soignant.profession) && <BandeauProfilIncomplet />}
      <div className={vue === 'swipe' ? 'flex flex-col flex-1 min-h-0 gap-2' : 'space-y-4'}>
        <div className="flex shrink-0 flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <h1 className="text-xl font-bold text-foreground">Explorer</h1>
          <div className="flex w-full items-center gap-1.5 sm:w-auto">
            {/* 6c.1 : UN SEUL switcher segmenté Swipe · Liste · Carte */}
            <div className="grid min-w-0 flex-1 grid-cols-3 rounded-2xl border border-jolene-rose-200 bg-jolene-cloud p-1 sm:inline-flex sm:flex-none" role="tablist" aria-label="Vue Swipe, Liste ou Carte">
              {([
                { v: 'swipe' as const, label: 'Swipe', icone: <Sparkles className="h-3.5 w-3.5" aria-hidden="true" /> },
                { v: 'liste' as const, label: 'Liste', icone: <LayoutGrid className="h-3.5 w-3.5" aria-hidden="true" /> },
                { v: 'carte' as const, label: 'Carte', icone: <MapIcon className="h-3.5 w-3.5" aria-hidden="true" /> },
              ]).map(({ v, label, icone }) => (
                <button
                  key={v}
                  type="button"
                  role="tab"
                  aria-selected={vue === v}
                  className={`inline-flex min-w-0 items-center justify-center gap-1 rounded-xl px-2 py-1.5 text-xs font-semibold transition-snap sm:px-2.5 ${vue === v ? 'bg-gradient-hero text-white shadow-md' : 'text-jolene-bubblegum hover:text-jolene-rose-700'}`}
                  onClick={() => basculerVue(v)}
                >
                  {icone}
                  {label}
                </button>
              ))}
            </div>
            {/* Lot 17 (F5) : calendrier de disponibilités — matching inversé */}
            <button
              type="button"
              onClick={() => navigate('/soignant/disponibilites')}
              aria-label="Mes disponibilités"
              className="h-10 w-10 shrink-0 flex items-center justify-center rounded-xl border border-jolene-rose-200 bg-card text-jolene-bubblegum hover:text-jolene-rose-700 hover:border-jolene-rose-300 transition-colors active:scale-95"
            >
              <CalendarDays className="h-4 w-4" aria-hidden="true" />
            </button>
            {/* Filtres = bottom sheet, badge du nombre de filtres actifs */}
            <button
              type="button"
              onClick={() => setFiltresOpen(true)}
              aria-label={`Filtres${nbFiltresActifs > 0 ? ` (${nbFiltresActifs} actif${nbFiltresActifs > 1 ? 's' : ''})` : ''}`}
              className="relative h-10 w-10 shrink-0 flex items-center justify-center rounded-xl border border-jolene-rose-200 bg-card text-jolene-bubblegum hover:text-jolene-rose-700 hover:border-jolene-rose-300 transition-colors active:scale-95"
            >
              <SlidersHorizontal className="h-4 w-4" aria-hidden="true" />
              {nbFiltresActifs > 0 && (
                <span className="absolute -top-1 -right-1 h-4 min-w-[16px] px-0.5 flex items-center justify-center rounded-full bg-primary text-primary-foreground text-[10px] font-bold" aria-hidden="true">
                  {nbFiltresActifs}
                </span>
              )}
            </button>
          </div>
        </div>

        {/* Chips rapides 1-tap — au-dessus du deck COMME de la liste (6c.1) */}
        <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1 shrink-0">
          {[
            { actif: urgentesOnly, label: '🔥 Urgentes', toggle: () => setUrgentesOnly(v => !v) },
            { actif: horaire === 'WEEKEND', label: '📅 Week-end', toggle: () => setHoraire(h => h === 'WEEKEND' ? 'TOUS' : 'WEEKEND') },
            { actif: horaire === 'NUIT', label: '🌙 Nuit', toggle: () => setHoraire(h => h === 'NUIT' ? 'TOUS' : 'NUIT') },
            { actif: horaire === 'JOUR', label: '☀️ Jour', toggle: () => setHoraire(h => h === 'JOUR' ? 'TOUS' : 'JOUR') },
          ].map((chip) => (
            <button
              key={chip.label}
              type="button"
              onClick={chip.toggle}
              aria-pressed={chip.actif}
              className={`shrink-0 inline-flex items-center rounded-full px-3 min-h-[44px] md:min-h-0 md:py-1.5 text-[11px] min-[390px]:text-xs font-semibold transition-snap border ${
                chip.actif
                  ? 'bg-gradient-hero text-white border-transparent shadow-md'
                  : 'bg-card text-jolene-bubblegum border-jolene-rose-200 hover:border-jolene-rose-300'
              }`}
            >
              {chip.label}
            </button>
          ))}
        </div>

        {/* La bannière documents ne s'affiche pas au-dessus du swipe (la carte doit
            vendre, sans bannière) — uniquement en vue Liste. Le rappel « documents »
            est porté par le parcours d'activation sur l'Accueil. */}
        {!parcours && vue === 'liste' && (
          <BandeauDocumentsManquants tousDocumentsValides={!!soignant?.tous_documents_valides} rcpExpiree={rcpExpiree} rcpExpireLe={rcpExpireLe} />
        )}

        {/* Session G1 : vue Swipe consolidée dans la page canonique.
            En mode swipe : conteneur plein écran (flex-1) → carte + barre
            d'action tiennent dans le viewport, sans scroll. */}
        {vue === 'swipe' ? (
          <div className="flex-1 min-h-0 flex flex-col">
            <VueSwipeMissions
              onBasculerListe={() => basculerVue('liste')}
              onCreerAlerte={() => setAlerteOpen(true)}
              onElargirRayon={() => { setRayonKm((r) => Math.min(100, r + 20)); basculerVue('liste'); }}
              filtreDeck={{
                urgentesOnly,
                horaire,
                profession,
                ville: debouncedVille,
                rayonKm,
                tauxMin,
                typeContrat,
              }}
            />
          </div>
        ) : (
        <>
        {/* Active filter chips — visible even when filters are collapsed on mobile */}
        {(villeRecherche || tauxMin > 0 || profession || typeContrat !== 'TOUS') && (
          <div className="flex flex-wrap gap-1.5 md:hidden">
            <BadgeY2K variant="info" size="sm">{filtered.length} résultat{filtered.length > 1 ? 's' : ''}</BadgeY2K>
            {villeRecherche && <BadgeY2K variant="info" size="sm">📍 {villeRecherche}</BadgeY2K>}
            {tauxMin > 0 && <BadgeY2K variant="info" size="sm">≥ {tauxMin} €/h</BadgeY2K>}
            {urgentesOnly && <BadgeY2K variant="info" size="sm">🔥 Urgentes</BadgeY2K>}
            {horaire !== 'TOUS' && <BadgeY2K variant="info" size="sm">{horaire === 'NUIT' ? '🌙 Nuit' : horaire === 'WEEKEND' ? '📅 Weekend' : '☀️ Jour'}</BadgeY2K>}
            {typeContrat !== 'TOUS' && <BadgeY2K variant="info" size="sm">{typeContrat}</BadgeY2K>}
          </div>
        )}

        {erreurChargement && (
          <div role="alert" className="card-base space-y-3">
            <p>{missions.length > 0
              ? 'Les missions n’ont pas pu être actualisées. Les derniers résultats restent affichés. Réessayez pour vérifier leur disponibilité.'
              : 'Les missions n’ont pas pu être chargées. Vérifiez votre connexion et réessayez.'}</p>
            <button className="btn-primary" disabled={actualisation} onClick={() => { void recharger(); }}>Réessayer</button>
          </div>
        )}
        {actualisation && <p role="status" className="text-sm text-muted-foreground">Actualisation des missions…</p>}
        {vue !== 'carte' ? (
          erreurChargement && missions.length === 0 ? null : loading ? <ChargementPage /> : filtered.length > 0 ? (
              <>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {filtered.slice(0, nbAffiche).map(m => (
                    <CarteMissionSoignant
                      key={m.id}
                      mission={m}
                      soignant={soignant}
                      onClick={() => navigate(`/soignant/missions/${m.id}`)}
                    />
                  ))}
                </div>
                {nbAffiche < filtered.length && (
                  <div className="flex justify-center mt-6">
                    <button onClick={() => setNbAffiche(n => n + 20)} className="btn-secondary text-sm px-6">
                      Voir plus ({filtered.length - nbAffiche} restante{filtered.length - nbAffiche > 1 ? 's' : ''})
                    </button>
                  </div>
                )}
                <NoteNetEstime className="mt-4" />
              </>
            ) : (
              <EmptyState
                icone={<SearchX />}
                mascotte="thinking"
                titre="Aucune mission trouvée"
                description="Crée une alerte : tu recevras un email dès qu'une nouvelle mission correspondant à tes critères est publiée."
                cta={{
                  label: '🔔 Me prévenir des prochaines missions',
                  onClick: () => setAlerteOpen(true),
                }}
                ctaSecondaire={
                  /* Cause la plus probable d'un résultat vide : un filtre rapide
                     actif (urgentes/weekend/nuit). On propose d'abord de les
                     effacer, sinon d'élargir le rayon. */
                  (urgentesOnly || horaire !== 'TOUS')
                    ? {
                        label: 'Effacer les filtres rapides',
                        onClick: () => { setUrgentesOnly(false); setHoraire('TOUS'); },
                      }
                    : rayonKm < 100
                    ? {
                        label: 'Élargir le rayon (+20 km)',
                        onClick: () => setRayonKm((r) => Math.min(100, r + 20)),
                      }
                    : undefined
                }
              />
            )
        ) : (
          <>
            <Suspense fallback={<ChargementPage />}>
              <CarteMissionsExploration missions={filtered} soignant={soignant} />
            </Suspense>
            {filtered.length === 0 && !loading && !erreurChargement && (
              <p className="text-sm text-muted-foreground text-center mt-3">Aucune mission à afficher sur la carte.</p>
            )}
          </>
        )}
        </>
        )}
      </div>

      {/* 7d-4 — mini-quiz cold start (première visite d'Explorer uniquement) */}
      <QuizPreferencesSwipe open={quizOpen} onOpenChange={setQuizOpen} onAppliquer={appliquerQuiz} />

      {/* 6c.1 — Filtres en bottom sheet (mobile) / modale centrée (desktop).
          Le formulaire pleine page a disparu ; les filtres sont LIVE (pas de
          bouton Appliquer) : fermer la sheet = voir les résultats. */}
      <DialogResponsive open={filtresOpen} onOpenChange={setFiltresOpen}>
        <DialogResponsiveContent maxWidth="lg">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Filtres</DialogResponsiveTitle>
            <DialogResponsiveDescription>
              {filtered.length} mission{filtered.length > 1 ? 's' : ''} avec les critères actuels
            </DialogResponsiveDescription>
          </DialogResponsiveHeader>
          <DialogResponsiveBody>
            <div className="space-y-4">
            {/* Mes recherches sauvegardées (J2.3.C) — key : remount après création
                d'une alerte 1-tap pour rafraîchir la liste */}
            <FiltresSauvegardes
              key={filtresVersion}
              audience="SOIGNANT_RECHERCHE_MISSIONS"
              filtresCourants={{
                profession,
                rayonKm,
                tauxMin,
                typeContrat,
                urgentesOnly,
                horaire,
                villeRecherche,
              }}
              onCharger={(f) => {
                const obj = f as Record<string, any>;
                if (typeof obj.profession === 'string') setProfession(obj.profession);
                if (typeof obj.rayonKm === 'number') setRayonKm(obj.rayonKm);
                if (typeof obj.tauxMin === 'number') setTauxMin(obj.tauxMin);
                if (typeof obj.typeContrat === 'string') setTypeContrat(obj.typeContrat);
                if (typeof obj.urgentesOnly === 'boolean') setUrgentesOnly(obj.urgentesOnly);
                if (typeof obj.horaire === 'string') setHoraire(obj.horaire as Horaire);
                if (typeof obj.villeRecherche === 'string') setVilleRecherche(obj.villeRecherche);
              }}
            />


          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {/* Ville / Code postal */}
            <div className="space-y-1.5">
              <Label htmlFor="recherche-ville" className="text-xs font-medium text-muted-foreground">📍 Ville ou code postal</Label>
              <Input
                id="recherche-ville"
                value={villeRecherche}
                onChange={(e) => setVilleRecherche(e.target.value)}
                placeholder="Ex : Paris, 75001..."
              />
              <p className="text-[10px] text-muted-foreground">Laisse vide pour utiliser ta position</p>
            </div>
            {/* Profession */}
            <div className="space-y-1.5">
              <Label className="text-xs font-medium text-muted-foreground">Profession</Label>
              <Select value={profession} onValueChange={setProfession}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {PROFESSIONS.map(p => (
                    <SelectItem key={p.valeur} value={p.valeur}>{p.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Rayon */}
            <div className="space-y-1.5">
              <Label className="text-xs font-medium text-muted-foreground">Rayon : {rayonKm} km</Label>
              <Slider
                value={[rayonKm]}
                onValueChange={([v]) => setRayonKm(v)}
                min={5}
                max={100}
                step={5}
                className="mt-2"
              />
            </div>

            {/* Taux horaire min */}
            <div className="space-y-1.5">
              <Label htmlFor="recherche-taux-min" className="text-xs font-medium text-muted-foreground">Taux horaire minimum (€/h)</Label>
              <Input
                id="recherche-taux-min"
                type="number"
                min={0}
                step={1}
                value={tauxMin || ''}
                onChange={(e) => setTauxMin(Number(e.target.value) || 0)}
                placeholder="Ex : 25"
              />
            </div>

            {/* Type de contrat */}
            <div className="space-y-1.5">
              <Label className="text-xs font-medium text-muted-foreground">Type de contrat</Label>
              <Select value={typeContrat} onValueChange={setTypeContrat}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="TOUS">Tous</SelectItem>
                  <SelectItem value="CDD">CDD</SelectItem>
                  <SelectItem value="LIBERAL">Libéral</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Horaires */}
            <div className="space-y-1.5">
              <Label className="text-xs font-medium text-muted-foreground">Horaires</Label>
              <Select value={horaire} onValueChange={(v) => setHoraire(v as Horaire)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="TOUS">Tous</SelectItem>
                  <SelectItem value="JOUR">Jour</SelectItem>
                  <SelectItem value="NUIT">Nuit</SelectItem>
                  <SelectItem value="WEEKEND">Week-end</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Urgentes uniquement */}
            <div className="flex items-center gap-3 pt-5">
              <Switch checked={urgentesOnly} onCheckedChange={setUrgentesOnly} id="urgentes" />
              <Label htmlFor="urgentes" className="text-sm cursor-pointer">Urgentes uniquement</Label>
            </div>
          </div>

          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <BadgeY2K variant="info">{filtered.length} mission{filtered.length > 1 ? 's' : ''}</BadgeY2K>
              {/* Le rayon n'est annoncé que s'il est réellement appliqué (position connue) */}
              {soignant?.adresse_lat != null && soignant?.adresse_lng != null && (
                <span>dans un rayon de {rayonKm} km</span>
              )}
            </div>
            <BoutonY2K
              variant="ghost"
              size="sm"
              className="text-xs text-muted-foreground"
              onClick={() => {
                // Valeur vide = profession du profil avec hiérarchie de
                // compétences (IADE/IBODE voient notamment les missions IDE).
                setProfession('');
                setRayonKm(soignant?.rayon_deplacement_km || 50);
                setTauxMin(0);
                setTypeContrat('TOUS');
                setUrgentesOnly(false);
                setHoraire('TOUS');
                setVilleRecherche('');
              }}
            >
              Réinitialiser
            </BoutonY2K>
          </div>
        
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K className="w-full" onClick={() => setFiltresOpen(false)}>
              Voir {filtered.length} mission{filtered.length > 1 ? 's' : ''}
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>

      {/* Confirmation 1-tap : création d'alerte missions (Session E-5) */}
      <Dialog open={alerteOpen} onOpenChange={(o) => { if (!alerteEnCours) setAlerteOpen(o); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>🔔 Créer une alerte missions</DialogTitle>
            <DialogDescription>
              {professionAlerteLabel ? (
                <>
                  Les nouvelles missions sont vérifiées toutes les heures. Tu recevras un email si une mission{' '}
                  <strong>{professionAlerteLabel}</strong> correspondant à tes critères
                  (rayon {rayonKm} km) est publiée.
                </>
              ) : (
                <>
                  Les nouvelles missions sont vérifiées toutes les heures. Tu recevras un email si une mission correspondant à tes
                  critères (rayon {rayonKm} km) est publiée.
                </>
              )}{' '}
              Tu pourras modifier ou désactiver cette alerte à tout moment depuis
              « Mes recherches sauvegardées ».
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <BoutonY2K variant="secondary" onClick={() => setAlerteOpen(false)} disabled={alerteEnCours}>
              Annuler
            </BoutonY2K>
            <BoutonY2K onClick={creerAlerteRapide} loading={alerteEnCours} disabled={alerteEnCours}>
              Activer l'alerte
            </BoutonY2K>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </LayoutApp>
  );
}

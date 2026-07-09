import React, { useState, useEffect, useMemo, useRef } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { logger } from '@/lib/logger';
import { handleErrorSilent } from '@/lib/handleError';
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
import { enrichirEtablissements } from '@/lib/etablissements';
import { calculerDistanceKm } from '@/lib/geo';
import { PROFESSIONS, getLabelProfession, extraireContratPreference, missionCompatibleContrat, getTypesContratSoignant, peutExercerLiberal } from '@/lib/constantes';
import { getMissionsCompatiblesFilter } from '@/lib/profession-hierarchy';
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
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { FiltresSauvegardes } from '@/components/FiltresSauvegardes';
import { VueSwipeMissions } from '@/components/swipe/VueSwipeMissions';
import type { Json } from '@/integrations/supabase/types';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

// Fix default marker icon for Leaflet + bundlers
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
});

interface SoignantData {
  profession: string;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number;
  tous_documents_valides: boolean;
  type_contrat: string | null;
  types_contrat_acceptes: string | null;
}

type Horaire = 'TOUS' | 'JOUR' | 'NUIT' | 'WEEKEND';

function isNuit(debut: string): boolean {
  const h = new Date(debut).getHours();
  return h >= 20 || h < 7;
}

function isWeekend(debut: string): boolean {
  const day = new Date(debut).getDay();
  return day === 0 || day === 6;
}

const VIEW_PREF_KEY = 'jolene_missions_view_pref'; // 'swipe' | 'liste'

export default function RechercheMissions() {
  usePageTitle('Trouver une mission');
  const navigate = useNavigate();
  const { user } = useAuth();
  // 6c.1 : UN SEUL switcher segmenté Swipe · Liste · Carte (les deux anciens
  // toggles — Swipe/Liste en haut + Liste/Carte flottant — coexistaient et se
  // contredisaient). Explorer = deck de swipe DIRECT par défaut ; la préférence
  // de vue est mémorisée par utilisateur.
  const [vue, setVue] = useState<'swipe' | 'liste' | 'carte'>(() => {
    try {
      // Deep-link ?vue=swipe (ex. nudge streak du dashboard) prioritaire sur la préférence.
      const urlVue = new URLSearchParams(window.location.search).get('vue');
      if (urlVue === 'swipe' || urlVue === 'liste' || urlVue === 'carte') return urlVue;
      const stored = localStorage.getItem(VIEW_PREF_KEY);
      if (stored === 'swipe' || stored === 'liste' || stored === 'carte') return stored;
      return 'swipe';
    } catch { return 'swipe'; }
  });
  const basculerVue = (v: 'swipe' | 'liste' | 'carte') => {
    try { localStorage.setItem(VIEW_PREF_KEY, v); } catch { /* ignore */ }
    setVue(v);
    if (v === 'carte') initMap('carte');
  };
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  // Pull-to-refresh (Lot 6b.3) : tirer en haut de page relance le fetch.
  const [refreshTick, setRefreshTick] = useState(0);
  const { pullDistance, refreshing } = usePullToRefresh(async () => {
    setRefreshTick(t => t + 1);
    await new Promise(r => setTimeout(r, 700));
  });
  const [nbAffiche, setNbAffiche] = useState(20);
  const [rcpExpiree, setRcpExpiree] = useState(false);
  const [rcpExpireLe, setRcpExpireLe] = useState<string | null>(null);
  // Filtres
  const [profession, setProfession] = useState<string>('');
  const [rayonKm, setRayonKm] = useState(50);
  const [tauxMin, setTauxMin] = useState(0);
  const [typeContrat, setTypeContrat] = useState<string>('TOUS');
  const [urgentesOnly, setUrgentesOnly] = useState(false);
  const [horaire, setHoraire] = useState<Horaire>('TOUS');
  // 6c.1 : les filtres vivent dans une bottom sheet (le formulaire pleine page
  // a disparu), ouverte par une icône avec badge du nombre de filtres actifs.
  const [filtresOpen, setFiltresOpen] = useState(false);
  const [villeRecherche, setVilleRecherche] = useState('');
  const debouncedVille = useDebounce(villeRecherche, 300);
  // Alerte 1-tap (Session E-5) : flux « créer une alerte » ouvert via ?alerte=1
  // (deep link depuis SwipeMissions) ou via le CTA de l'état vide.
  const [searchParams, setSearchParams] = useSearchParams();
  const [alerteOpen, setAlerteOpen] = useState(false);
  const [alerteEnCours, setAlerteEnCours] = useState(false);
  const [filtresVersion, setFiltresVersion] = useState(0);
  // Map
  const mapRef = useRef<HTMLDivElement>(null);
  const leafletMap = useRef<L.Map | null>(null);
  const markersLayer = useRef<L.LayerGroup | null>(null);

  // 6c.4 : visiter Explorer remet à zéro le badge « X nouvelles missions »
  useEffect(() => { marquerExplorerVisite(); }, []);

  // 7d-4 : cold start — mini-quiz 5 questions au VRAI premier contact avec le
  // deck : jamais vu (localStorage) ET zéro swipe en base (une utilisatrice
  // expérimentée qui change d'appareil ne doit pas repasser par le quiz —
  // ses préférences sont déjà apprises).
  const [quizOpen, setQuizOpen] = useState(false);
  useEffect(() => {
    if (localStorage.getItem(CLE_QUIZ_PREFS) || !user) return;
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
  }, [user]);
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
      if (typeof f.profession === 'string') setProfession(f.profession);
      if (typeof f.rayonKm === 'number') setRayonKm(f.rayonKm);
      if (typeof f.tauxMin === 'number') setTauxMin(f.tauxMin);
      if (typeof f.typeContrat === 'string') setTypeContrat(f.typeContrat);
      if (typeof f.urgentesOnly === 'boolean') setUrgentesOnly(f.urgentesOnly);
      if (typeof f.horaire === 'string') setHoraire(f.horaire as Horaire);
      if (typeof f.villeRecherche === 'string') setVilleRecherche(f.villeRecherche);
      if (parsed.nom_source) toast.success(`Filtres « ${parsed.nom_source} » appliqués`);
    } catch (_e) { /* ignore */ }
  }, []);

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
  // filtres_sauvegardes : profession du soignant + rayon actuel, alerte email
  // IMMEDIATE. Idempotent : si une alerte du même nom existe déjà, on la
  // réactive au lieu de créer un doublon.
  const creerAlerteRapide = async () => {
    setAlerteEnCours(true);
    try {
      const prof = profession || soignant?.profession || '';
      const nomAlerte = prof ? `Alerte missions ${getLabelProfession(prof)}` : 'Alerte missions';

      const { data: existants } = await supabase.rpc('fn_lister_mes_filtres_sauvegardes', {
        p_audience: 'SOIGNANT_RECHERCHE_MISSIONS',
      });
      const deja = (((existants as any) || []) as Array<{ id: string; nom: string; alerte_active: boolean }>)
        .find((f) => f?.nom === nomAlerte);

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
        toast.success("Ton alerte est active : tu recevras un email dès qu'une nouvelle mission correspond.");
      } else {
        const { data, error } = await supabase.rpc('fn_creer_filtre_sauvegarde', {
          p_nom: nomAlerte,
          p_audience: 'SOIGNANT_RECHERCHE_MISSIONS',
          p_filtres: { profession: prof, rayonKm } as Json,
          p_alerte_active: true,
          p_frequence_alerte: 'IMMEDIATE',
        });
        if (error || (data as any)?.error) {
          toast.error((data as any)?.error || "Impossible de créer l'alerte");
          return;
        }
        toast.success("Alerte créée : tu recevras un email dès qu'une nouvelle mission correspond.");
      }
      setAlerteOpen(false);
      setFiltresVersion((v) => v + 1); // rafraîchit la liste « Mes recherches sauvegardées »
    } finally {
      setAlerteEnCours(false);
    }
  };

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides, type_contrat, types_contrat_acceptes, type_exercice, taux_horaire_minimum')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => {
        if (data) {
          const s = data as any;
          setSoignant(s);
          setProfession(s.profession);
          setRayonKm(s.rayon_deplacement_km || 50);
          // Plancher tarif horaire = préférence de profil persistante. On l'applique
          // par défaut, sans écraser un filtre déjà appliqué (filtre sauvegardé).
          if (s.taux_horaire_minimum != null) {
            setTauxMin((cur) => (cur > 0 ? cur : Number(s.taux_horaire_minimum)));
          }
        }
      }).then(undefined, (err) => handleErrorSilent(err, 'RechercheMissions.soignant'));

    // RCP check only for LIBERAL/MIXTE
    supabase.from('soignants').select('type_exercice').eq('id', user.id).maybeSingle()
      .then(({ data: sg }) => {
        const isLiberalOrMixte = sg?.type_exercice === 'LIBERAL' || sg?.type_exercice === 'MIXTE';
        if (!isLiberalOrMixte) { setRcpExpiree(false); return; }
        supabase.from('documents_soignants')
          .select('statut_verification, valide_jusqua')
          .eq('soignant_id', user.id)
          .eq('type_document', 'RCP_ASSURANCE')
          .order('televerse_le', { ascending: false })
          .limit(1)
          .then(({ data }) => {
            if (!data || data.length === 0) {
              setRcpExpiree(true);
            } else {
              const doc = data[0];
              const expire = doc.valide_jusqua ? new Date(doc.valide_jusqua) < new Date() : false;
              const invalide = doc.statut_verification === 'REJETE' || doc.statut_verification === 'EXPIRE' || expire;
              setRcpExpiree(invalide);
              // Alerte préventive J-30 : RCP encore valide mais expirant sous 30 jours
              if (!invalide && doc.valide_jusqua) {
                const joursRestants = (new Date(doc.valide_jusqua).getTime() - Date.now()) / 86400000;
                setRcpExpireLe(joursRestants <= 30 ? doc.valide_jusqua : null);
              }
            }
          });
      });
  }, [user]);

  useEffect(() => {
    if (!user) return;
    setLoading(true);
    const fetchMissions = async () => {
      let query = supabase.from('missions').select(`
        id, intitule, description, service, profession_requise,
        specialite_medicale_requise, accepte_non_specialises,
        debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
        total_brut, net_a_payer, est_urgente, niveau_urgence, statut,
        soignant_assigne_id, cree_le, etablissement_id, type_contrat_recherche, boostee_le, mode_remuneration, retrocession_pct
      `)
        .eq('statut', 'OUVERTE')
        .gte('debut_le', new Date().toISOString())
        .order('boostee_le', { ascending: false, nullsFirst: false })
        .order('est_urgente', { ascending: false })
        .order('debut_le', { ascending: true })
        .limit(500);

      const professionFiltre = profession || soignant?.profession;
      if (professionFiltre) {
        // Si l'utilisateur n'a pas explicitement choisi une profession dans le
        // filtre (utilise sa propre profession), on élargit la recherche aux
        // missions hiérarchiquement compatibles (IBODE/IADE peuvent voir les
        // missions IDE ; IDE voit les missions IBODE/IADE si accepte_non_spec).
        const orFiltre = !profession ? getMissionsCompatiblesFilter(professionFiltre) : null;
        if (orFiltre) {
          query = query.or(orFiltre);
        } else {
          query = query.eq('profession_requise', professionFiltre as any);
        }
      }

      if (tauxMin > 0) query = query.gte('taux_horaire_base', tauxMin);
      if (urgentesOnly) query = query.eq('est_urgente', true);

      const { data, error } = await query;
      if (error) {
        logger.warn('[RechercheMissions] Erreur requête missions:', error.message);
        toast.error('Impossible de charger les missions. Vérifie ta connexion.');
      }
      const enriched = data ? await enrichirEtablissements(data as any) : [];
      setMissions(enriched);
      setLoading(false);
    };
    fetchMissions();
  }, [user, soignant, profession, tauxMin, urgentesOnly, refreshTick]);

  const filtered = useMemo(() => {
    const typesContrat = soignant ? getTypesContratSoignant(soignant) : ['CDD', 'VACATION', 'LIBERAL', 'SALARIE'];
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
        // PR 2 Sprint 1 — matrice prof × type_etab : si la mission est LIBERAL
        // et que la combinaison est incompatible, on retire la mission du
        // listing (pas affichée au soignant). Défense en profondeur côté
        // backend via trigger dec_valider_compatibilite_mission_liberal.
        if (mType === 'LIBERAL' && soignant?.profession && m.etablissements?.type) {
          if (!peutExercerLiberal(soignant.profession, m.etablissements.type)) return false;
        }
        // Additional UI filter
        if (typeContrat !== 'TOUS') {
          if (typeContrat === 'CDD' && mType === 'LIBERAL') return false;
          if (typeContrat === 'LIBERAL' && mType === 'SALARIE') return false;
        }
        if (horaire === 'NUIT' && !isNuit(m.debut_le)) return false;
        if (horaire === 'JOUR' && isNuit(m.debut_le)) return false;
        if (horaire === 'WEEKEND' && !isWeekend(m.debut_le)) return false;
        return true;
      })
      .sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999));
  }, [missions, soignant, rayonKm, typeContrat, horaire, debouncedVille]);

  // Initialize / update map
  const initMap = (tab: string) => {
    if (tab !== 'carte') return;
    setTimeout(() => {
      if (!mapRef.current) return;

      const center: [number, number] = soignant?.adresse_lat && soignant?.adresse_lng
        ? [soignant.adresse_lat, soignant.adresse_lng]
        : [48.8566, 2.3522]; // Paris default

      if (!leafletMap.current) {
        leafletMap.current = L.map(mapRef.current).setView(center, 11);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
          maxZoom: 18,
        }).addTo(leafletMap.current);
        markersLayer.current = L.layerGroup().addTo(leafletMap.current);

        // Soignant position marker
        if (soignant?.adresse_lat && soignant?.adresse_lng) {
          const homeIcon = L.divIcon({
            html: '<div style="background:hsl(187,75%,40%);width:14px;height:14px;border-radius:50%;border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3);"></div>',
            iconSize: [14, 14],
            className: '',
          });
          L.marker([soignant.adresse_lat, soignant.adresse_lng], { icon: homeIcon })
            .addTo(leafletMap.current)
            .bindPopup('<strong>Ta position</strong>');
        }
      } else {
        leafletMap.current.invalidateSize();
      }

      // Update markers
      if (markersLayer.current) {
        markersLayer.current.clearLayers();
        filtered.forEach(m => {
          const lat = m.etablissements?.adresse_lat;
          const lng = m.etablissements?.adresse_lng;
          if (!lat || !lng) return;

          const marker = L.marker([lat, lng]).addTo(markersLayer.current!);
          const popup = `
            <div style="min-width:200px;font-family:Inter,sans-serif;">
              <p style="font-weight:600;font-size:13px;margin:0 0 4px;">${m.intitule}</p>
              <p style="font-size:11px;color:#666;margin:0 0 2px;">🏥 ${m.etablissements?.nom ?? '—'}</p>
              <p style="font-size:11px;color:#666;margin:0 0 2px;">📅 ${format(new Date(m.debut_le), "d MMM · HH'h'mm", { locale: fr })}</p>
              <p style="font-size:13px;font-weight:700;color:#E04590;margin:4px 0;">💰 ${(m.taux_horaire_base ?? 0).toFixed(2)} €/h</p>
              <a href="/soignant/missions/${m.id}" style="display:inline-block;margin-top:6px;padding:4px 12px;background:#E04590;color:white;border-radius:6px;text-decoration:none;font-size:11px;font-weight:600;">Voir la mission</a>
            </div>
          `;
          marker.bindPopup(popup);
        });
      }
    }, 100);
  };

  // Vue carte : resynchronise les marqueurs quand les résultats filtrés changent
  // (avant, seule la bascule vers la carte redessinait les marqueurs).
  useEffect(() => {
    if (vue === 'carte') initMap('carte');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vue, filtered]);

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
      {(!soignant || !soignant.profession) && <BandeauProfilIncomplet />}
      <div className={vue === 'swipe' ? 'flex flex-col flex-1 min-h-0 gap-2' : 'space-y-4'}>
        <div className="flex items-center justify-between gap-2 shrink-0">
          <h1 className="text-xl font-bold text-foreground">Explorer</h1>
          <div className="flex items-center gap-1.5">
            {/* 6c.1 : UN SEUL switcher segmenté Swipe · Liste · Carte */}
            <div className="inline-flex rounded-2xl bg-jolene-cloud border border-jolene-rose-200 p-1" role="tablist" aria-label="Vue Swipe, Liste ou Carte">
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
                  className={`inline-flex items-center gap-1 rounded-xl px-2.5 py-1.5 text-xs font-semibold transition-snap ${vue === v ? 'bg-gradient-hero text-white shadow-md' : 'text-jolene-bubblegum hover:text-jolene-rose-700'}`}
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
        <div className="flex gap-2 overflow-x-auto pb-1 -mx-1 px-1 shrink-0">
          {[
            { actif: urgentesOnly, label: '🔥 Urgentes', toggle: () => setUrgentesOnly(v => !v) },
            { actif: horaire === 'WEEKEND', label: '📅 Ce weekend', toggle: () => setHoraire(h => h === 'WEEKEND' ? 'TOUS' : 'WEEKEND') },
            { actif: horaire === 'NUIT', label: '🌙 Nuit', toggle: () => setHoraire(h => h === 'NUIT' ? 'TOUS' : 'NUIT') },
            { actif: horaire === 'JOUR', label: '☀️ Jour', toggle: () => setHoraire(h => h === 'JOUR' ? 'TOUS' : 'JOUR') },
          ].map((chip) => (
            <button
              key={chip.label}
              type="button"
              onClick={chip.toggle}
              aria-pressed={chip.actif}
              className={`shrink-0 inline-flex items-center rounded-full px-4 min-h-[44px] md:min-h-0 md:py-1.5 text-xs font-semibold transition-snap border ${
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
        {vue === 'liste' && (
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
              filtreDeck={{ urgentesOnly, horaire }}
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

        {vue !== 'carte' ? (
          loading ? <ChargementPage /> : filtered.length > 0 ? (
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
            <div
              ref={mapRef}
              className="w-full rounded-xl border border-border overflow-hidden"
              style={{ height: 'min(calc(100dvh - 280px), 600px)', minHeight: '250px' }}
            />
            {filtered.length === 0 && !loading && (
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
                setProfession(soignant?.profession || '');
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
                  Tu recevras un email dès qu'une nouvelle mission{' '}
                  <strong>{professionAlerteLabel}</strong> correspondant à tes critères
                  (rayon {rayonKm} km) est publiée.
                </>
              ) : (
                <>
                  Tu recevras un email dès qu'une nouvelle mission correspondant à tes
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

import React, { useState, useEffect, useMemo, useRef } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { logger } from '@/lib/logger';
import { handleErrorSilent } from '@/lib/handleError';
import { toast } from 'sonner';
import { useNavigate } from 'react-router-dom';
import { SearchX, MapPin, List, Map as MapIcon, SlidersHorizontal } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { CarteMissionSoignant } from '@/components/CarteMissionSoignant';
import { BandeauDocumentsManquants } from '@/components/BandeauDocumentsManquants';
import { BandeauProfilIncomplet } from '@/components/BandeauProfilIncomplet';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { calculerDistanceKm } from '@/lib/geo';
import { PROFESSIONS, getLabelProfession, extraireContratPreference, missionCompatibleContrat, getTypesContratSoignant, peutExercerLiberal } from '@/lib/constantes';
import { getMissionsCompatiblesFilter } from '@/lib/profession-hierarchy';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { FiltresSauvegardes } from '@/components/FiltresSauvegardes';
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

export default function RechercheMissions() {
  usePageTitle('Recherche missions');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<SoignantData | null>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [nbAffiche, setNbAffiche] = useState(20);
  const [rcpExpiree, setRcpExpiree] = useState(false);
  // Filtres
  const [profession, setProfession] = useState<string>('');
  const [rayonKm, setRayonKm] = useState(50);
  const [tauxMin, setTauxMin] = useState(0);
  const [typeContrat, setTypeContrat] = useState<string>('TOUS');
  const [urgentesOnly, setUrgentesOnly] = useState(false);
  const [horaire, setHoraire] = useState<Horaire>('TOUS');
  const [showFilters, setShowFilters] = useState(true);
  const [villeRecherche, setVilleRecherche] = useState('');
  const debouncedVille = useDebounce(villeRecherche, 300);
  // Map
  const mapRef = useRef<HTMLDivElement>(null);
  const leafletMap = useRef<L.Map | null>(null);
  const markersLayer = useRef<L.LayerGroup | null>(null);

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

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants')
      .select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides, type_contrat, types_contrat_acceptes, type_exercice')
      .eq('id', user.id).maybeSingle()
      .then(({ data }) => {
        if (data) {
          const s = data as any;
          setSoignant(s);
          setProfession(s.profession);
          setRayonKm(s.rayon_deplacement_km || 50);
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
              setRcpExpiree(doc.statut_verification === 'REJETE' || doc.statut_verification === 'EXPIRE' || expire);
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
        soignant_assigne_id, cree_le, etablissement_id, type_contrat_recherche
      `)
        .eq('statut', 'OUVERTE')
        .gte('debut_le', new Date().toISOString())
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
        toast.error('Impossible de charger les missions. Vérifiez votre connexion.');
      }
      const enriched = data ? await enrichirEtablissements(data as any) : [];
      setMissions(enriched);
      setLoading(false);
    };
    fetchMissions();
  }, [user, soignant, profession, tauxMin, urgentesOnly]);

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
        // Distance filter only when searching by ville
        if (villeSearch && m.distance_km !== null && m.distance_km > rayonKm) return false;
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
            .bindPopup('<strong>Votre position</strong>');
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

  // No blocking guard — render even without soignant profile

  return (
    <LayoutApp role="SOIGNANT">
      {(!soignant || !soignant.profession) && <BandeauProfilIncomplet />}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-foreground">Recherche avancée</h1>
          <Button variant="outline" size="sm" onClick={() => setShowFilters(!showFilters)} className="gap-1.5 md:hidden">
            <SlidersHorizontal className="h-4 w-4" />
            Filtres
          </Button>
        </div>

        <BandeauDocumentsManquants tousDocumentsValides={!!soignant?.tous_documents_valides} rcpExpiree={rcpExpiree} />

        {/* Mes recherches sauvegardées (J2.3.C) */}
        <FiltresSauvegardes
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
            setShowFilters(true);
          }}
        />

        {/* Filters */}
        <div className={`${showFilters ? 'block' : 'hidden md:block'} card-base space-y-4`}>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {/* Ville / Code postal */}
            <div className="space-y-1.5">
              <Label className="text-xs font-medium text-muted-foreground">📍 Ville ou code postal</Label>
              <Input
                value={villeRecherche}
                onChange={(e) => setVilleRecherche(e.target.value)}
                placeholder="Ex : Paris, 75001..."
              />
              <p className="text-[10px] text-muted-foreground">Laissez vide pour utiliser votre position</p>
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
              <Label className="text-xs font-medium text-muted-foreground">Taux horaire minimum (€/h)</Label>
              <Input
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
              <Badge variant="outline">{filtered.length} mission{filtered.length > 1 ? 's' : ''}</Badge>
              <span>dans un rayon de {rayonKm} km</span>
            </div>
            <Button
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
            </Button>
          </div>
        </div>

        {/* Active filter chips — visible even when filters are collapsed on mobile */}
        {!showFilters && (villeRecherche || tauxMin > 0 || urgentesOnly || horaire !== 'TOUS' || typeContrat !== 'TOUS') && (
          <div className="flex flex-wrap gap-1.5 md:hidden">
            <Badge variant="outline" className="text-[10px]">{filtered.length} résultat{filtered.length > 1 ? 's' : ''}</Badge>
            {villeRecherche && <Badge variant="secondary" className="text-[10px]">📍 {villeRecherche}</Badge>}
            {tauxMin > 0 && <Badge variant="secondary" className="text-[10px]">≥ {tauxMin} €/h</Badge>}
            {urgentesOnly && <Badge variant="secondary" className="text-[10px]">🔥 Urgentes</Badge>}
            {horaire !== 'TOUS' && <Badge variant="secondary" className="text-[10px]">{horaire === 'NUIT' ? '🌙 Nuit' : horaire === 'WEEKEND' ? '📅 Weekend' : '☀️ Jour'}</Badge>}
            {typeContrat !== 'TOUS' && <Badge variant="secondary" className="text-[10px]">{typeContrat}</Badge>}
          </div>
        )}

        {/* Tabs Liste / Carte */}
        <Tabs defaultValue="liste" onValueChange={initMap}>
          <TabsList className="w-full max-w-xs">
            <TabsTrigger value="liste" className="gap-1.5 flex-1"><List className="h-4 w-4" />Liste</TabsTrigger>
            <TabsTrigger value="carte" className="gap-1.5 flex-1"><MapIcon className="h-4 w-4" />Carte</TabsTrigger>
          </TabsList>

          <TabsContent value="liste">
            {loading ? <ChargementPage /> : filtered.length > 0 ? (
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
                      Voir plus ({filtered.length - nbAffiche} restantes)
                    </button>
                  </div>
                )}
              </>
            ) : (
              <EtatVide
                icone={SearchX}
                titre="Aucune mission trouvée"
                sousTitre="Essayez d'élargir vos filtres ou d'augmenter le rayon de recherche."
              />
            )}
          </TabsContent>

          <TabsContent value="carte">
            <div
              ref={mapRef}
              className="w-full rounded-xl border border-border overflow-hidden"
              style={{ height: 'min(calc(100dvh - 280px), 600px)', minHeight: '250px' }}
            />
            {filtered.length === 0 && !loading && (
              <p className="text-sm text-muted-foreground text-center mt-3">Aucune mission à afficher sur la carte.</p>
            )}
          </TabsContent>
        </Tabs>
      </div>
    </LayoutApp>
  );
}

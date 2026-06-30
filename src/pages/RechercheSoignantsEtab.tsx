import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Search, Filter, MapPin, Star, ShieldCheck, Award, Briefcase, X, Loader2, ChevronRight } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { PROFESSIONS, getLabelProfession } from '@/lib/constantes';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonFavori } from '@/components/BoutonFavori';

interface SoignantResultat {
  id: string;
  prenom: string;
  nom_initiale: string;
  profession: string;
  specialite_medicale: string | null;
  type_exercice: 'LIBERAL' | 'SALARIE' | 'MIXTE';
  score_fiabilite: number | null;
  note_moyenne: number | null;
  nb_evaluations: number;
  total_missions_terminees: number;
  annees_experience: number | null;
  specialites: string[];
  bio_extrait: string;
  avatar_url: string | null;
  rpps_verifie: boolean;
  tous_documents_valides: boolean;
  disponible_urgence: boolean;
  ville: string | null;
  distance_km: number | null;
  priorite_missions_urgentes: boolean;
  badge_ambassadeur: boolean;
}

interface Filtres {
  profession: string;
  type_exercice: string;
  ville: string;
  distance_max_km: string;
  note_min: string;
  score_min: string;
  experience_min: string;
  disponible_urgence: boolean;
  documents_valides: boolean;
  recherche_texte: string;
}

const FILTRES_VIDES: Filtres = {
  profession: '',
  type_exercice: '',
  ville: '',
  distance_max_km: '',
  note_min: '',
  score_min: '',
  experience_min: '',
  disponible_urgence: false,
  documents_valides: false,
  recherche_texte: '',
};

const PAGE_SIZE = 20;

export default function RechercheSoignantsEtab() {
  usePageTitle('Recherche soignants');
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  const [filtres, setFiltres] = useState<Filtres>(() => ({
    profession: searchParams.get('profession') ?? '',
    type_exercice: searchParams.get('type_exercice') ?? '',
    ville: searchParams.get('ville') ?? '',
    distance_max_km: searchParams.get('distance') ?? '',
    note_min: searchParams.get('note_min') ?? '',
    score_min: searchParams.get('score_min') ?? '',
    experience_min: searchParams.get('experience') ?? '',
    disponible_urgence: searchParams.get('urgence') === '1',
    documents_valides: searchParams.get('docs') === '1',
    recherche_texte: searchParams.get('q') ?? '',
  }));

  const [soignants, setSoignants] = useState<SoignantResultat[]>([]);
  const [countTotal, setCountTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filtresOuverts, setFiltresOuverts] = useState(false);

  const filtresActifs = useMemo(() => {
    const f = filtres;
    let count = 0;
    if (f.profession) count++;
    if (f.type_exercice) count++;
    if (f.ville) count++;
    if (f.distance_max_km) count++;
    if (f.note_min) count++;
    if (f.score_min) count++;
    if (f.experience_min) count++;
    if (f.disponible_urgence) count++;
    if (f.documents_valides) count++;
    if (f.recherche_texte) count++;
    return count;
  }, [filtres]);

  const fetchSoignants = async (newOffset: number, isLoadMore: boolean) => {
    if (isLoadMore) setLoadingMore(true); else setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('fn_rechercher_soignants_etab' as any, {
        p_profession: filtres.profession || null,
        p_specialites: null,
        p_ville: filtres.ville || null,
        p_distance_max_km: filtres.distance_max_km ? parseInt(filtres.distance_max_km, 10) : null,
        p_type_exercice: filtres.type_exercice || null,
        p_note_min: filtres.note_min ? parseFloat(filtres.note_min) : null,
        p_score_min: filtres.score_min ? parseInt(filtres.score_min, 10) : null,
        p_experience_min: filtres.experience_min ? parseInt(filtres.experience_min, 10) : null,
        p_disponible_urgence: filtres.disponible_urgence ? true : null,
        p_documents_valides: filtres.documents_valides ? true : null,
        p_recherche_texte: filtres.recherche_texte || null,
        p_limit: PAGE_SIZE,
        p_offset: newOffset,
      });
      if (rpcError) throw rpcError;
      const payload = data as any;
      if (payload?.error) {
        setError(payload.error);
        toast.error(payload.error);
        return;
      }
      const nouveaux: SoignantResultat[] = payload?.soignants ?? [];
      setSoignants(isLoadMore ? (prev) => [...prev, ...nouveaux] : nouveaux);
      setCountTotal(payload?.count_total ?? 0);
      setOffset(newOffset);
    } catch (e: any) {
      const msg = e?.message ?? 'Erreur lors de la recherche de soignants. Veuillez réessayer.';
      setError(msg);
      toast.error(msg);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  };

  // Sync URL <-> filtres
  useEffect(() => {
    const params: Record<string, string> = {};
    if (filtres.profession) params.profession = filtres.profession;
    if (filtres.type_exercice) params.type_exercice = filtres.type_exercice;
    if (filtres.ville) params.ville = filtres.ville;
    if (filtres.distance_max_km) params.distance = filtres.distance_max_km;
    if (filtres.note_min) params.note_min = filtres.note_min;
    if (filtres.score_min) params.score_min = filtres.score_min;
    if (filtres.experience_min) params.experience = filtres.experience_min;
    if (filtres.disponible_urgence) params.urgence = '1';
    if (filtres.documents_valides) params.docs = '1';
    if (filtres.recherche_texte) params.q = filtres.recherche_texte;
    setSearchParams(params, { replace: true });
  }, [filtres, setSearchParams]);

  // Debounce 300ms sur filtres → fetch
  useEffect(() => {
    const t = setTimeout(() => fetchSoignants(0, false), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtres]);

  const reset = () => setFiltres(FILTRES_VIDES);
  const update = <K extends keyof Filtres>(key: K, value: Filtres[K]) => setFiltres((p) => ({ ...p, [key]: value }));
  const peutCharger = soignants.length < countTotal;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6 flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Annuaire soignants</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {countTotal > 0 ? `${countTotal} soignant${countTotal > 1 ? 's' : ''} disponible${countTotal > 1 ? 's' : ''}` : 'Recherchez des soignants pour vos missions'}
          </p>
        </div>
        <button
          type="button"
          onClick={() => navigate('/etablissement/parametres/recherches-sauvegardees')}
          className="btn-secondary text-xs inline-flex items-center gap-1.5 shrink-0"
        >
          <Star className="h-3.5 w-3.5" /> Recherches sauvegardées
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-6">
        {/* Sidebar filtres */}
        <aside className={`lg:block ${filtresOuverts ? 'block' : 'hidden'}`}>
          <div className="card-base sticky top-4 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold text-foreground flex items-center gap-2"><Filter className="h-4 w-4" /> Filtres</h2>
              {filtresActifs > 0 && (
                <button onClick={reset} className="text-xs text-primary hover:underline">Réinitialiser</button>
              )}
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Recherche libre</label>
              <div className="relative">
                <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
                <input
                  type="text"
                  value={filtres.recherche_texte}
                  onChange={(e) => update('recherche_texte', e.target.value)}
                  placeholder="Prénom, mots-clés bio…"
                  className="w-full pl-8 pr-2 py-2 text-sm rounded-lg border border-border bg-background"
                />
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Profession</label>
              <select
                value={filtres.profession}
                onChange={(e) => update('profession', e.target.value)}
                className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
              >
                <option value="">Toutes</option>
                {PROFESSIONS.map((p) => (
                  <option key={p.valeur} value={p.valeur}>{p.label}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Type d'exercice</label>
              <select
                value={filtres.type_exercice}
                onChange={(e) => update('type_exercice', e.target.value)}
                className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
              >
                <option value="">Tous</option>
                <option value="LIBERAL">Libéral</option>
                <option value="SALARIE">Salarié</option>
                <option value="MIXTE">Salarié + Libéral</option>
              </select>
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Ville</label>
              <input
                type="text"
                value={filtres.ville}
                onChange={(e) => update('ville', e.target.value)}
                placeholder="Paris, Lyon…"
                className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
              />
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Distance max (km)</label>
              <input
                type="number"
                min={0}
                max={500}
                value={filtres.distance_max_km}
                onChange={(e) => update('distance_max_km', e.target.value)}
                placeholder="ex. 30"
                className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
              />
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs font-medium text-muted-foreground mb-1 block">Note ≥</label>
                <input
                  type="number" min={0} max={5} step={0.5}
                  value={filtres.note_min}
                  onChange={(e) => update('note_min', e.target.value)}
                  placeholder="0-5"
                  className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
                />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground mb-1 block">Score ≥</label>
                <input
                  type="number" min={0} max={100}
                  value={filtres.score_min}
                  onChange={(e) => update('score_min', e.target.value)}
                  placeholder="0-100"
                  className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
                />
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">Expérience min (années)</label>
              <input
                type="number" min={0} max={50}
                value={filtres.experience_min}
                onChange={(e) => update('experience_min', e.target.value)}
                placeholder="0"
                className="w-full px-2 py-2 text-sm rounded-lg border border-border bg-background"
              />
            </div>

            <div className="space-y-2 pt-2 border-t border-border">
              <label className="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="checkbox"
                  checked={filtres.disponible_urgence}
                  onChange={(e) => update('disponible_urgence', e.target.checked)}
                  className="rounded border-border"
                />
                <span>🚨 Disponible pour urgences</span>
              </label>
              <label className="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="checkbox"
                  checked={filtres.documents_valides}
                  onChange={(e) => update('documents_valides', e.target.checked)}
                  className="rounded border-border"
                />
                <span>Documents complets</span>
              </label>
            </div>
          </div>
        </aside>

        {/* Résultats */}
        <main>
          <div className="lg:hidden mb-3 flex items-center gap-2">
            <button
              type="button"
              onClick={() => setFiltresOuverts((v) => !v)}
              className="btn-secondary text-sm inline-flex items-center gap-2"
            >
              {filtresOuverts ? <X className="h-4 w-4" /> : <Filter className="h-4 w-4" />}
              {filtresOuverts ? 'Masquer filtres' : `Filtres${filtresActifs > 0 ? ` (${filtresActifs})` : ''}`}
            </button>
          </div>

          {loading ? (
            <ChargementPage />
          ) : error ? (
            <div className="card-base text-center py-10">
              <p className="text-sm text-destructive">{error}</p>
              <button onClick={() => fetchSoignants(0, false)} className="text-xs text-primary hover:underline mt-2">Réessayer</button>
            </div>
          ) : soignants.length === 0 ? (
            <div className="card-base text-center py-10">
              <p className="text-sm text-muted-foreground">Aucun soignant ne correspond à vos critères.</p>
              {filtresActifs > 0 && (
                <button onClick={reset} className="text-xs text-primary hover:underline mt-2">Réinitialiser les filtres</button>
              )}
            </div>
          ) : (
            <>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {soignants.map((s) => (
                  <CarteSoignant key={s.id} soignant={s} etablissementId={user?.id} onClick={() => navigate(`/etablissement/soignants/${s.id}`)} />
                ))}
              </div>

              {peutCharger && (
                <div className="mt-6 text-center">
                  <button
                    type="button"
                    onClick={() => fetchSoignants(offset + PAGE_SIZE, true)}
                    disabled={loadingMore}
                    className="btn-secondary text-sm inline-flex items-center gap-2"
                  >
                    {loadingMore ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                    {loadingMore ? 'Chargement…' : `Voir plus (${countTotal - soignants.length} restant${countTotal - soignants.length > 1 ? 's' : ''})`}
                  </button>
                </div>
              )}
            </>
          )}
        </main>
      </div>
    </LayoutApp>
  );
}

function CarteSoignant({ soignant: s, onClick, etablissementId }: { soignant: SoignantResultat; onClick: () => void; etablissementId?: string }) {
  const initiales = `${s.prenom?.[0] ?? ''}${s.nom_initiale?.[0] ?? ''}`.toUpperCase() || 'SD';
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); } }}
      className="card-base relative text-left cursor-pointer transition-shadow hover:shadow-md focus:outline-none focus:ring-2 focus:ring-primary/40"
    >
      {etablissementId && (
        <div className="absolute top-2 right-2 z-10" onClick={(e) => e.stopPropagation()}>
          <BoutonFavori soignantId={s.id} etablissementId={etablissementId} />
        </div>
      )}
      <div className="flex items-start gap-3">
        {s.avatar_url ? (
          <img src={s.avatar_url} alt="" className="h-14 w-14 rounded-2xl object-cover border border-border" />
        ) : (
          <div className="h-14 w-14 rounded-2xl border border-border bg-muted flex items-center justify-center text-lg font-bold text-foreground shrink-0">
            {initiales}
          </div>
        )}
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-semibold text-foreground truncate">
                {s.prenom} {s.nom_initiale}
              </p>
              <p className="text-xs text-muted-foreground inline-flex items-center gap-1 mt-0.5">
                <Briefcase className="h-3.5 w-3.5" /> {getLabelProfession(s.profession)}
                {s.specialite_medicale && <span> · {s.specialite_medicale}</span>}
              </p>
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0 mt-1" />
          </div>

          <div className="flex flex-wrap items-center gap-1.5 mt-2 text-xs">
            {s.type_exercice && (
              <span className={`inline-flex items-center rounded-full px-2 py-0.5 font-medium ${s.type_exercice === 'LIBERAL' ? 'bg-info/10 text-info' : s.type_exercice === 'MIXTE' ? 'bg-rose/10 text-rose' : 'bg-muted text-muted-foreground'}`}>
                {s.type_exercice === 'MIXTE' ? 'Salarié + Libéral' : s.type_exercice === 'LIBERAL' ? 'Libéral' : 'Salarié'}
              </span>
            )}
            {s.score_fiabilite != null ? (
              <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary px-2 py-0.5 font-medium">
                <ShieldCheck className="h-3 w-3" /> {s.score_fiabilite}/100
              </span>
            ) : (
              <span className="inline-flex items-center rounded-full bg-muted text-muted-foreground px-2 py-0.5 text-[11px]">Pas encore d'évaluation</span>
            )}
            {s.note_moyenne != null && (
              <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 text-amber-700 px-2 py-0.5 font-medium">
                <Star className="h-3 w-3" /> {Number(s.note_moyenne).toFixed(1)} ({s.nb_evaluations})
              </span>
            )}
            {s.rpps_verifie && (
              <span className="inline-flex items-center gap-1 rounded-full bg-success/10 text-success px-2 py-0.5 font-medium">
                <ShieldCheck className="h-3 w-3" /> RPPS
              </span>
            )}
            {s.tous_documents_valides && (
              <span className="inline-flex items-center gap-1 rounded-full bg-success/10 text-success px-2 py-0.5 font-medium">Docs OK</span>
            )}
            {s.disponible_urgence && (
              <span className="inline-flex items-center rounded-full bg-orange-50 text-orange-700 px-2 py-0.5 font-medium">🚨 Urgence</span>
            )}
            {s.badge_ambassadeur && (
              <span className="inline-flex items-center gap-1 rounded-full bg-purple-50 text-purple-700 px-2 py-0.5 font-medium">
                <Award className="h-3 w-3" /> Ambassadeur
              </span>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-3 mt-2 text-xs text-muted-foreground">
            {s.ville && (
              <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" /> {s.ville}{s.distance_km != null ? ` · ${s.distance_km} km` : ''}</span>
            )}
            {s.annees_experience != null && s.annees_experience > 0 && (
              <span>{s.annees_experience} an{s.annees_experience > 1 ? 's' : ''} d'expérience</span>
            )}
            {s.total_missions_terminees > 0 && (
              <span>{s.total_missions_terminees} mission{s.total_missions_terminees > 1 ? 's' : ''}</span>
            )}
          </div>

          {s.bio_extrait && (
            <p className="text-xs text-foreground/80 mt-2 line-clamp-2">{s.bio_extrait}</p>
          )}
        </div>
      </div>
    </div>
  );
}

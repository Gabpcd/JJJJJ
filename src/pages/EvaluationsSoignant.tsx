import { useEffect, useState } from 'react';
import { Star, Calendar, Building2, TrendingUp, Flag, X, Pencil } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Notation {
  id: string;
  mission_id: string;
  mission_intitule: string;
  mission_fin_le: string;
  etablissement_id: string;
  etablissement_nom: string;
  critere_1: number;
  critere_2: number;
  critere_3: number;
  critere_4: number;
  note_moyenne: number;
  commentaire: string | null;
  signale: boolean;
  cree_le: string;
}

interface Stats {
  note_moyenne_globale: number;
  total_evaluations: number;
  pct_5_etoiles: number;
}

interface EtabFiltre { id: string; nom: string }
interface PointEvolution { mois: string; note_moyenne: number; nb: number }

const PAR_PAGE = 20;

function StarsRow({ note }: { note: number }) {
  return (
    <div className="inline-flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`h-3.5 w-3.5 ${i <= Math.round(note) ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground/30'}`}
        />
      ))}
      <span className="ml-1 text-xs font-medium text-foreground">{note.toFixed(1)}</span>
    </div>
  );
}

export default function EvaluationsSoignant() {
  usePageTitle('Mes évaluations');
  return (
    <LayoutApp role="SOIGNANT">
      <EvaluationsContent />
    </LayoutApp>
  );
}

export function EvaluationsContent() {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [notations, setNotations] = useState<Notation[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [evolution, setEvolution] = useState<PointEvolution[]>([]);
  const [etabsDisponibles, setEtabsDisponibles] = useState<EtabFiltre[]>([]);
  const [total, setTotal] = useState(0);

  const [periode, setPeriode] = useState<'3M' | '6M' | '12M' | 'TOUT'>('TOUT');
  const [noteMin, setNoteMin] = useState<number | ''>('');
  const [etabFiltre, setEtabFiltre] = useState<string>('');
  const [page, setPage] = useState(0);

  const [notationSignaler, setNotationSignaler] = useState<Notation | null>(null);
  const [notationEditer, setNotationEditer] = useState<Notation | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_mes_notations_recues_avec_stats' as any, {
      p_periode: periode,
      p_note_min: noteMin === '' ? null : noteMin,
      p_etablissement_id: etabFiltre || null,
      p_limit: PAR_PAGE,
      p_offset: page * PAR_PAGE,
    });
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || 'Erreur chargement.' });
      setLoading(false);
      return;
    }
    const result = data as any;
    setNotations(result.notations || []);
    setStats(result.stats || null);
    setEvolution(result.evolution_6m || []);
    setEtabsDisponibles(result.etabs_disponibles || []);
    setTotal(result.total || 0);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [periode, noteMin, etabFiltre, page]);

  if (loading && notations.length === 0) return <ChargementPage />;

  const totalPages = Math.ceil(total / PAR_PAGE);

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Star className="h-6 w-6 text-yellow-400 fill-yellow-400" />
          Mes évaluations reçues
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Notes laissées par les établissements après tes missions.
        </p>
      </div>

      {/* KPIs */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
          <div className="rounded-2xl border-2 border-primary/30 bg-primary/5 p-4">
            <p className="text-[10px] uppercase font-semibold text-foreground mb-1">Note moyenne</p>
            <div className="flex items-baseline gap-1">
              <p className="text-2xl font-bold text-primary tabular-nums">{stats.note_moyenne_globale.toFixed(1)}</p>
              <Star className="h-4 w-4 fill-yellow-400 text-yellow-400" />
            </div>
          </div>
          <div className="rounded-2xl border-2 border-info/30 bg-info/5 p-4">
            <p className="text-[10px] uppercase font-semibold text-foreground mb-1">Total évaluations</p>
            <p className="text-2xl font-bold text-info tabular-nums">{stats.total_evaluations}</p>
          </div>
          <div className="rounded-2xl border-2 border-success/30 bg-success/5 p-4">
            <p className="text-[10px] uppercase font-semibold text-foreground mb-1">% 5 étoiles</p>
            <p className="text-2xl font-bold text-success tabular-nums">{stats.pct_5_etoiles}%</p>
          </div>
          <div className="rounded-2xl border-2 border-warning/30 bg-warning/5 p-4">
            <p className="text-[10px] uppercase font-semibold text-foreground mb-1 inline-flex items-center gap-1">
              <TrendingUp className="h-3 w-3" /> Évolution 6m
            </p>
            <p className="text-2xl font-bold text-warning tabular-nums">
              {evolution.length > 0
                ? evolution[evolution.length - 1].note_moyenne.toFixed(1)
                : '—'}
            </p>
            <p className="text-[10px] text-muted-foreground mt-0.5">dernier mois</p>
          </div>
        </div>
      )}

      {/* Mini chart évolution */}
      {evolution.length > 0 && (
        <div className="rounded-xl border border-border bg-card p-4 mb-6">
          <p className="text-xs font-semibold text-foreground mb-2 inline-flex items-center gap-1">
            <TrendingUp className="h-3 w-3" /> Note moyenne 6 derniers mois
          </p>
          <div className="flex items-end gap-1.5 h-20">
            {evolution.map((p) => {
              const heightPct = (p.note_moyenne / 5) * 100;
              return (
                <div key={p.mois} className="flex-1 flex flex-col items-center gap-1" title={`${p.mois}: ${p.note_moyenne}/5 (${p.nb} évals)`}>
                  <div
                    className="w-full bg-primary/30 rounded-t"
                    style={{ height: `${heightPct}%` }}
                  />
                  <span className="text-[9px] text-muted-foreground">
                    {format(new Date(p.mois + '-01'), 'MMM', { locale: fr })}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Filtres */}
      <div className="flex flex-col sm:flex-row gap-2 mb-4 flex-wrap">
        <select
          value={periode}
          onChange={(e) => { setPeriode(e.target.value as any); setPage(0); }}
          className="input-base sm:w-44"
          aria-label="Filtrer par période"
        >
          <option value="TOUT">Toutes périodes</option>
          <option value="3M">3 derniers mois</option>
          <option value="6M">6 derniers mois</option>
          <option value="12M">12 derniers mois</option>
        </select>
        <select
          value={noteMin}
          onChange={(e) => { setNoteMin(e.target.value === '' ? '' : Number(e.target.value)); setPage(0); }}
          className="input-base sm:w-40"
          aria-label="Filtrer par note minimum"
        >
          <option value="">Toutes notes</option>
          <option value="5">5 étoiles</option>
          <option value="4">4 étoiles et +</option>
          <option value="3">3 étoiles et +</option>
        </select>
        <select
          value={etabFiltre}
          onChange={(e) => { setEtabFiltre(e.target.value); setPage(0); }}
          className="input-base sm:w-60"
          aria-label="Filtrer par établissement"
        >
          <option value="">Tous établissements</option>
          {etabsDisponibles.map((e) => (
            <option key={e.id} value={e.id}>{e.nom}</option>
          ))}
        </select>
      </div>

      <p className="text-xs text-muted-foreground mb-2">
        {total} évaluation{total > 1 ? 's' : ''}
      </p>

      {(() => {
        const colonnes: ColonneTableau<Notation>[] = [
          { cle: 'note', titre: 'Note' },
          { cle: 'mission', titre: 'Mission' },
          { cle: 'etab', titre: 'Établissement' },
          { cle: 'commentaire', titre: 'Commentaire' },
          { cle: 'date', titre: 'Date' },
          { cle: 'actions', titre: '', align: 'right', largeur: 'w-32' },
        ];
        return (
          <TableOuCartes
            colonnes={colonnes}
            donnees={notations}
            getId={(n) => n.id}
            etatVide={<EmptyState icone={<Star />} mascotte="empty" titre="Aucune évaluation" description="Les évaluations reçues apparaîtront ici." />}
            renduCellule={(n, col) => {
              switch (col.cle) {
                case 'note':
                  return <StarsRow note={n.note_moyenne} />;
                case 'mission':
                  return <span className="font-medium text-foreground line-clamp-1">{n.mission_intitule}</span>;
                case 'etab':
                  return <span className="text-sm text-muted-foreground">{n.etablissement_nom}</span>;
                case 'commentaire':
                  return n.commentaire
                    ? <span className="text-xs italic line-clamp-2">« {n.commentaire} »</span>
                    : <span className="text-xs text-muted-foreground">—</span>;
                case 'date':
                  return <span className="text-xs text-muted-foreground whitespace-nowrap">{format(new Date(n.cree_le), 'd MMM yyyy', { locale: fr })}</span>;
                case 'actions':
                  return (
                    <div className="flex items-center gap-1 justify-end">
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-8 text-xs gap-1"
                        onClick={(e) => { e.stopPropagation(); setNotationEditer(n); }}
                      >
                        <Pencil className="h-3 w-3" />
                        Éditer
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-8 text-xs gap-1"
                        disabled={n.signale}
                        onClick={(e) => { e.stopPropagation(); setNotationSignaler(n); }}
                      >
                        <Flag className="h-3 w-3" />
                        {n.signale ? 'Signalée' : 'Signaler'}
                      </Button>
                    </div>
                  );
                default:
                  return null;
              }
            }}
            renduCarte={(n) => (
              <div className="space-y-2">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <StarsRow note={n.note_moyenne} />
                      <span className="text-[11px] text-muted-foreground inline-flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        {format(new Date(n.cree_le), 'd MMM yyyy', { locale: fr })}
                      </span>
                    </div>
                    <p className="text-sm font-semibold text-foreground line-clamp-1">{n.mission_intitule}</p>
                    <p className="text-xs text-muted-foreground inline-flex items-center gap-1 mt-0.5">
                      <Building2 className="h-3 w-3" /> {n.etablissement_nom}
                    </p>
                    {n.commentaire && (
                      <p className="text-xs text-foreground mt-2 italic">« {n.commentaire} »</p>
                    )}
                  </div>
                </div>
                <div className="pt-2 border-t border-border flex justify-end gap-2">
                  <Button
                    size="sm"
                    variant="ghost"
                    className="text-xs min-h-[44px] gap-1.5 text-muted-foreground"
                    onClick={(e) => { e.stopPropagation(); setNotationEditer(n); }}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                    Éditer
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    className="text-xs min-h-[44px] gap-1.5 text-muted-foreground hover:text-destructive"
                    disabled={n.signale}
                    onClick={(e) => { e.stopPropagation(); setNotationSignaler(n); }}
                  >
                    <Flag className="h-3.5 w-3.5" />
                    {n.signale ? 'Déjà signalée' : 'Signaler cette évaluation'}
                  </Button>
                </div>
              </div>
            )}
          />
        );
      })()}

      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-xs text-muted-foreground">Page {page + 1} / {totalPages}</p>
          <div className="flex gap-2">
            <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0} className="btn-secondary text-xs disabled:opacity-50">Précédent</button>
            <button onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1} className="btn-secondary text-xs disabled:opacity-50">Suivant</button>
          </div>
        </div>
      )}

      {notationSignaler && (
        <ModaleSignaler
          notation={notationSignaler}
          onFermer={() => setNotationSignaler(null)}
          onSignale={() => { setNotationSignaler(null); charger(); }}
        />
      )}

      {notationEditer && (
        <ModaleEditer
          notation={notationEditer}
          onFermer={() => setNotationEditer(null)}
          onSauvegarde={() => { setNotationEditer(null); charger(); }}
        />
      )}
    </>
  );
}

function StarPicker({ value, onChange, label }: { value: number; onChange: (v: number) => void; label: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-medium text-foreground">{label}</span>
      <div className="inline-flex items-center gap-0.5">
        {[1, 2, 3, 4, 5].map((i) => (
          <button
            key={i}
            type="button"
            onClick={() => onChange(i)}
            className="p-0.5 focus:outline-none"
            aria-label={`${i} étoile${i > 1 ? 's' : ''}`}
          >
            <Star className={`h-6 w-6 transition-colors ${i <= value ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground/30'}`} />
          </button>
        ))}
      </div>
    </div>
  );
}

function ModaleEditer({ notation, onFermer, onSauvegarde }: { notation: Notation; onFermer: () => void; onSauvegarde: () => void }) {
  const [critere1, setCritere1] = useState(notation.critere_1);
  const [critere2, setCritere2] = useState(notation.critere_2);
  const [critere3, setCritere3] = useState(notation.critere_3);
  const [critere4, setCritere4] = useState(notation.critere_4);
  const [commentaire, setCommentaire] = useState(notation.commentaire || '');
  const [loading, setLoading] = useState(false);

  async function sauvegarder() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_modifier_notation_mission' as any, {
      p_notation_id: notation.id,
      p_critere_1: critere1,
      p_critere_2: critere2,
      p_critere_3: critere3,
      p_critere_4: critere4,
      p_commentaire: commentaire.trim() || null,
    });
    setLoading(false);
    if (error || (data && (data as any).success === false)) {
      toast.error(error?.message || (data as any)?.error || 'Erreur lors de la mise à jour.');
      return;
    }
    toast.success('Évaluation mise à jour.');
    onSauvegarde();
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-foreground">Modifier l'évaluation</h2>
          <button onClick={onFermer} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-semibold text-foreground">{notation.mission_intitule}</p>
          <p className="text-muted-foreground">{notation.etablissement_nom}</p>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <StarPicker value={critere1} onChange={setCritere1} label="Critère 1" />
          <StarPicker value={critere2} onChange={setCritere2} label="Critère 2" />
          <StarPicker value={critere3} onChange={setCritere3} label="Critère 3" />
          <StarPicker value={critere4} onChange={setCritere4} label="Critère 4" />
        </div>
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Commentaire (optionnel)</span>
          <textarea
            value={commentaire}
            onChange={(e) => setCommentaire(e.target.value)}
            className="input-base"
            rows={3}
            placeholder="Ajoutez un commentaire…"
            disabled={loading}
          />
        </label>
        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">Annuler</button>
          <button
            onClick={sauvegarder}
            disabled={loading}
            className="bg-primary text-primary-foreground rounded-xl px-4 py-2 text-sm font-medium hover:bg-primary/90 disabled:opacity-50 flex-1"
          >
            {loading ? 'Enregistrement…' : 'Sauvegarder'}
          </button>
        </div>
      </div>
    </div>
  );
}

function ModaleSignaler({ notation, onFermer, onSignale }: { notation: Notation; onFermer: () => void; onSignale: () => void }) {
  const { afficherNotification } = useNotification();
  const [motif, setMotif] = useState('');
  const [loading, setLoading] = useState(false);

  async function signaler() {
    if (motif.trim().length < 10) {
      afficherNotification({ type: 'erreur', message: 'Motif obligatoire (min 10 caractères).' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_signaler_notation' as any, {
      p_notation_id: notation.id,
      p_motif: motif.trim(),
    });
    setLoading(false);
    if (error || (data && (data as any).success === false)) {
      afficherNotification({ type: 'erreur', message: error?.message || (data as any)?.error || 'Erreur signalement.' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Signalement transmis à l\'admin Jolene.' });
    onSignale();
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-foreground">Signaler cette évaluation</h2>
          <button onClick={onFermer} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-semibold text-foreground">{notation.mission_intitule}</p>
          <p className="text-muted-foreground">Note moyenne : {notation.note_moyenne.toFixed(1)}/5</p>
        </div>
        <p className="text-xs text-muted-foreground">
          Si cette évaluation est abusive, inappropriée ou injuste, signale-la.
          Un administrateur Jolene examinera ton signalement et pourra masquer la notation si justifié.
        </p>
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif * (min 10 caractères)</span>
          <textarea
            value={motif}
            onChange={(e) => setMotif(e.target.value)}
            className="input-base"
            rows={4}
            placeholder="Explique pourquoi cette évaluation te paraît abusive…"
            disabled={loading}
          />
          <span className="text-[10px] text-muted-foreground">{motif.length} / 10+</span>
        </label>
        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">Annuler</button>
          <button
            onClick={signaler}
            disabled={loading || motif.trim().length < 10}
            className="bg-destructive text-destructive-foreground rounded-xl px-4 py-2 text-sm font-medium hover:bg-destructive/90 disabled:opacity-50 flex-1"
          >
            Signaler
          </button>
        </div>
      </div>
    </div>
  );
}

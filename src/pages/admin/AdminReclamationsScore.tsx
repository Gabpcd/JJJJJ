import { useEffect, useState } from 'react';
import { Loader2, FileText, AlertCircle, CheckCircle, XCircle, Edit3 } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Reclamation {
  id: string;
  evenement_type: 'SOIGNANT' | 'ETAB';
  evenement_id: string;
  event_type_evenement: string;
  event_points: number;
  event_motif: string;
  event_cree_le: string;
  contesteur_id: string;
  motif_categorie: string;
  texte_libre: string;
  justificatif_storage_path: string | null;
  statut: 'PENDING' | 'TREATED' | 'CANCELLED';
  decision_admin: 'MAINTENIR' | 'REDUIRE' | 'ANNULER' | null;
  motif_admin: string | null;
  cree_le: string;
  jours_attente: number;
}

/**
 * Page admin /admin/reclamations-score (PR 8 Sprint 3.5).
 *
 * Liste des réclamations de score avec actions MAINTENIR/REDUIRE/ANNULER.
 * Décision propagée automatiquement aux événements + recalcul score.
 */
export default function AdminReclamationsScore() {
  usePageTitle('Réclamations score');
  const { afficherNotification } = useNotification();
  const [filtre, setFiltre] = useState<'PENDING' | 'TREATED' | 'TOUS'>('PENDING');
  const [reclamations, setReclamations] = useState<Reclamation[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectionnee, setSelectionnee] = useState<Reclamation | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_reclamations' as any, {
      p_statut: filtre, p_limit: 100,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
    } else if ((data as any)?.success) {
      setReclamations(((data as any).reclamations || []) as Reclamation[]);
    }
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtre]);

  return (
    <LayoutAdmin>
      <div className="max-w-5xl mx-auto p-4 space-y-4">
        <h1 className="text-2xl font-bold text-foreground">Réclamations score</h1>

        <div className="flex gap-2">
          {(['PENDING', 'TREATED', 'TOUS'] as const).map(f => (
            <button key={f} onClick={() => setFiltre(f)}
              className={`px-3 py-1.5 rounded-lg text-sm ${filtre === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground hover:bg-accent'}`}>
              {f === 'PENDING' ? 'En attente' : f === 'TREATED' ? 'Traitées' : 'Toutes'}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>
        ) : reclamations.length === 0 ? (
          <p className="text-center text-muted-foreground py-8 italic">Aucune réclamation</p>
        ) : (
          <div className="space-y-2">
            {reclamations.map(r => (
              <div key={r.id}
                className={`rounded-xl border p-4 ${r.statut === 'PENDING' && r.jours_attente > 7
                  ? 'border-destructive bg-destructive/5'
                  : r.statut === 'PENDING'
                  ? 'border-amber-300 bg-amber-50/40 dark:bg-amber-950/20'
                  : 'border-border bg-card'}`}>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-xs font-mono bg-muted px-1.5 py-0.5 rounded">{r.evenement_type}</span>
                      <span className="font-semibold text-foreground">{r.event_type_evenement}</span>
                      <span className="font-mono text-destructive">{r.event_points} pts</span>
                      {r.statut === 'PENDING' && (
                        <span className={`text-xs px-2 py-0.5 rounded-full ${r.jours_attente > 7
                          ? 'bg-destructive text-destructive-foreground'
                          : 'bg-amber-200 text-amber-900 dark:bg-amber-800 dark:text-amber-100'}`}>
                          {Math.round(r.jours_attente)}j d'attente
                        </span>
                      )}
                      {r.statut === 'TREATED' && r.decision_admin && (
                        <span className={`text-xs px-2 py-0.5 rounded-full ${
                          r.decision_admin === 'ANNULER' ? 'bg-emerald-200 text-emerald-900' :
                          r.decision_admin === 'REDUIRE' ? 'bg-blue-200 text-blue-900' :
                          'bg-muted text-foreground'}`}>
                          {r.decision_admin}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      <strong>Event :</strong> {r.event_motif}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">
                      <strong>Motif réclamation :</strong> {r.motif_categorie}
                    </p>
                    <p className="text-sm text-foreground mt-2 italic">« {r.texte_libre} »</p>
                    {r.justificatif_storage_path && (
                      <a href={`https://flripxtsyegjshnhzjkz.supabase.co/storage/v1/object/sign/justificatifs/${encodeURIComponent(r.justificatif_storage_path)}`}
                        target="_blank" rel="noopener noreferrer"
                        className="text-xs text-primary inline-flex items-center gap-1 mt-1">
                        <FileText className="h-3 w-3" /> Justificatif joint
                      </a>
                    )}
                    {r.motif_admin && (
                      <p className="text-xs mt-2 bg-muted/40 p-2 rounded">
                        <strong>Décision admin :</strong> {r.motif_admin}
                      </p>
                    )}
                    <p className="text-[10px] text-muted-foreground mt-2">
                      Créée {format(new Date(r.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  </div>
                  {r.statut === 'PENDING' && (
                    <button onClick={() => setSelectionnee(r)} className="btn-primary text-xs">Traiter</button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {selectionnee && (
          <ModaleDecision
            reclamation={selectionnee}
            onFermer={() => setSelectionnee(null)}
            onTraitee={() => { setSelectionnee(null); charger(); }}
          />
        )}
      </div>
    </LayoutAdmin>
  );
}

function ModaleDecision({ reclamation, onFermer, onTraitee }: {
  reclamation: Reclamation; onFermer: () => void; onTraitee: () => void;
}) {
  const { afficherNotification } = useNotification();
  const [decision, setDecision] = useState<'MAINTENIR' | 'REDUIRE' | 'ANNULER'>('MAINTENIR');
  const [pointsCorriges, setPointsCorriges] = useState<string>(Math.max(-5, Math.ceil(reclamation.event_points / 2)).toString());
  const [motifAdmin, setMotifAdmin] = useState('');
  const [loading, setLoading] = useState(false);

  async function soumettre() {
    if (motifAdmin.trim().length < 10) {
      afficherNotification({ type: 'erreur', message: 'Motif admin min 10 caractères.' });
      return;
    }
    if (decision === 'REDUIRE') {
      const pc = parseInt(pointsCorriges);
      if (isNaN(pc) || pc >= 0) {
        afficherNotification({ type: 'erreur', message: 'Points corrigés doivent être négatifs (ex: -5).' });
        return;
      }
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_traiter_reclamation' as any, {
        p_reclamation_id: reclamation.id,
        p_decision: decision,
        p_points_corriges: decision === 'REDUIRE' ? parseInt(pointsCorriges) : null,
        p_motif_admin: motifAdmin.trim(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      afficherNotification({ type: 'succes', message: 'Décision appliquée. Score recalculé + notif envoyée.' });
      onTraitee();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-xl max-w-lg w-full p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-foreground">Décider la réclamation</h2>

        <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-1">
          <p className="font-semibold">{reclamation.event_type_evenement} <span className="font-mono text-destructive">({reclamation.event_points} pts)</span></p>
          <p>Motif catégorie : <strong>{reclamation.motif_categorie}</strong></p>
          <p className="italic">« {reclamation.texte_libre} »</p>
        </div>

        <div className="space-y-2">
          <span className="text-xs font-medium block">Décision *</span>
          {[
            { v: 'MAINTENIR', l: '✋ MAINTENIR la pénalité (réclamation rejetée)', i: <XCircle className="h-4 w-4 text-muted-foreground" /> },
            { v: 'REDUIRE', l: '⚖️ RÉDUIRE la pénalité', i: <Edit3 className="h-4 w-4 text-blue-600" /> },
            { v: 'ANNULER', l: '✅ ANNULER complètement (event neutralisé)', i: <CheckCircle className="h-4 w-4 text-emerald-600" /> },
          ].map(opt => (
            <label key={opt.v} className="flex items-center gap-2 cursor-pointer p-2 rounded hover:bg-muted">
              <input type="radio" checked={decision === opt.v} onChange={() => setDecision(opt.v as any)} />
              {opt.i}
              <span className="text-sm">{opt.l}</span>
            </label>
          ))}
        </div>

        {decision === 'REDUIRE' && (
          <label className="block">
            <span className="text-xs font-medium mb-1 block">Points corrigés (négatif, ex: -5)</span>
            <input type="number" max="-1" value={pointsCorriges} onChange={e => setPointsCorriges(e.target.value)} className="input-base" />
            <span className="text-[10px] text-muted-foreground">Original : {reclamation.event_points} pts</span>
          </label>
        )}

        <label className="block">
          <span className="text-xs font-medium mb-1 block">Motif admin * (min 10 chars, visible par l'user)</span>
          <textarea value={motifAdmin} onChange={e => setMotifAdmin(e.target.value)} className="input-base" rows={3}
            placeholder="Ex: Certif médical fourni est conforme, justification valide..." />
        </label>

        <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs flex gap-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <p>La décision sera <strong>propagée automatiquement</strong> sur l'événement score, le score sera recalculé, et l'utilisateur recevra notification email + push.</p>
        </div>

        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">Annuler</button>
          <button onClick={soumettre} disabled={loading} className="btn-primary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Appliquer la décision
          </button>
        </div>
      </div>
    </div>
  );
}

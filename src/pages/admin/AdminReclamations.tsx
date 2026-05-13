import React, { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { extraireMessageErreur } from '@/lib/erreurs';
import { CheckCircle, XCircle, Download, FileText, Loader2, MessageCircle, Clock, Send } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Button } from '@/components/ui/button';

const TABS = [
  { id: 'generales', label: 'Réclamations générales' },
  { id: 'scoring', label: 'Contestations scoring' },
] as const;

const STATUT_OPTIONS = [
  { value: 'EN_COURS', label: 'En cours' },
  { value: 'RESOLUE', label: 'Résolue' },
  { value: 'FERMEE', label: 'Fermée' },
];

export default function AdminReclamations() {
  usePageTitle('Réclamations');
  const { afficherNotification } = useNotification();
  const [tab, setTab] = useState<'generales' | 'scoring'>('generales');

  // Scoring state
  const [reclamationsScoring, setReclamationsScoring] = useState<any[]>([]);
  const [loadingScoring, setLoadingScoring] = useState(true);
  const [traitement, setTraitement] = useState<string | null>(null);
  const [pointsInput, setPointsInput] = useState<Record<string, number>>({});

  // General state
  const [reclamationsGenerales, setReclamationsGenerales] = useState<any[]>([]);
  const [loadingGenerales, setLoadingGenerales] = useState(true);
  const [reponseInput, setReponseInput] = useState<Record<string, string>>({});
  const [statutInput, setStatutInput] = useState<Record<string, string>>({});
  const [traitementGen, setTraitementGen] = useState<string | null>(null);

  /* ── Load scoring ── */
  const chargerScoring = async () => {
    setLoadingScoring(true);
    const { data } = await supabase
      .from('reclamations_scoring')
      .select('*')
      .order('cree_le', { ascending: false })
      .limit(100);

    if (data && data.length > 0) {
      const soignantIds = [...new Set((data as any[]).map(r => r.soignant_id))];
      const { data: soignants } = await supabase
        .from('soignants')
        .select('id, prenom, nom, score_fiabilite')
        .in('id', soignantIds);

      setReclamationsScoring((data as any[]).map(r => ({
        ...r,
        soignant: soignants?.find(s => s.id === r.soignant_id) || null,
      })));
    } else {
      setReclamationsScoring([]);
    }
    setLoadingScoring(false);
  };

  /* ── Load generales ── */
  const chargerGenerales = async () => {
    setLoadingGenerales(true);
    const { data } = await supabase
      .from('reclamations' as any)
      .select('*')
      .order('cree_le', { ascending: false })
      .limit(100);

    if (data && (data as any[]).length > 0) {
      // Enrich with user names
      const userIds = [...new Set((data as any[]).map((r: any) => r.utilisateur_id))];
      const [{ data: soignants }, { data: etabs }] = await Promise.all([
        supabase.from('soignants').select('id, prenom, nom').in('id', userIds),
        supabase.from('etablissements').select('id, nom').in('id', userIds),
      ]);

      setReclamationsGenerales((data as any[]).map((r: any) => {
        const sg = soignants?.find(s => s.id === r.utilisateur_id);
        const et = etabs?.find(e => e.id === r.utilisateur_id);
        return {
          ...r,
          nom_utilisateur: sg ? `${sg.prenom} ${sg.nom}` : et?.nom || 'Inconnu',
        };
      }));
    } else {
      setReclamationsGenerales([]);
    }
    setLoadingGenerales(false);
  };

  useEffect(() => { chargerScoring(); chargerGenerales(); }, []);

  /* ── Traiter scoring ── */
  const traiterScoring = async (id: string, decision: 'ACCEPTEE' | 'REFUSEE') => {
    setTraitement(id);
    const points = decision === 'ACCEPTEE' ? (pointsInput[id] || 10) : 0;

    const { data, error } = await supabase.rpc('fn_traiter_reclamation' as any, {
      p_reclamation_id: id,
      p_statut: decision,
      p_points_restaures: points,
    });

    if (error) {
      afficherNotification({ type: 'erreur', message: extraireMessageErreur(error) });
    } else if (data && typeof data === 'object' && (data as any).success === false) {
      afficherNotification({ type: 'erreur', message: (data as any).error || 'Erreur' });
    } else {
      afficherNotification({ type: 'succes', message: decision === 'ACCEPTEE' ? `Acceptée, +${points} pts` : 'Refusée.' });
      await chargerScoring();
    }
    setTraitement(null);
  };

  /* ── Traiter generale ── */
  const traiterGenerale = async (id: string) => {
    setTraitementGen(id);
    const statut = statutInput[id] || 'RESOLUE';
    const reponse = reponseInput[id]?.trim() || null;

    const { data, error } = await supabase.rpc('fn_traiter_reclamation_generale' as any, {
      p_reclamation_id: id,
      p_statut: statut,
      p_reponse: reponse,
    });

    if (error || (data as any)?.error) {
      afficherNotification({ type: 'erreur', message: (data as any)?.error || extraireMessageErreur(error!) });
    } else {
      afficherNotification({ type: 'succes', message: 'Réclamation traitée' });
      await chargerGenerales();
    }
    setTraitementGen(null);
  };

  const telechargerJustificatif = async (cle: string, nom: string) => {
    const win = window.open('', '_blank');
    const { data } = await supabase.storage.from('jolene-documents').createSignedUrl(cle, 300);
    if (data?.signedUrl && win) win.location.href = data.signedUrl;
  };

  const loading = tab === 'scoring' ? loadingScoring : loadingGenerales;

  return (
    <LayoutAdmin>
      <h1 className="text-xl font-bold text-foreground mb-4">Réclamations</h1>

      {/* Tabs */}
      <div className="flex gap-1 mb-6 bg-muted/50 rounded-xl p-1 w-fit">
        {TABS.map(t => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${tab === t.id ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
          >
            {t.label}
            {t.id === 'generales' && reclamationsGenerales.filter(r => r.statut === 'EN_ATTENTE').length > 0 && (
              <span className="ml-1.5 inline-flex items-center justify-center h-5 min-w-5 px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-bold">
                {reclamationsGenerales.filter(r => r.statut === 'EN_ATTENTE').length}
              </span>
            )}
            {t.id === 'scoring' && reclamationsScoring.filter(r => r.statut === 'EN_ATTENTE').length > 0 && (
              <span className="ml-1.5 inline-flex items-center justify-center h-5 min-w-5 px-1 rounded-full bg-warning text-warning-foreground text-[10px] font-bold">
                {reclamationsScoring.filter(r => r.statut === 'EN_ATTENTE').length}
              </span>
            )}
          </button>
        ))}
      </div>

      {loading && <ChargementPage />}

      {/* ═══ TAB: Générales ═══ */}
      {!loading && tab === 'generales' && (
        <div className="space-y-4">
          {reclamationsGenerales.length === 0 ? (
            <p className="text-center py-12 text-muted-foreground">Aucune réclamation générale.</p>
          ) : (
            <>
              {reclamationsGenerales.filter(r => r.statut === 'EN_ATTENTE' || r.statut === 'EN_COURS').map(r => (
                <div key={r.id} className="card-base border-l-4 border-primary space-y-3">
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="font-semibold text-foreground">{r.nom_utilisateur}</p>
                      <p className="text-xs text-muted-foreground">
                        {r.type_utilisateur === 'SOIGNANT' ? '🩺 Soignant' : '🏥 Établissement'} · {r.categorie} · {format(new Date(r.cree_le), 'd MMM yyyy HH:mm', { locale: fr })}
                      </p>
                    </div>
                    <span className={`badge-base text-xs ${r.statut === 'EN_ATTENTE' ? 'bg-warning/10 text-warning' : 'bg-primary/10 text-primary'}`}>
                      {r.statut === 'EN_ATTENTE' ? 'En attente' : 'En cours'}
                    </span>
                  </div>
                  <p className="text-sm font-medium text-foreground">{r.sujet}</p>
                  <p className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-3">{r.details}</p>

                  <div className="space-y-2 pt-2">
                    <textarea
                      placeholder="Réponse à l'utilisateur (optionnelle)"
                      value={reponseInput[r.id] || ''}
                      onChange={e => setReponseInput(prev => ({ ...prev, [r.id]: e.target.value }))}
                      rows={2}
                      className="input-base w-full text-sm resize-none"
                    />
                    <div className="flex items-center gap-2">
                      <select
                        value={statutInput[r.id] || 'RESOLUE'}
                        onChange={e => setStatutInput(prev => ({ ...prev, [r.id]: e.target.value }))}
                        className="input-base text-sm"
                      >
                        {STATUT_OPTIONS.map(s => (
                          <option key={s.value} value={s.value}>{s.label}</option>
                        ))}
                      </select>
                      <div className="flex-1" />
                      <Button
                        size="sm"
                        onClick={() => traiterGenerale(r.id)}
                        disabled={traitementGen === r.id}
                        className="gap-1"
                      >
                        {traitementGen === r.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Send className="h-3.5 w-3.5" />}
                        Traiter
                      </Button>
                    </div>
                  </div>
                </div>
              ))}

              {reclamationsGenerales.filter(r => r.statut === 'RESOLUE' || r.statut === 'FERMEE').length > 0 && (
                <div className="space-y-2 mt-6">
                  <h2 className="text-base font-semibold text-muted-foreground">
                    Traitées ({reclamationsGenerales.filter(r => r.statut === 'RESOLUE' || r.statut === 'FERMEE').length})
                  </h2>
                  {reclamationsGenerales.filter(r => r.statut === 'RESOLUE' || r.statut === 'FERMEE').map(r => (
                    <div key={r.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
                      <div>
                        <span className="text-sm text-foreground">{r.nom_utilisateur}</span>
                        <span className="text-xs text-muted-foreground ml-2">{r.sujet}</span>
                      </div>
                      <span className={`badge-base text-[10px] ${r.statut === 'RESOLUE' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>
                        {r.statut === 'RESOLUE' ? '✅ Résolue' : '🔒 Fermée'}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* ═══ TAB: Scoring ═══ */}
      {!loading && tab === 'scoring' && (
        <div className="space-y-4">
          {/* Sprint 5.5 PR 11 : bandeau redirection workflow Sprint 3.5 */}
          <div className="rounded-xl bg-amber-50 dark:bg-amber-950/30 border-2 border-amber-300 dark:border-amber-800 p-4 text-sm text-amber-900 dark:text-amber-200">
            <p className="font-semibold mb-1">⚠️ Contestations scoring legacy</p>
            <p className="text-xs mb-2">
              Cette table <code>reclamations_scoring</code> contient des contestations créées avant Sprint 3.5.
              Le nouveau workflow MAINTENIR / RÉDUIRE / ANNULER se trouve dans la page dédiée Sprint 3.5.
            </p>
            <a
              href="/admin/reclamations-score"
              className="inline-flex items-center gap-1 text-amber-900 dark:text-amber-200 underline font-medium"
            >
              → Aller à /admin/reclamations-score (workflow Sprint 3.5)
            </a>
          </div>

          {reclamationsScoring.length === 0 ? (
            <p className="text-center py-12 text-muted-foreground">Aucune contestation scoring legacy.</p>
          ) : (
            <>
              {reclamationsScoring.filter(r => r.statut === 'EN_ATTENTE').map(r => (
                <div key={r.id} className="card-base border-l-4 border-warning space-y-3">
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="font-semibold text-foreground">
                        {r.soignant?.prenom} {r.soignant?.nom}
                        <span className="ml-2 text-xs text-muted-foreground">Score: {r.soignant?.score_fiabilite}/100</span>
                      </p>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {format(new Date(r.cree_le), 'd MMM yyyy HH:mm', { locale: fr })}
                      </p>
                    </div>
                    <span className="badge-base bg-warning/10 text-warning text-xs">{r.motif}</span>
                  </div>
                  {r.details && <p className="text-sm text-foreground bg-muted/50 rounded-lg p-3">{r.details}</p>}
                  {r.justificatif_s3_cle && (
                    <button
                      onClick={() => telechargerJustificatif(r.justificatif_s3_cle, r.justificatif_nom_fichier)}
                      className="flex items-center gap-2 text-sm text-primary hover:underline"
                    >
                      <FileText className="h-4 w-4" />
                      {r.justificatif_nom_fichier || 'Télécharger le justificatif'}
                    </button>
                  )}
                  <div className="flex items-center gap-3 pt-2">
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-muted-foreground">Points :</label>
                      <input
                        type="number"
                        min={1}
                        max={30}
                        value={pointsInput[r.id] || 10}
                        onChange={e => setPointsInput(prev => ({ ...prev, [r.id]: Number(e.target.value) }))}
                        className="input-base w-20 text-sm"
                      />
                    </div>
                    <div className="flex-1" />
                    <button
                      onClick={() => traiterScoring(r.id, 'ACCEPTEE')}
                      disabled={traitement === r.id}
                      className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                    >
                      {traitement === r.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle className="h-3.5 w-3.5" />}
                      Accepter (+{pointsInput[r.id] || 10} pts)
                    </button>
                    <button
                      onClick={() => traiterScoring(r.id, 'REFUSEE')}
                      disabled={traitement === r.id}
                      className="btn-danger text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                    >
                      <XCircle className="h-3.5 w-3.5" /> Refuser
                    </button>
                  </div>
                </div>
              ))}

              {reclamationsScoring.filter(r => r.statut !== 'EN_ATTENTE').length > 0 && (
                <div className="space-y-2 mt-6">
                  <h2 className="text-base font-semibold text-muted-foreground">
                    Traitées ({reclamationsScoring.filter(r => r.statut !== 'EN_ATTENTE').length})
                  </h2>
                  {reclamationsScoring.filter(r => r.statut !== 'EN_ATTENTE').map(r => (
                    <div key={r.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
                      <div>
                        <span className="text-sm text-foreground">{r.soignant?.prenom} {r.soignant?.nom}</span>
                        <span className="text-xs text-muted-foreground ml-2">{r.motif}</span>
                      </div>
                      <span className={`badge-base text-[10px] ${r.statut === 'ACCEPTEE' ? 'bg-success/10 text-success' : 'bg-destructive/10 text-destructive'}`}>
                        {r.statut === 'ACCEPTEE' ? `✅ +${r.points_accordes} pts` : '❌ Refusée'}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      )}
    </LayoutAdmin>
  );
}

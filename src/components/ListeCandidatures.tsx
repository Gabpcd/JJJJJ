import React, { useState, useEffect } from 'react';
import { CheckCircle, XCircle, Clock, Send, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';

function scoreBadge(score: number) {
  if (score >= 70) return 'bg-success/10 text-success';
  if (score >= 40) return 'bg-warning/10 text-warning';
  return 'bg-destructive/10 text-destructive';
}

interface ListeCandidaturesProps {
  missionId: string;
  onAccepted: () => void;
  onError: (msg: string) => void;
  onSuccess: (msg: string) => void;
}

export function ListeCandidatures({ missionId, onAccepted, onError, onSuccess }: ListeCandidaturesProps) {
  const [candidatures, setCandidatures] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [traitement, setTraitement] = useState<string | null>(null);

  useEffect(() => {
    charger();
  }, [missionId]);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('candidatures')
      .select('id, soignant_id, message, statut, cree_le')
      .eq('mission_id', missionId)
      .order('cree_le', { ascending: true });

    if (data && data.length > 0) {
      // Enrich with soignant info
      const enriched = await Promise.all(
        data.map(async (c: any) => {
          const { data: sg } = await supabase.rpc('fn_soignant_pour_etablissement' as any, { p_soignant_id: c.soignant_id });
          return { ...c, soignant: sg || null };
        })
      );
      setCandidatures(enriched);
    } else {
      setCandidatures([]);
    }
    setLoading(false);
  };

  const traiterCandidature = async (candidatureId: string, decision: 'ACCEPTEE' | 'REFUSEE') => {
    setTraitement(candidatureId);
    try {
      const { data, error } = await supabase.rpc('fn_traiter_candidature' as any, {
        p_candidature_id: candidatureId,
        p_decision: decision,
        p_motif: decision === 'REFUSEE' ? 'Refusé par l\'établissement' : null,
      });
      if (error) throw error;
      if (data?.error) { onError(data.error); return; }
      onSuccess(decision === 'ACCEPTEE' ? 'Candidature acceptée ! Le soignant est assigné.' : 'Candidature refusée.');
      if (decision === 'ACCEPTEE') onAccepted();
      await charger();
    } catch (err: any) {
      onError(extraireMessageErreur(err));
    }
    setTraitement(null);
  };

  if (loading) return <p className="text-sm text-muted-foreground text-center py-6">Chargement des candidatures…</p>;

  if (candidatures.length === 0) {
    return (
      <div className="text-center py-8">
        <Clock className="h-10 w-10 text-muted-foreground/30 mx-auto mb-2" />
        <p className="text-sm text-muted-foreground">Aucune candidature pour le moment</p>
        <p className="text-xs text-muted-foreground/60 mt-1">Les soignants qualifiés peuvent postuler à cette mission.</p>
      </div>
    );
  }

  const enAttente = candidatures.filter(c => c.statut === 'EN_ATTENTE');
  const traitees = candidatures.filter(c => c.statut !== 'EN_ATTENTE');

  return (
    <div className="space-y-4">
      {enAttente.length > 0 && (
        <div className="space-y-3">
          <p className="text-sm font-semibold text-foreground">En attente ({enAttente.length})</p>
          {enAttente.map((c: any) => (
            <div key={c.id} className="card-base border-primary/20">
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm text-foreground">
                    👤 {c.soignant?.prenom} {c.soignant?.nom}
                  </p>
                  {c.soignant?.bio && (
                    <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{c.soignant.bio}</p>
                  )}
                  <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                    <span className={`badge-base text-[10px] ${scoreBadge(c.soignant?.score_fiabilite || 0)}`}>
                      ⭐ {c.soignant?.score_fiabilite || 0}/100
                    </span>
                    {c.soignant?.annees_experience > 0 && (
                      <span className="text-[10px] text-muted-foreground">{c.soignant.annees_experience} ans d'exp.</span>
                    )}
                    {c.soignant?.specialites && (
                      <span className="text-[10px] text-muted-foreground">{
                        (Array.isArray(c.soignant.specialites) ? c.soignant.specialites : []).slice(0, 3).join(', ')
                      }</span>
                    )}
                  </div>
                  {c.message && (
                    <div className="mt-2 bg-muted/50 rounded-lg p-2">
                      <p className="text-xs text-muted-foreground italic">"{c.message}"</p>
                    </div>
                  )}
                </div>
                <div className="flex gap-1.5 shrink-0">
                  <button
                    onClick={() => traiterCandidature(c.id, 'ACCEPTEE')}
                    disabled={traitement === c.id}
                    className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                  >
                    <CheckCircle className="h-3.5 w-3.5" />
                    Accepter
                  </button>
                  <button
                    onClick={() => traiterCandidature(c.id, 'REFUSEE')}
                    disabled={traitement === c.id}
                    className="btn-danger text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50"
                  >
                    <XCircle className="h-3.5 w-3.5" />
                    Refuser
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {traitees.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-semibold text-muted-foreground">Traitées ({traitees.length})</p>
          {traitees.map((c: any) => (
            <div key={c.id} className="flex items-center justify-between p-3 bg-muted/30 rounded-xl">
              <span className="text-sm text-muted-foreground">
                {c.soignant?.prenom} {c.soignant?.nom}
              </span>
              <span className={`badge-base text-[10px] ${c.statut === 'ACCEPTEE' ? 'bg-success/10 text-success' : 'bg-destructive/10 text-destructive'}`}>
                {c.statut === 'ACCEPTEE' ? '✅ Acceptée' : '❌ Refusée'}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

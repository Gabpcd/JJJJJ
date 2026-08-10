import React, { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Flame, CheckCircle2, XCircle, Loader2, ArrowRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { getLabelProfession } from '@/lib/constantes';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

interface CandidatureUrgence {
  id: string;
  cree_le: string;
  mission_id: string;
  mission_intitule: string;
  mission_debut_le: string;
  soignant_id: string;
  soignant_prenom: string;
  soignant_nom_initiale: string;
  soignant_profession: string;
  soignant_score: number | null;
  soignant_distance_km: number | null;
}

export function BannerCandidaturesPoolUrgence({ etablissementId }: { etablissementId: string }) {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<CandidatureUrgence[]>([]);
  const [processing, setProcessing] = useState<string | null>(null);
  const [decision, setDecision] = useState<{ candidature: CandidatureUrgence; action: 'VALIDER' | 'REFUSER' } | null>(null);
  const [motifRefus, setMotifRefus] = useState('');

  const charger = useCallback(async () => {
    if (!etablissementId) return;
    setLoading(true);
    const { data, error } = await supabase
      .from('candidatures')
      .select(`
        id, cree_le, mission_id, soignant_id,
        missions!inner ( id, intitule, debut_le, etablissement_id ),
        soignants!inner ( id, prenom, nom, profession, score_fiabilite, total_missions_terminees )
      `)
      .eq('statut', 'EN_ATTENTE_VALIDATION_ETAB')
      .eq('missions.etablissement_id', etablissementId)
      .order('cree_le', { ascending: true })
      .limit(10);

    if (error) {
      setLoading(false);
      return;
    }

    const list: CandidatureUrgence[] = (data ?? []).map((c: any) => ({
      id: c.id,
      cree_le: c.cree_le,
      mission_id: c.mission_id,
      mission_intitule: c.missions?.intitule ?? 'Mission',
      mission_debut_le: c.missions?.debut_le,
      soignant_id: c.soignant_id,
      soignant_prenom: c.soignants?.prenom ?? '',
      soignant_nom_initiale: (c.soignants?.nom ?? '?').charAt(0) + '.',
      soignant_profession: c.soignants?.profession ?? '',
      soignant_score: c.soignants?.total_missions_terminees >= 3 ? c.soignants?.score_fiabilite : null,
      soignant_distance_km: null,
    }));
    setItems(list);
    setLoading(false);
  }, [etablissementId]);

  useEffect(() => { void charger(); }, [charger]);

  const executerDecision = async () => {
    if (!decision) return;
    const { candidature: cand, action } = decision;
    if (action === 'REFUSER' && motifRefus.trim().length < 5) {
      toast.error('Précisez le motif du refus (5 caractères minimum).');
      return;
    }
    setProcessing(cand.id);
    const { data, error } = await supabase.rpc('fn_etab_valider_acceptation_urgence' as any, {
      p_candidature_id: cand.id,
      p_action: action,
      ...(action === 'REFUSER' ? { p_motif_refus: motifRefus.trim() } : {}),
    });
    setProcessing(null);
    if (error) { toast.error(error.message); return; }
    const r = data as any;
    if (r?.success) {
      toast.success(action === 'VALIDER' ? `Mission assignée à ${cand.soignant_prenom}` : 'Acceptation refusée');
      setDecision(null);
      setMotifRefus('');
      void charger();
    } else {
      toast.error(r?.error ?? 'Erreur');
    }
  };

  if (loading || items.length === 0) return null;

  return (
    <div className="card-base border-l-4 border-l-destructive bg-destructive/5 mb-4">
      <div className="flex items-start gap-3 mb-3">
        <Flame className="h-5 w-5 text-destructive flex-shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <h2 className="font-semibold text-foreground">
            {items.length} acceptation{items.length > 1 ? 's' : ''} pool urgence en attente
          </h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            Validez ou refusez sous 1h pour libérer la mission.
          </p>
        </div>
      </div>

      <div className="space-y-2">
        {items.map((c) => (
          <div key={c.id} className="rounded-xl border border-border bg-card p-3">
            <div className="flex items-start justify-between gap-3 mb-2">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-foreground">
                  {c.soignant_prenom} {c.soignant_nom_initiale}
                  <span className="text-xs text-muted-foreground ml-2">{getLabelProfession(c.soignant_profession)}</span>
                  {c.soignant_score != null && (
                    <span className="badge-base bg-primary/10 text-primary text-[10px] ml-2">{c.soignant_score}/100</span>
                  )}
                </p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Mission « {c.mission_intitule} » · {new Date(c.mission_debut_le).toLocaleString('fr-FR', { weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                </p>
              </div>
              <button
                onClick={() => navigate(`/etablissement/missions/${c.mission_id}`)}
                className="text-xs text-primary hover:underline inline-flex items-center gap-1"
              >
                Détail <ArrowRight className="h-3 w-3" />
              </button>
            </div>
            <div className="flex items-center gap-2 pt-2 border-t border-border">
              <button
                onClick={() => setDecision({ candidature: c, action: 'VALIDER' })}
                disabled={processing === c.id}
                className="btn-primary text-xs inline-flex items-center gap-1.5"
              >
                {processing === c.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle2 className="h-3.5 w-3.5" />}
                Valider
              </button>
              <button
                onClick={() => setDecision({ candidature: c, action: 'REFUSER' })}
                disabled={processing === c.id}
                className="btn-secondary text-xs inline-flex items-center gap-1.5"
              >
                <XCircle className="h-3.5 w-3.5" /> Refuser
              </button>
            </div>
          </div>
        ))}
      </div>

      <DialogResponsive open={Boolean(decision)} onOpenChange={(open) => { if (!open && !processing) setDecision(null); }}>
        <DialogResponsiveContent maxWidth="md">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>
              {decision?.action === 'VALIDER' ? 'Confirmer le remplacement' : 'Refuser cette acceptation'}
            </DialogResponsiveTitle>
          </DialogResponsiveHeader>
          <DialogResponsiveBody className="space-y-3">
            {decision && (
              <div className="rounded-lg bg-muted/40 p-3 text-sm">
                <p className="font-semibold text-foreground">{decision.candidature.soignant_prenom} {decision.candidature.soignant_nom_initiale}</p>
                <p className="text-xs text-muted-foreground mt-1">Mission « {decision.candidature.mission_intitule} »</p>
              </div>
            )}
            {decision?.action === 'VALIDER' ? (
              <p className="text-sm text-muted-foreground">La mission sera assignée immédiatement et les autres candidatures d'urgence seront libérées.</p>
            ) : (
              <label className="block">
                <span className="text-sm font-medium text-foreground">Motif visible par le soignant *</span>
                <textarea
                  value={motifRefus}
                  onChange={(event) => setMotifRefus(event.target.value)}
                  rows={3}
                  maxLength={500}
                  className="input-base mt-1"
                  placeholder="Expliquez brièvement votre décision"
                />
              </label>
            )}
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <button type="button" className="btn-secondary" disabled={Boolean(processing)} onClick={() => setDecision(null)}>Retour</button>
            <button
              type="button"
              className="btn-primary inline-flex items-center justify-center gap-2"
              disabled={Boolean(processing) || (decision?.action === 'REFUSER' && motifRefus.trim().length < 5)}
              onClick={() => void executerDecision()}
            >
              {processing && <Loader2 className="h-4 w-4 animate-spin" />}
              {decision?.action === 'VALIDER' ? 'Assigner le soignant' : 'Confirmer le refus'}
            </button>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>
    </div>
  );
}

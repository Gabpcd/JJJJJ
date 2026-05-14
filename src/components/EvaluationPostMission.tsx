import { useEffect, useState } from 'react';
import { Star, Send } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { toast } from 'sonner';
import {
  DialogResponsive,
  DialogResponsiveHeader,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

interface Props {
  missionId: string;
  evalueId: string;
  typeEvaluateur: 'SOIGNANT' | 'ETABLISSEMENT';
  nomEvalue: string;
  onTermine: () => void;
}

const CRITERES_ETABLISSEMENT = ['Ponctualité', 'Compétence', 'Attitude'];

/**
 * Modale d'évaluation post-mission.
 *
 * - Si typeEvaluateur = ETABLISSEMENT : un étab évalue un soignant
 *   (critères affichés : Ponctualité / Compétence / Attitude).
 * - Si typeEvaluateur = SOIGNANT : un soignant évalue un établissement.
 *
 * Pré-check via .eq('mission_id') + .eq('type_evaluateur') pour éviter la
 * faille où le modal réouvrait à chaque visite côté admin de groupe.
 *
 * Sprint 8 ter-E : migré vers <DialogResponsive /> (fullscreen mobile / centered desktop maxWidth=md).
 * createPortal supprimé — DialogResponsive utilise déjà Radix Portal en interne.
 * Étoiles + bouton envoyer min-h-[44px] pour touch targets mobile.
 */
export function EvaluationPostMission({ missionId, evalueId: _evalueId, typeEvaluateur, nomEvalue, onTermine }: Props) {
  const { user } = useAuth();
  const [note, setNote] = useState(0);
  const [hoverNote, setHoverNote] = useState(0);
  const [commentaire, setCommentaire] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [dejaEvalue, setDejaEvalue] = useState<boolean | null>(null);

  useEffect(() => {
    if (!user) return;
    // Filtre sur mission_id + type_evaluateur : RLS isole les évaluations
    // accessibles (les siennes côté soignant, celles de son étab côté admin).
    // Évite la faille : fn_evaluer_soignant stocke evaluateur_id = etablissement_id
    // (pas auth.uid()), donc .eq('evaluateur_id', user.id) ne matche jamais pour
    // les admins de groupe_sante → le modal rouvrait à chaque visite.
    supabase
      .from('evaluations')
      .select('id')
      .eq('mission_id', missionId)
      .eq('type_evaluateur', typeEvaluateur)
      .limit(1)
      .maybeSingle()
      .then(({ data }) => setDejaEvalue(!!data));
  }, [missionId, user, typeEvaluateur]);

  if (dejaEvalue === null || dejaEvalue) return null;

  const soumettre = async () => {
    if (!user || note === 0) return;
    setEnvoi(true);
    try {
      // Use the appropriate RPC based on evaluator type
      const rpcName = typeEvaluateur === 'ETABLISSEMENT' ? 'fn_evaluer_soignant' : 'fn_evaluer_etablissement';
      const { data, error } = await supabase.rpc(rpcName as any, {
        p_mission_id: missionId,
        p_note: note,
        p_commentaire: commentaire.trim() ? sanitizeText(commentaire.trim()) : null,
      });
      if (error) throw error;
      if (data && typeof data === 'object' && (data as any).error) {
        toast.error((data as any).error);
        setEnvoi(false);
        return;
      }
      toast.success('Merci pour votre évaluation !');
      onTermine();
    } catch (err: any) {
      const msg = err?.message || err?.details || "Erreur lors de l'envoi de l'évaluation";
      toast.error(msg);
    } finally {
      setEnvoi(false);
    }
  };

  const isSoignant = typeEvaluateur === 'SOIGNANT';
  const description = isSoignant
    ? `Évaluez l'établissement « ${nomEvalue} »`
    : `Évaluez le soignant « ${nomEvalue} »`;

  return (
    <DialogResponsive
      open={true}
      onOpenChange={(o) => { if (!o && !envoi) onTermine(); }}
      maxWidth="md"
    >
      <DialogResponsiveHeader
        title="Mission terminée 🎉"
        description={description}
      />
      <DialogResponsiveBody>
        <div className="mb-4 flex items-center justify-center gap-1">
          {[1, 2, 3, 4, 5].map((v) => (
            <button
              key={v}
              type="button"
              onMouseEnter={() => setHoverNote(v)}
              onMouseLeave={() => setHoverNote(0)}
              onClick={() => setNote(v)}
              className="flex min-h-[44px] min-w-[44px] items-center justify-center transition-transform hover:scale-110"
              aria-label={`Note ${v} étoile${v > 1 ? 's' : ''}`}
            >
              <Star
                className={`h-8 w-8 transition-colors ${
                  v <= (hoverNote || note) ? 'fill-amber-400 text-amber-400' : 'text-muted-foreground/30'
                }`}
              />
            </button>
          ))}
        </div>

        {note > 0 && (
          <p className="mb-4 text-center text-sm font-medium text-foreground">
            {note === 1 && 'Insuffisant'}
            {note === 2 && 'Passable'}
            {note === 3 && 'Correct'}
            {note === 4 && 'Bien'}
            {note === 5 && 'Excellent'}
          </p>
        )}

        {!isSoignant && (
          <div className="mb-4 flex flex-wrap justify-center gap-2">
            {CRITERES_ETABLISSEMENT.map((c) => (
              <span key={c} className="rounded-full bg-muted px-3 py-1 text-xs text-muted-foreground">
                {c}
              </span>
            ))}
          </div>
        )}

        <textarea
          value={commentaire}
          onChange={(e) => setCommentaire(e.target.value.slice(0, 500))}
          placeholder={isSoignant ? 'Un commentaire ? (optionnel)' : 'Ponctualité, compétence, attitude… (optionnel)'}
          rows={3}
          className="mb-1 w-full resize-none rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/50"
        />
        <p className="text-right text-xs text-muted-foreground">{commentaire.length}/500</p>
      </DialogResponsiveBody>
      <DialogResponsiveFooter>
        <button
          onClick={soumettre}
          disabled={note === 0 || envoi}
          className="flex min-h-[44px] w-full items-center justify-center gap-2 rounded-lg bg-primary py-2.5 text-sm font-semibold text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          <Send className="h-4 w-4" />
          {envoi ? 'Envoi…' : 'Envoyer mon évaluation'}
        </button>
      </DialogResponsiveFooter>
    </DialogResponsive>
  );
}

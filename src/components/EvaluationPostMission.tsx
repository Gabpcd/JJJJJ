import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { Star, Send, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { toast } from 'sonner';

interface Props {
  missionId: string;
  evalueId: string;
  typeEvaluateur: 'SOIGNANT' | 'ETABLISSEMENT';
  nomEvalue: string;
  onTermine: () => void;
}

const CRITERES_ETABLISSEMENT = ['Ponctualité', 'Compétence', 'Attitude'];

export function EvaluationPostMission({ missionId, evalueId, typeEvaluateur, nomEvalue, onTermine }: Props) {
  const { user } = useAuth();
  const [note, setNote] = useState(0);
  const [hoverNote, setHoverNote] = useState(0);
  const [commentaire, setCommentaire] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [dejaEvalue, setDejaEvalue] = useState<boolean | null>(null);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('evaluations')
      .select('id')
      .eq('mission_id', missionId)
      .eq('evaluateur_id', user.id)
      .maybeSingle()
      .then(({ data }) => setDejaEvalue(!!data));
  }, [missionId, user]);

  if (dejaEvalue === null || dejaEvalue) return null;

  const soumettre = async () => {
    if (!user || note === 0) return;
    setEnvoi(true);
    try {
      const { error } = await supabase.from('evaluations').insert({
        mission_id: missionId,
        evaluateur_id: user.id,
        evalue_id: evalueId,
        type_evaluateur: typeEvaluateur,
        note,
        commentaire: commentaire.trim() ? sanitizeText(commentaire.trim()) : null,
        visible: false,
      });
      if (error) throw error;
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
  const titre = isSoignant
    ? `Évaluez l'établissement « ${nomEvalue} »`
    : `Évaluez le soignant « ${nomEvalue} »`;

  const modal = (
    <div className="fixed inset-0 z-[100] flex min-h-screen items-center justify-center bg-black/50 p-4">
      <div className="relative w-full max-w-md rounded-2xl bg-card p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-200">
        <button
          onClick={onTermine}
          className="absolute right-4 top-4 text-muted-foreground transition-colors hover:text-foreground"
          aria-label="Fermer"
        >
          <X className="h-5 w-5" />
        </button>

        <h2 className="mb-1 text-lg font-bold text-foreground">Mission terminée 🎉</h2>
        <p className="mb-5 text-sm text-muted-foreground">{titre}</p>

        <div className="mb-4 flex items-center justify-center gap-1">
          {[1, 2, 3, 4, 5].map((v) => (
            <button
              key={v}
              type="button"
              onMouseEnter={() => setHoverNote(v)}
              onMouseLeave={() => setHoverNote(0)}
              onClick={() => setNote(v)}
              className="transition-transform hover:scale-110"
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
        <p className="mb-4 text-right text-xs text-muted-foreground">{commentaire.length}/500</p>

        <button
          onClick={soumettre}
          disabled={note === 0 || envoi}
          className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary py-2.5 text-sm font-semibold text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          <Send className="h-4 w-4" />
          {envoi ? 'Envoi…' : 'Envoyer mon évaluation'}
        </button>
      </div>
    </div>
  );

  return typeof document !== 'undefined' ? createPortal(modal, document.body) : modal;
}

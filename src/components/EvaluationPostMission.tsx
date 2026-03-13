import React, { useState, useEffect } from 'react';
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

  if (dejaEvalue === null) return null;
  if (dejaEvalue) return null;

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
    } catch {
      toast.error("Erreur lors de l'envoi de l'évaluation");
    } finally {
      setEnvoi(false);
    }
  };

  const isSoignant = typeEvaluateur === 'SOIGNANT';
  const titre = isSoignant
    ? `Évaluez l'établissement « ${nomEvalue} »`
    : `Évaluez le soignant « ${nomEvalue} »`;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-2xl shadow-2xl w-full max-w-md p-6 relative animate-in fade-in zoom-in-95 duration-200">
        <button
          onClick={onTermine}
          className="absolute top-4 right-4 text-muted-foreground hover:text-foreground transition-colors"
          aria-label="Fermer"
        >
          <X className="h-5 w-5" />
        </button>

        <h2 className="text-lg font-bold text-foreground mb-1">Mission terminée 🎉</h2>
        <p className="text-sm text-muted-foreground mb-5">{titre}</p>

        {/* Étoiles */}
        <div className="flex items-center gap-1 justify-center mb-4">
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
                  v <= (hoverNote || note)
                    ? 'fill-amber-400 text-amber-400'
                    : 'text-muted-foreground/30'
                }`}
              />
            </button>
          ))}
        </div>
        {note > 0 && (
          <p className="text-center text-sm font-medium text-foreground mb-4">
            {note === 1 && 'Insuffisant'}
            {note === 2 && 'Passable'}
            {note === 3 && 'Correct'}
            {note === 4 && 'Bien'}
            {note === 5 && 'Excellent'}
          </p>
        )}

        {/* Critères pour évaluation soignant */}
        {!isSoignant && (
          <div className="flex flex-wrap gap-2 justify-center mb-4">
            {CRITERES_ETABLISSEMENT.map((c) => (
              <span key={c} className="text-xs px-3 py-1 rounded-full bg-muted text-muted-foreground">
                {c}
              </span>
            ))}
          </div>
        )}

        {/* Commentaire */}
        <textarea
          value={commentaire}
          onChange={(e) => setCommentaire(e.target.value.slice(0, 500))}
          placeholder={isSoignant ? 'Un commentaire ? (optionnel)' : 'Ponctualité, compétence, attitude… (optionnel)'}
          rows={3}
          className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/50 mb-1"
        />
        <p className="text-xs text-muted-foreground mb-4 text-right">{commentaire.length}/500</p>

        <button
          onClick={soumettre}
          disabled={note === 0 || envoi}
          className="w-full flex items-center justify-center gap-2 rounded-lg bg-primary text-primary-foreground py-2.5 text-sm font-semibold disabled:opacity-50 transition-opacity hover:opacity-90"
        >
          <Send className="h-4 w-4" />
          {envoi ? 'Envoi…' : 'Envoyer mon évaluation'}
        </button>
      </div>
    </div>
  );
}

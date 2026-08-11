import React, { useState } from 'react';
import { Star, Loader2, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { avecDelai } from '@/lib/avecDelai';
import { extraireMessageErreur } from '@/lib/erreurs';

interface Props {
  missionId: string;
  sens: 'ETAB_VERS_SOIGNANT' | 'SOIGNANT_VERS_ETAB';
  missionIntitule?: string;
  onClose: () => void;
  onSuccess?: () => void;
}

const CRITERES_ETAB_VERS_SOIGNANT = [
  { key: 'critere_1', label: 'Ponctualité', desc: 'Arrivée à l\'heure, respect des horaires' },
  { key: 'critere_2', label: 'Professionnalisme', desc: 'Tenue, comportement, savoir-être' },
  { key: 'critere_3', label: 'Qualité du soin', desc: 'Compétences techniques, attention au patient' },
  { key: 'critere_4', label: 'Communication', desc: 'Écoute, transmission, relation équipe' },
];

const CRITERES_SOIGNANT_VERS_ETAB = [
  { key: 'critere_1', label: 'Accueil', desc: 'Premier contact, bienveillance équipe' },
  { key: 'critere_2', label: 'Encadrement', desc: 'Soutien, présence, supervision' },
  { key: 'critere_3', label: 'Clarté des consignes', desc: 'Briefing, instructions, documentation' },
  { key: 'critere_4', label: 'Paiement à temps', desc: 'Respect des délais de paiement / facturation' },
];

const COMMENTAIRE_MAX = 2000;

function StarRating({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const [hover, setHover] = useState<number | null>(null);
  return (
    <div className="inline-flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((n) => {
        const active = (hover ?? value) >= n;
        return (
          <button
            key={n}
            type="button"
            onMouseEnter={() => setHover(n)}
            onMouseLeave={() => setHover(null)}
            onClick={() => onChange(n)}
            className="p-1 transition-transform hover:scale-110 focus:outline-none focus:ring-2 focus:ring-primary/40 rounded"
            aria-label={`Note ${n} étoile${n > 1 ? 's' : ''}`}
          >
            <Star className={`h-6 w-6 ${active ? 'text-amber-400 fill-amber-400' : 'text-muted-foreground/30'}`} />
          </button>
        );
      })}
    </div>
  );
}

export function ModalNoterMission({ missionId, sens, missionIntitule, onClose, onSuccess }: Props) {
  const criteres = sens === 'ETAB_VERS_SOIGNANT' ? CRITERES_ETAB_VERS_SOIGNANT : CRITERES_SOIGNANT_VERS_ETAB;
  const titreCible = sens === 'ETAB_VERS_SOIGNANT' ? 'le soignant' : 'l\'établissement';

  const [c1, setC1] = useState(0);
  const [c2, setC2] = useState(0);
  const [c3, setC3] = useState(0);
  const [c4, setC4] = useState(0);
  const [commentaire, setCommentaire] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const tousNotes = c1 > 0 && c2 > 0 && c3 > 0 && c4 > 0;
  const setters = [setC1, setC2, setC3, setC4];
  const valeurs = [c1, c2, c3, c4];

  const submit = async () => {
    if (!tousNotes) {
      toast.error('Notez les 4 critères avant d\'envoyer');
      return;
    }
    setSubmitting(true);
    try {
      const { data, error } = await avecDelai(
        supabase.rpc('fn_creer_notation_mission' as any, {
          p_mission_id: missionId,
          p_sens: sens,
          p_critere_1: c1, p_critere_2: c2, p_critere_3: c3, p_critere_4: c4,
          p_commentaire: commentaire.trim() || null,
        }),
        12_000,
        'L’envoi de la notation met trop de temps à répondre.',
      );
      if (error) throw error;
      const r = data as any;
      if (r?.success) {
        toast.success(r?.tardive ? 'Notation enregistrée (tardive)' : 'Notation enregistrée ✨');
        onSuccess?.();
        onClose();
      } else {
        toast.error(r?.error ?? 'Impossible d’enregistrer la notation.');
      }
    } catch (error) {
      toast.error(extraireMessageErreur(error));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-[80] bg-foreground/50 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-card rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-lg font-bold text-foreground">Noter {titreCible}</h2>
            {missionIntitule && (
              <p className="text-xs text-muted-foreground mt-0.5">Mission : {missionIntitule}</p>
            )}
          </div>
          <button onClick={onClose} aria-label="Fermer" className="p-1 hover:bg-muted rounded-lg">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="p-5 space-y-4">
          {criteres.map((c, idx) => (
            <div key={c.key} className="border-b border-border pb-3 last:border-0">
              <div className="flex items-start justify-between gap-3 mb-1">
                <div>
                  <p className="text-sm font-semibold text-foreground">{c.label}</p>
                  <p className="text-xs text-muted-foreground">{c.desc}</p>
                </div>
                <StarRating value={valeurs[idx]} onChange={setters[idx]} />
              </div>
            </div>
          ))}

          <div>
            <label className="text-sm font-medium text-foreground mb-1 block">
              Commentaire <span className="text-xs text-muted-foreground font-normal">(optionnel)</span>
            </label>
            <textarea
              value={commentaire}
              onChange={(e) => setCommentaire(e.target.value.slice(0, COMMENTAIRE_MAX))}
              rows={4}
              maxLength={COMMENTAIRE_MAX}
              placeholder="Partagez votre expérience…"
              className="w-full px-3 py-2 text-sm rounded-lg border border-border bg-background"
            />
            <div className="flex justify-end mt-1">
              <span className={`text-[10px] ${commentaire.length > COMMENTAIRE_MAX * 0.9 ? 'text-warning' : 'text-muted-foreground'}`}>
                {commentaire.length} / {COMMENTAIRE_MAX}
              </span>
            </div>
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 p-5 border-t border-border">
          <button onClick={onClose} className="btn-secondary text-sm" disabled={submitting}>
            Annuler
          </button>
          <button
            onClick={submit}
            disabled={!tousNotes || submitting}
            className="btn-primary text-sm inline-flex items-center gap-2"
          >
            {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Star className="h-4 w-4" />}
            {submitting ? 'Envoi…' : 'Envoyer la notation'}
          </button>
        </div>
      </div>
    </div>
  );
}

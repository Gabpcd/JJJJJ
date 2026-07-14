import { useMemo, useState } from 'react';
import { Loader2, Star, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

interface Props {
  mission: {
    mission_id: string;
    intitule: string;
    soignant_prenom: string;
    soignant_nom: string;
    soignant_profession: string;
    fin_le: string;
  };
  onFermer: () => void;
  onEvaluee?: () => void;
}

const CRITERES = [
  { key: 'critere_1', label: 'Ponctualité', description: 'Arrivée et départ aux horaires prévus' },
  { key: 'critere_2', label: 'Qualité technique', description: 'Compétences et professionnalisme' },
  { key: 'critere_3', label: 'Relationnel équipe', description: 'Communication avec patients et collègues' },
  { key: 'critere_4', label: 'Conformité protocole', description: 'Respect des consignes et procédures' },
] as const;

/**
 * Modale d'évaluation soignant côté étab (Sprint 5.7 PR 5).
 *
 * 4 critères 1-5 étoiles + commentaire optionnel.
 * Appelle fn_creer_notation_mission(mission_id, sens='ETAB_VERS_SOIGNANT', criteres, commentaire).
 *
 * Sprint 3.5 backend gère :
 *  - Calcul note globale (moyenne des 4 critères)
 *  - Propagation au score soignant (composante "notation étab" 35%)
 *  - Notification push + email au soignant
 *  - Audit trail
 *
 * Sprint 8 ter-F PR 4 — Migration vers DialogResponsive (fullscreen mobile).
 */
export function ModaleEvaluerSoignant({ mission, onFermer, onEvaluee }: Props) {
  const { afficherNotification } = useNotification();
  const [criteres, setCriteres] = useState<Record<string, number>>({});
  const [commentaire, setCommentaire] = useState('');
  const [loading, setLoading] = useState(false);

  const noteGlobale = useMemo(() => {
    const values = CRITERES.map((c) => criteres[c.key]).filter((v): v is number => typeof v === 'number');
    if (values.length === 0) return null;
    return Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10;
  }, [criteres]);

  const valide = CRITERES.every((c) => typeof criteres[c.key] === 'number' && criteres[c.key] >= 1 && criteres[c.key] <= 5);

  async function soumettre() {
    if (!valide) {
      afficherNotification({ type: 'erreur', message: 'Toutes les notes (1-5) sont requises.' });
      return;
    }
    if (commentaire.length > 500) {
      afficherNotification({ type: 'erreur', message: 'Le commentaire est limité à 500 caractères.' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_creer_notation_mission' as any, {
      p_mission_id: mission.mission_id,
      p_sens: 'ETAB_VERS_SOIGNANT',
      p_critere_1: criteres.critere_1,
      p_critere_2: criteres.critere_2,
      p_critere_3: criteres.critere_3,
      p_critere_4: criteres.critere_4,
      p_commentaire: commentaire.trim() || null,
    });
    setLoading(false);
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    const result = data as any;
    if (!result?.success && result?.error) {
      afficherNotification({ type: 'erreur', message: result.error });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Évaluation enregistrée. Merci !' });
    onEvaluee?.();
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !loading) onFermer(); }}>
      <DialogResponsiveContent maxWidth="lg">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Évaluer le soignant</DialogResponsiveTitle>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          {/* Récap */}
          <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-0.5">
            <p className="font-semibold text-foreground">{mission.intitule}</p>
            <p className="text-muted-foreground">{mission.soignant_prenom} {mission.soignant_nom} · {mission.soignant_profession}</p>
          </div>

          {/* Critères */}
          <div className="space-y-4">
            {CRITERES.map((c) => (
              <div key={c.key} className="space-y-1">
                <div className="flex items-baseline justify-between">
                  <label className="text-sm font-medium text-foreground">{c.label} *</label>
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {criteres[c.key] ? `${criteres[c.key]}/5` : '—/5'}
                  </span>
                </div>
                <p className="text-[11px] text-muted-foreground">{c.description}</p>
                <div className="flex gap-1.5">
                  {[1, 2, 3, 4, 5].map((n) => (
                    <button
                      key={n}
                      type="button"
                      onClick={() => setCriteres((prev) => ({ ...prev, [c.key]: n }))}
                      className={`flex-1 min-h-[44px] rounded-lg border-2 transition-all text-sm font-medium ${
                        criteres[c.key] === n
                          ? 'border-primary bg-primary/10 text-primary'
                          : 'border-border bg-background text-muted-foreground hover:border-primary/40'
                      }`}
                      disabled={loading}
                      aria-label={`${c.label} : ${n}/5`}
                    >
                      <Star className={`h-4 w-4 inline ${criteres[c.key] && n <= criteres[c.key] ? 'fill-current' : ''}`} />
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>

          {/* Note globale */}
          {noteGlobale !== null && (
            <div className="rounded-lg border-2 border-primary/30 bg-primary/5 p-3 text-center">
              <p className="text-xs text-muted-foreground">Note globale calculée</p>
              <p className="text-2xl font-bold text-primary tabular-nums">{noteGlobale} / 5</p>
            </div>
          )}

          {/* Commentaire */}
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Commentaire (optionnel, max 500 caractères)</span>
            <textarea
              value={commentaire}
              onChange={(e) => setCommentaire(e.target.value.slice(0, 500))}
              className="input-base"
              rows={3}
              placeholder="Vos retours qualitatifs sur le soignant…"
              maxLength={500}
              disabled={loading}
            />
            <span className="text-[10px] text-muted-foreground">{commentaire.length} / 500</span>
          </label>

          <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <p>L'évaluation alimente le score de fiabilité du soignant. Le soignant sera notifié de cette évaluation et pourra la contester via le support si elle paraît injuste.</p>
          </div>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button onClick={onFermer} disabled={loading} className="btn-secondary min-h-[44px] disabled:opacity-50">Annuler</button>
          <button
            onClick={soumettre}
            disabled={loading || !valide}
            className="btn-primary min-h-[44px] disabled:opacity-50 inline-flex items-center justify-center gap-2"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Envoyer l'évaluation
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

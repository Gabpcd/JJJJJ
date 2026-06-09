import { useState } from 'react';
import { Flag } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

const CATEGORIES: { value: string; label: string }[] = [
  { value: 'COMPORTEMENT_INAPPROPRIE', label: 'Comportement inapproprié' },
  { value: 'NON_PROFESSIONNALISME', label: 'Manque de professionnalisme' },
  { value: 'FRAUDE_SUSPECTEE', label: 'Fraude suspectée' },
  { value: 'FAUX_DOCUMENT', label: 'Faux document' },
  { value: 'USURPATION_IDENTITE', label: "Usurpation d'identité" },
  { value: 'SECURITE_DANGER', label: 'Sécurité / danger' },
  { value: 'AUTRE', label: 'Autre' },
];

interface Props {
  cibleId: string;
  cibleType: 'SOIGNANT' | 'ETABLISSEMENT';
  missionId?: string | null;
  /** Rendu compact (lien texte) au lieu d'un bouton plein. */
  variant?: 'bouton' | 'lien';
}

/**
 * Bouton + modal de signalement d'un utilisateur à l'administration Jolene.
 * Motif obligatoire (≥ 10 caractères). Appelle fn_signaler_utilisateur.
 */
export function SignalerUtilisateur({ cibleId, cibleType, missionId = null, variant = 'lien' }: Props) {
  const [open, setOpen] = useState(false);
  const [categorie, setCategorie] = useState('COMPORTEMENT_INAPPROPRIE');
  const [motif, setMotif] = useState('');
  const [saving, setSaving] = useState(false);

  async function envoyer() {
    if (motif.trim().length < 10) {
      toast.error('Merci de préciser le motif (10 caractères minimum).');
      return;
    }
    setSaving(true);
    const { data, error } = await supabase.rpc('fn_signaler_utilisateur' as any, {
      p_cible_id: cibleId,
      p_cible_type: cibleType,
      p_categorie: categorie,
      p_motif: motif.trim(),
      p_mission_id: missionId,
    });
    setSaving(false);
    const res = data as { success?: boolean; error?: string } | null;
    if (error || !res?.success) {
      toast.error(res?.error || error?.message || "Échec de l'envoi du signalement.");
      return;
    }
    toast.success('Signalement transmis à Jolene. Merci, notre équipe va l’examiner.');
    setOpen(false);
    setMotif('');
  }

  return (
    <>
      {variant === 'bouton' ? (
        <button type="button" onClick={() => setOpen(true)}
          className="inline-flex items-center gap-1.5 rounded-lg border border-destructive/40 text-destructive px-3 py-1.5 text-sm font-medium hover:bg-destructive/10 transition-colors">
          <Flag className="h-3.5 w-3.5" /> Signaler à Jolene
        </button>
      ) : (
        <button type="button" onClick={() => setOpen(true)}
          className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-destructive transition-colors">
          <Flag className="h-3 w-3" /> Signaler
        </button>
      )}

      {open && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setOpen(false)}>
          <div className="bg-card border border-border rounded-2xl max-w-md w-full p-6 space-y-4 max-h-[90dvh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h3 className="font-bold text-foreground flex items-center gap-2"><Flag className="h-4 w-4 text-destructive" /> Signaler à Jolene</h3>
            <p className="text-xs text-muted-foreground">Votre signalement est transmis à l'administration Jolene, qui l'examinera. Soyez précis et factuel.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Motif</span>
              <select value={categorie} onChange={(e) => setCategorie(e.target.value)} className="input-base">
                {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block">Précisez (obligatoire)</span>
              <textarea value={motif} onChange={(e) => setMotif(e.target.value)} rows={4}
                placeholder="Décrivez précisément ce que vous signalez…" className="input-base resize-none" />
            </label>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setOpen(false)} className="btn-secondary text-sm">Annuler</button>
              <button type="button" onClick={envoyer} disabled={saving || motif.trim().length < 10}
                className="inline-flex items-center gap-1.5 rounded-lg bg-destructive text-destructive-foreground px-4 py-2 text-sm font-medium disabled:opacity-50">
                {saving ? 'Envoi…' : 'Envoyer le signalement'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

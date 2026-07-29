import { useState } from 'react';
import { Loader2, Upload, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { sanitiserNomFichier, verifierFichierDocument } from '@/lib/documentUpload';

interface Props {
  ouvert: boolean;
  onFermer: () => void;
  onCreee?: (reclamationId: string) => void;
  evenementId: string;
  evenementType: 'SOIGNANT' | 'ETAB';
  /** Détails de l'événement pour le rappel */
  evenementInfo: {
    type_evenement: string;
    points: number;
    motif: string;
    cree_le: string;
  };
}

const MOTIFS = [
  { value: 'URGENCE_MEDICALE', label: '🏥 Urgence médicale' },
  { value: 'DEUIL', label: '🕊️ Deuil' },
  { value: 'FORCE_MAJEURE', label: '⚡ Force majeure' },
  { value: 'ERREUR_JOLENE', label: '🔧 Erreur Jolene' },
  { value: 'CONTEXTE_PARTICULIER', label: '📝 Contexte particulier' },
  { value: 'AUTRE', label: '❓ Autre' },
];

/**
 * Modale de réclamation contre un événement de score (Sprint 3.5 PR 7).
 *
 * Permet à un soignant ou un étab de contester un événement de score qui
 * le pénalise. Un justificatif non médical (PDF, image) peut être joint
 * de manière facultative.
 *
 * La réclamation est créée en statut PENDING et examinée par un admin
 * Jolene (PR 8 Sprint 3.5).
 */
export function ModaleReclamationScore({
  ouvert, onFermer, onCreee, evenementId, evenementType, evenementInfo,
}: Props) {
  const { afficherNotification } = useNotification();
  const [motif, setMotif] = useState('');
  const [texte, setTexte] = useState('');
  const [fichier, setFichier] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);

  if (!ouvert) return null;

  async function uploadJustificatif(): Promise<string | null> {
    if (!fichier) return null;
    const validation = await verifierFichierDocument(fichier, { maxBytes: 5 * 1024 * 1024 });
    if (validation.ok === false) {
      afficherNotification({ type: 'erreur', message: validation.message });
      return null;
    }
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      afficherNotification({ type: 'erreur', message: 'Votre session a expiré. Reconnectez-vous.' });
      return null;
    }
    const safeName = sanitiserNomFichier(fichier.name, validation.mime);
    const path = `${authData.user.id}/reclamations/${evenementId}/${Date.now()}_${safeName}`;
    const { error } = await supabase.storage
      .from('justificatifs')
      .upload(path, fichier, { contentType: validation.mime, upsert: false });
    if (error) {
      afficherNotification({ type: 'erreur', message: 'Erreur upload : ' + error.message });
      return null;
    }
    return path;
  }

  async function soumettre() {
    if (!motif) {
      afficherNotification({ type: 'erreur', message: 'Sélectionne un motif.' });
      return;
    }
    if (texte.trim().length < 20) {
      afficherNotification({ type: 'erreur', message: 'Texte libre min 20 caractères.' });
      return;
    }
    setLoading(true);
    try {
      const justificatif = fichier ? await uploadJustificatif() : null;
      if (fichier && !justificatif) return;
      const { data, error } = await supabase.rpc('fn_creer_reclamation_score' as any, {
        p_evenement_id: evenementId,
        p_evenement_type: evenementType,
        p_motif_categorie: motif,
        p_texte_libre: texte.trim(),
        p_justificatif_storage_path: justificatif,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      afficherNotification({ type: 'succes', message: 'Réclamation envoyée. Un admin Jolene va l\'examiner.' });
      onCreee?.(result.reclamation_id);
      onFermer();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div className="bg-card border border-border rounded-xl max-w-md w-full p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="text-lg font-bold text-foreground">Contester cet événement de score</h2>

        <div className="rounded-lg bg-muted/40 p-3 text-xs">
          <p className="font-semibold text-foreground">{evenementInfo.type_evenement}</p>
          <p className="text-muted-foreground mt-1">{evenementInfo.motif}</p>
          <p className="font-mono mt-1 text-destructive">{evenementInfo.points} pts</p>
        </div>

        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif de la contestation *</span>
          <select value={motif} onChange={e => setMotif(e.target.value)} className="input-base">
            <option value="">— Sélectionne —</option>
            {MOTIFS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
        </label>

        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Explication détaillée * (min 20 caractères)</span>
          <textarea
            value={texte}
            onChange={e => setTexte(e.target.value)}
            className="input-base"
            rows={5}
            placeholder="Explique précisément la situation : que s'est-il passé, pourquoi cet événement ne devrait pas te pénaliser..."
          />
          <span className="text-[10px] text-muted-foreground">{texte.length} / 20+</span>
        </label>

        <div className="block">
          <span id="reclamation-justificatif-label" className="text-xs font-medium text-foreground mb-1 block">Justificatif non médical (optionnel — PDF, image, max 5 Mo)</span>
          <label className="flex items-center gap-2 cursor-pointer rounded-lg border border-dashed border-border bg-muted/20 p-3 hover:bg-muted/40 transition">
            <Upload className="h-4 w-4 text-muted-foreground" />
            <span className="text-xs text-muted-foreground flex-1">
              {fichier ? fichier.name : 'Choisir un fichier'}
            </span>
            <input
              type="file"
              accept="application/pdf,image/jpeg,image/png,image/webp"
              aria-labelledby="reclamation-justificatif-label"
              className="hidden"
              onChange={async e => {
                const selected = e.target.files?.[0] || null;
                if (!selected) { setFichier(null); return; }
                const validation = await verifierFichierDocument(selected, { maxBytes: 5 * 1024 * 1024 });
                if (validation.ok === false) {
                  setFichier(null);
                  afficherNotification({ type: 'erreur', message: validation.message });
                  e.target.value = '';
                  return;
                }
                setFichier(selected);
              }}
            />
          </label>
          <p className="text-[10px] text-warning mt-1">
            N'envoyez aucun certificat médical ni document mentionnant un diagnostic ou une information de santé. Vous pouvez joindre uniquement une preuve non médicale, par exemple un justificatif de transport ou une attestation employeur ne contenant aucune donnée de santé.
          </p>
        </div>

        <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <p>Ta réclamation sera examinée par un administrateur Jolene. La décision (annulation, réduction ou maintien) sera notifiée par email + push.</p>
        </div>

        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">
            Annuler
          </button>
          <button onClick={soumettre} disabled={loading} className="btn-primary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2">
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Envoyer
          </button>
        </div>
      </div>
    </div>
  );
}

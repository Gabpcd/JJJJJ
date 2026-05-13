import { useState } from 'react';
import { Loader2, Upload, X, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { AnnulationCandidatureTimer } from './AnnulationCandidatureTimer';

interface Props {
  ouvert: boolean;
  onFermer: () => void;
  onAnnulee?: () => void;
  candidatureId: string;
  accepteeA: string | Date;
  debutMission: string | Date;
  estAsap?: boolean;
  /** Récapitulatif mission affiché en tête de modale */
  missionInfo: {
    intitule: string;
    etablissementNom: string;
    debut_le: string;
    fin_le: string;
  };
}

const MOTIFS = [
  { value: 'URGENCE_PERSONNELLE', label: '🆘 Urgence personnelle' },
  { value: 'URGENCE_MEDICALE', label: '🏥 Urgence médicale' },
  { value: 'DEUIL', label: '🕊️ Deuil' },
  { value: 'PROBLEME_TRANSPORT', label: '🚗 Problème de transport' },
  { value: 'CHANGEMENT_AVIS', label: '🤔 Changement d\'avis' },
  { value: 'AUTRE', label: '❓ Autre' },
];

/**
 * Modale d'annulation candidature soignant Sprint 3.5.
 *
 * Affiche les conséquences AVANT confirmation via AnnulationCandidatureTimer,
 * collecte un motif structuré + texte libre obligatoire (min 20 chars) +
 * justificatif optionnel (PDF/image, max 5 MB).
 *
 * Coche obligatoire "J'ai compris les conséquences" pour activer le bouton
 * confirmer.
 *
 * Appelle `fn_annuler_candidature_soignant` qui :
 *   - calcule la pénalité backend (re-vérification)
 *   - crée un évenement_score_soignant si applicable
 *   - notifie l'établissement (push + email)
 *   - audit trail
 */
export function ModaleAnnulationCandidature({
  ouvert, onFermer, onAnnulee, candidatureId, accepteeA, debutMission, estAsap = false, missionInfo,
}: Props) {
  const { afficherNotification } = useNotification();
  const [motif, setMotif] = useState('');
  const [texte, setTexte] = useState('');
  const [fichier, setFichier] = useState<File | null>(null);
  const [accepte, setAccepte] = useState(false);
  const [loading, setLoading] = useState(false);

  if (!ouvert) return null;

  async function uploadJustificatif(): Promise<string | null> {
    if (!fichier) return null;
    if (fichier.size > 5 * 1024 * 1024) {
      afficherNotification({ type: 'erreur', message: 'Fichier trop volumineux (max 5 MB).' });
      return null;
    }
    const safeName = fichier.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const path = `annulations-candidature/${candidatureId}/${Date.now()}_${safeName}`;
    const { error } = await supabase.storage.from('justificatifs').upload(path, fichier, { upsert: false });
    if (error) {
      afficherNotification({ type: 'erreur', message: 'Erreur upload : ' + error.message });
      return null;
    }
    return path;
  }

  async function confirmer() {
    if (!motif) {
      afficherNotification({ type: 'erreur', message: 'Sélectionnez un motif.' });
      return;
    }
    if (texte.trim().length < 20) {
      afficherNotification({ type: 'erreur', message: 'Veuillez ajouter une explication (min 20 caractères).' });
      return;
    }
    if (!accepte) {
      afficherNotification({ type: 'erreur', message: 'Veuillez cocher la case de confirmation.' });
      return;
    }
    setLoading(true);
    try {
      const justificatifPath = fichier ? await uploadJustificatif() : null;
      if (fichier && !justificatifPath) {
        // upload échoué — on n'enregistre pas
        setLoading(false);
        return;
      }
      const { data, error } = await supabase.rpc('fn_annuler_candidature_soignant' as any, {
        p_candidature_id: candidatureId,
        p_motif_categorie: motif,
        p_texte_libre: texte.trim(),
        p_justificatif_storage_path: justificatifPath,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        const code = result?.error_code;
        const message = result?.error || codeErreurFr(code) || 'Erreur lors de l\'annulation.';
        afficherNotification({ type: 'erreur', message });
        return;
      }
      const points = Number(result?.points ?? 0);
      const msg = points < 0
        ? `Candidature annulée. Score impacté : ${points} pts.`
        : 'Candidature annulée.';
      afficherNotification({ type: 'succes', message: msg });
      onAnnulee?.();
      onFermer();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau.' });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div
        className="bg-card border border-border rounded-2xl max-w-lg w-full p-6 space-y-4 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-foreground">Annuler votre candidature</h2>
          <button onClick={onFermer} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer">
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Récap mission */}
        <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-0.5">
          <p className="font-semibold text-foreground">{missionInfo.intitule}</p>
          <p className="text-muted-foreground">{missionInfo.etablissementNom}</p>
          <p className="text-muted-foreground">
            Du {new Date(missionInfo.debut_le).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
            {' '}au{' '}
            {new Date(missionInfo.fin_le).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
          </p>
        </div>

        {/* Conséquences calculées */}
        <AnnulationCandidatureTimer
          accepteeA={accepteeA}
          debutMission={debutMission}
          estAsap={estAsap}
        />

        {/* Motif structuré */}
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif de l'annulation *</span>
          <select value={motif} onChange={(e) => setMotif(e.target.value)} className="input-base">
            <option value="">— Sélectionnez —</option>
            {MOTIFS.map((m) => (
              <option key={m.value} value={m.value}>{m.label}</option>
            ))}
          </select>
        </label>

        {/* Texte libre */}
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Explication détaillée * (min 20 caractères)</span>
          <textarea
            value={texte}
            onChange={(e) => setTexte(e.target.value)}
            className="input-base"
            rows={4}
            placeholder="Expliquez la situation : que s'est-il passé, pourquoi vous devez annuler maintenant…"
          />
          <span className="text-[10px] text-muted-foreground">{texte.length} / 20+</span>
        </label>

        {/* Justificatif optionnel */}
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Justificatif (optionnel — PDF, image, max 5 MB)</span>
          <label className="flex items-center gap-2 cursor-pointer rounded-lg border border-dashed border-border bg-muted/20 p-3 hover:bg-muted/40 transition">
            <Upload className="h-4 w-4 text-muted-foreground" />
            <span className="text-xs text-muted-foreground flex-1">
              {fichier ? fichier.name : 'Choisir un fichier'}
            </span>
            <input
              type="file"
              accept="application/pdf,image/*"
              className="hidden"
              onChange={(e) => setFichier(e.target.files?.[0] || null)}
            />
          </label>
          <p className="text-[10px] text-muted-foreground mt-1">
            Un justificatif (certif médical, billet de train annulé…) facilite la contestation si vous le souhaitez.
          </p>
        </label>

        {/* Coche confirmation */}
        <label className="flex items-start gap-2 rounded-lg border border-border bg-background p-3 cursor-pointer">
          <input
            type="checkbox"
            checked={accepte}
            onChange={(e) => setAccepte(e.target.checked)}
            className="mt-1 h-4 w-4 rounded border-border"
            disabled={loading}
          />
          <span className="text-xs text-foreground">
            J'ai compris les conséquences (impact score le cas échéant) et je confirme l'annulation de ma candidature.
          </span>
        </label>

        <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <p>L'établissement sera notifié immédiatement. Si la pénalité vous semble injuste, vous pourrez la contester depuis votre page score.</p>
        </div>

        <div className="flex gap-2">
          <button onClick={onFermer} disabled={loading} className="btn-secondary flex-1 disabled:opacity-50">
            Garder la candidature
          </button>
          <button
            onClick={confirmer}
            disabled={loading || !motif || texte.trim().length < 20 || !accepte}
            className="btn-primary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Confirmer l'annulation
          </button>
        </div>
      </div>
    </div>
  );
}

function codeErreurFr(code?: string): string | null {
  if (!code) return null;
  switch (code) {
    case 'NON_AUTHENTIFIE': return 'Session expirée, reconnectez-vous.';
    case 'NON_AUTORISE': return 'Vous n\'êtes pas autorisé(e) à annuler cette candidature.';
    case 'MOTIF_INVALIDE': return 'Motif invalide.';
    case 'CANDIDATURE_INTROUVABLE': return 'Candidature introuvable ou déjà annulée.';
    case 'STATUT_INVALIDE': return 'La candidature ne peut plus être annulée dans son état actuel.';
    default: return null;
  }
}

import { useState } from 'react';
import { Loader2, Check, X, Clock, Euro, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { ModalConfirmation } from '@/components/ModalConfirmation';

interface Props {
  litigeId: string;
  /** Si une proposition existe déjà, on l'affiche avec un bouton Accepter/Refuser */
  propositionExistante?: {
    type: TypeModification;
    modifications: Record<string, any>;
    justification?: string;
    proposeur_role?: 'soignant' | 'etablissement';
  } | null;
  /** Rôle de l'utilisateur courant */
  roleUtilisateur: 'soignant' | 'etablissement';
  /** Callback quand la proposition est créée OU acceptée */
  onResolu?: () => void;
}

type TypeModification =
  | 'MODIFICATION_HORAIRES'
  | 'MODIFICATION_MONTANT'
  | 'ANNULATION_TOTALE'
  | 'COMPENSATION_PARTIELLE'
  | 'MIXTE'
  | 'ACCORD_SANS_MODIFICATION';

const TYPES_LABEL: Record<TypeModification, string> = {
  MODIFICATION_HORAIRES: '⏰ Corriger les horaires de pointage',
  MODIFICATION_MONTANT: '💶 Ajuster le montant total',
  ANNULATION_TOTALE: '❌ Annuler la mission entièrement',
  COMPENSATION_PARTIELLE: '⚖️ Compensation partielle (% de réduction)',
  MIXTE: '🔀 Modification mixte (horaires + montant)',
  ACCORD_SANS_MODIFICATION: '🤝 Accord sans modification chiffrée',
};

/**
 * Composant FormulaireAccord (PR 3 Sprint 3.5).
 *
 * Permet à une partie d'un litige de proposer une modification structurée
 * (horaires, montant, annulation, compensation) qui sera exécutée
 * automatiquement par fn_cloturer_litige_avec_payload après accord de
 * l'autre partie.
 *
 * Si propositionExistante est fournie, affiche la proposition + bouton
 * Accepter/Refuser. Sinon, formulaire de création.
 */
export function FormulaireAccord({ litigeId, propositionExistante, roleUtilisateur, onResolu }: Props) {
  const { afficherNotification } = useNotification();
  const [type, setType] = useState<TypeModification>('ACCORD_SANS_MODIFICATION');
  const [horaireArrivee, setHoraireArrivee] = useState('');
  const [horaireDepart, setHoraireDepart] = useState('');
  const [montantCorrige, setMontantCorrige] = useState('');
  const [pourcentageCompensation, setPourcentageCompensation] = useState('');
  const [motifAnnulation, setMotifAnnulation] = useState('');
  const [justification, setJustification] = useState('');
  const [loading, setLoading] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [modeContreProposition, setModeContreProposition] = useState(false);

  async function envoyerProposition() {
    const modifications: Record<string, any> = {};

    if (type === 'MODIFICATION_HORAIRES' || type === 'MIXTE') {
      if (!horaireArrivee || !horaireDepart) {
        afficherNotification({ type: 'erreur', message: 'Horaires arrivée et départ requis.' });
        return;
      }
      const arrivee = new Date(horaireArrivee);
      const depart = new Date(horaireDepart);
      if (Number.isNaN(arrivee.getTime()) || Number.isNaN(depart.getTime()) || depart <= arrivee) {
        afficherNotification({ type: 'erreur', message: 'L’heure de départ doit être postérieure à l’heure d’arrivée.' });
        return;
      }
      // datetime-local n'embarque aucun fuseau. Envoyer un ISO explicite évite
      // que PostgreSQL interprète l'heure française comme une heure UTC.
      modifications.pointage_arrivee_le = arrivee.toISOString();
      modifications.pointage_depart_le = depart.toISOString();
    }
    if (type === 'MODIFICATION_MONTANT' || type === 'MIXTE') {
      const montant = Number(montantCorrige);
      if (!Number.isFinite(montant) || montant <= 0 || montant > 10_000_000) {
        afficherNotification({ type: 'erreur', message: 'Saisissez un montant positif valide.' });
        return;
      }
      modifications.montant_total_corrige = montant;
    }
    if (type === 'COMPENSATION_PARTIELLE') {
      const pct = parseFloat(pourcentageCompensation);
      if (isNaN(pct) || pct <= 0 || pct > 100) {
        afficherNotification({ type: 'erreur', message: 'Pourcentage entre 1 et 100 requis.' });
        return;
      }
      modifications.pourcentage_compensation = pct;
    }
    if (type === 'ANNULATION_TOTALE') {
      if (!motifAnnulation.trim()) {
        afficherNotification({ type: 'erreur', message: 'Motif d\'annulation requis.' });
        return;
      }
      modifications.motif_annulation = motifAnnulation.trim();
    }
    if (!justification.trim()) {
      afficherNotification({ type: 'erreur', message: 'Justification écrite obligatoire.' });
      return;
    }

    const payload = { type, modifications, justification: justification.trim() };

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_cloturer_litige_avec_payload' as any, {
        p_litige_id: litigeId,
        p_payload: payload,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      if (result.statut === 'RESOLU_ACCORD_PARTIES') {
        afficherNotification({ type: 'succes', message: 'Litige résolu ✅ Modifications appliquées.' });
      } else if (result.statut === 'EN_ATTENTE_VALIDATION_ADMIN') {
        afficherNotification({ type: 'succes', message: 'Accord conclu ✅ Le mouvement financier sera exécuté après validation de l\'administrateur.' });
      } else {
        afficherNotification({ type: 'succes', message: 'Proposition envoyée. En attente de l\'autre partie.' });
      }
      setModeContreProposition(false);
      onResolu?.();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
      setShowConfirm(false);
    }
  }

  async function accepterProposition() {
    if (!propositionExistante) return;
    // `proposeur_role` est une donnée de présentation dérivée côté UI. Ne pas
    // la renvoyer dans le JSON versionné : l'accord doit porter exactement sur
    // le payload stocké par le proposant.
    const payloadExact = {
      type: propositionExistante.type,
      modifications: propositionExistante.modifications,
      justification: propositionExistante.justification,
    };
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_cloturer_litige_avec_payload' as any, {
        p_litige_id: litigeId,
        p_payload: payloadExact,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      afficherNotification({
        type: 'succes',
        message: result.statut === 'EN_ATTENTE_VALIDATION_ADMIN'
          ? 'Accord conclu ✅ Le mouvement financier sera exécuté après validation de l\'administrateur.'
          : 'Accord conclu ✅ Modifications appliquées.',
      });
      onResolu?.();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  // Le proposeur ne peut pas écraser sa propre proposition pendant que
  // l'autre partie ne l'a pas encore acceptée/refusée.
  if (propositionExistante && propositionExistante.proposeur_role === roleUtilisateur) {
    const mods = propositionExistante.modifications || {};
    return (
      <div className="rounded-xl border-2 border-amber-300 bg-amber-50 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <Clock className="h-5 w-5 text-amber-700" />
          <h3 className="font-bold text-foreground">Proposition envoyée</h3>
        </div>
        <p className="text-sm text-muted-foreground">
          Elle est en attente de la réponse de l'autre partie. Vous ne pouvez pas envoyer une seconde proposition entre-temps.
        </p>
        <div className="rounded-lg bg-card border border-border p-3 space-y-2 text-sm">
          <p className="font-semibold text-primary">{TYPES_LABEL[propositionExistante.type]}</p>
          {mods.montant_total_corrige != null && <p>Nouveau montant : {mods.montant_total_corrige} €</p>}
          {mods.pourcentage_compensation != null && <p>Compensation : -{mods.pourcentage_compensation}%</p>}
          {propositionExistante.justification && <p className="italic text-muted-foreground">« {propositionExistante.justification} »</p>}
        </div>
      </div>
    );
  }

  // === Affichage proposition existante ===
  if (propositionExistante && propositionExistante.proposeur_role !== roleUtilisateur && !modeContreProposition) {
    const mods = propositionExistante.modifications || {};
    return (
      <div className="rounded-xl border-2 border-primary/40 bg-primary/5 p-4 space-y-3">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 text-primary" />
          <h3 className="font-bold text-foreground">Proposition d'accord reçue</h3>
        </div>
        <p className="text-sm text-foreground">
          {propositionExistante.proposeur_role === 'soignant' ? 'Le soignant' : 'L\'établissement'} propose :
        </p>
        <div className="rounded-lg bg-card border border-border p-3 space-y-2 text-sm">
          <p className="font-semibold text-primary">{TYPES_LABEL[propositionExistante.type]}</p>
          {mods.pointage_arrivee_le && (
            <p className="text-xs"><Clock className="h-3 w-3 inline mr-1" /> Arrivée : {new Date(mods.pointage_arrivee_le).toLocaleString('fr-FR')}</p>
          )}
          {mods.pointage_depart_le && (
            <p className="text-xs"><Clock className="h-3 w-3 inline mr-1" /> Départ : {new Date(mods.pointage_depart_le).toLocaleString('fr-FR')}</p>
          )}
          {mods.montant_total_corrige != null && (
            <p className="text-xs"><Euro className="h-3 w-3 inline mr-1" /> Nouveau montant : {mods.montant_total_corrige} €</p>
          )}
          {mods.pourcentage_compensation != null && (
            <p className="text-xs">Compensation : -{mods.pourcentage_compensation}%</p>
          )}
          {mods.motif_annulation && (
            <p className="text-xs italic">{mods.motif_annulation}</p>
          )}
          {propositionExistante.justification && (
            <p className="text-xs italic text-muted-foreground border-t border-border pt-2 mt-2">
              « {propositionExistante.justification} »
            </p>
          )}
        </div>
        <div className="flex gap-2">
          <button
            onClick={accepterProposition}
            disabled={loading}
            className="btn-primary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2"
          >
            {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
            Accepter la proposition
          </button>
          <button
            disabled={loading}
            className="btn-secondary flex-1 disabled:opacity-50 inline-flex items-center justify-center gap-2"
            onClick={() => setModeContreProposition(true)}
          >
            <X className="h-4 w-4" />
            Refuser / Contre-proposer
          </button>
        </div>
        <p className="text-[10px] text-muted-foreground italic">
          En acceptant, les corrections opérationnelles seront appliquées et tracées. Tout mouvement financier reste soumis aux contrôles de sécurité Jolene.
        </p>
      </div>
    );
  }

  // === Formulaire création proposition ===
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold text-foreground">{modeContreProposition ? 'Faire une contre-proposition' : 'Proposer un accord'}</h3>
          {modeContreProposition && (
            <p className="text-xs text-warning mt-1">Cette nouvelle version remplacera la proposition reçue et demandera un nouvel accord à l’autre partie.</p>
          )}
        </div>
        {modeContreProposition && (
          <button type="button" className="text-xs text-muted-foreground hover:underline" onClick={() => setModeContreProposition(false)}>
            Revenir à la proposition reçue
          </button>
        )}
      </div>
      <p className="text-xs text-muted-foreground">
        Décrivez précisément la modification convenue. Une fois acceptée par l'autre partie, elle sera
        appliquée aux présences et documents concernés ; un mouvement financier sensible passe par la validation Jolene.
      </p>

      <label className="block">
        <span className="text-xs font-medium text-foreground mb-1 block">Type de modification</span>
        <select value={type} onChange={e => setType(e.target.value as TypeModification)} className="input-base">
          {Object.entries(TYPES_LABEL).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
      </label>

      {(type === 'MODIFICATION_HORAIRES' || type === 'MIXTE') && (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Arrivée corrigée</span>
            <input type="datetime-local" value={horaireArrivee} onChange={e => setHoraireArrivee(e.target.value)} className="input-base text-sm" />
          </label>
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Départ corrigé</span>
            <input type="datetime-local" value={horaireDepart} onChange={e => setHoraireDepart(e.target.value)} className="input-base text-sm" />
          </label>
        </div>
      )}

      {(type === 'MODIFICATION_MONTANT' || type === 'MIXTE') && (
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Nouveau montant total (€)</span>
          <input type="number" step="0.01" min="0" value={montantCorrige} onChange={e => setMontantCorrige(e.target.value)} className="input-base text-sm" placeholder="240.00" />
        </label>
      )}

      {type === 'COMPENSATION_PARTIELLE' && (
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Pourcentage de réduction (1-100)</span>
          <input type="number" min="1" max="100" value={pourcentageCompensation} onChange={e => setPourcentageCompensation(e.target.value)} className="input-base text-sm" placeholder="30" />
        </label>
      )}

      {type === 'ANNULATION_TOTALE' && (
        <label className="block">
          <span className="text-xs font-medium text-foreground mb-1 block">Motif d'annulation</span>
          <input type="text" value={motifAnnulation} onChange={e => setMotifAnnulation(e.target.value)} className="input-base text-sm" placeholder="Ex: soignant parti avant la fin pour raison médicale" />
        </label>
      )}

      <label className="block">
        <span className="text-xs font-medium text-foreground mb-1 block">Justification écrite *</span>
        <textarea value={justification} onChange={e => setJustification(e.target.value)} className="input-base text-sm" rows={3} placeholder="Expliquez le contexte..." />
      </label>

      <button
        type="button"
        onClick={() => setShowConfirm(true)}
        disabled={loading}
        className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
      >
        {loading && <Loader2 className="h-4 w-4 animate-spin" />}
        Envoyer la proposition
      </button>

      <p className="text-[10px] text-muted-foreground italic">
        L'autre partie verra cette proposition et pourra l'accepter (auto-exécution) ou contre-proposer.
      </p>

      <ModalConfirmation
        ouvert={showConfirm}
        onFermer={() => setShowConfirm(false)}
        onConfirmer={envoyerProposition}
        titre="Envoyer la proposition d'accord ?"
        message={
          type === 'ANNULATION_TOTALE'
            ? 'Si elle est acceptée, l’annulation et les documents rectificatifs seront appliqués. Tout remboursement éventuel restera soumis aux contrôles Jolene.'
            : 'Si elle est acceptée, les corrections seront appliquées et tracées. Tout mouvement financier sensible restera soumis aux contrôles Jolene.'
        }
        labelConfirmer="Envoyer la proposition"
        variante="primaire"
      />
    </div>
  );
}

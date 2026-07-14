import { useCallback, useEffect, useRef, useState } from 'react';
import { Loader2, FileText, AlertCircle, CheckCircle, XCircle, Edit3 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Reclamation {
  id: string;
  evenement_type: 'SOIGNANT' | 'ETAB';
  evenement_id: string;
  event_type_evenement: string;
  event_points: number;
  event_motif: string;
  event_cree_le: string;
  contesteur_id: string;
  motif_categorie: string;
  texte_libre: string;
  justificatif_storage_path: string | null;
  statut: 'PENDING' | 'TREATED' | 'CANCELLED';
  decision_admin: 'MAINTENIR' | 'REDUIRE' | 'ANNULER' | null;
  motif_admin: string | null;
  cree_le: string;
  jours_attente: number;
}

/** Libellés français des types de profil concernés (valeurs techniques inchangées côté RPC). */
const LIBELLES_EVENEMENT_TYPE: Record<Reclamation['evenement_type'], string> = {
  SOIGNANT: 'Soignant',
  ETAB: 'Établissement',
};

/** Libellés français des types d'événement score (cf. CHECK en base). */
const LIBELLES_TYPE_EVENEMENT: Record<string, string> = {
  // Événements soignant
  ANNULATION_12_24H: 'Annulation entre 12h et 24h avant la mission',
  ANNULATION_1_12H: 'Annulation entre 1h et 12h avant la mission',
  ASAP_ANNULEE_APRES_FENETRE: 'Mission urgente annulée hors délai',
  NO_SHOW: 'Absence non signalée',
  LITIGE_TORT_RECONNU: 'Litige avec tort reconnu',
  NOTE_BASSE_RECUE: 'Note basse reçue',
  EVALUATION_NEGATIVE: 'Évaluation négative',
  BONUS_AMBASSADEUR: 'Bonus ambassadeur',
  BONUS_FIDELITE: 'Bonus fidélité',
  // Événements établissement
  ANNULATION_AVANT_CONTRAT: 'Annulation avant signature du contrat',
  ANNULATION_CDD_SIGNE: 'Annulation après CDD signé',
  ANNULATION_LIBERAL_SIGNE: 'Annulation après contrat libéral signé',
  ANNULATION_APRES_POINTAGE: 'Annulation après pointage',
  PAIEMENT_RETARD: 'Paiement en retard',
  AUTRE: 'Autre',
};

function libelleTypeEvenement(type: string): string {
  return LIBELLES_TYPE_EVENEMENT[type] ?? type;
}

/** Libellés français des décisions admin affichées en badge. */
const LIBELLES_DECISION: Record<NonNullable<Reclamation['decision_admin']>, string> = {
  MAINTENIR: 'Pénalité maintenue',
  REDUIRE: 'Pénalité réduite',
  ANNULER: 'Pénalité annulée',
};

/**
 * Page admin /admin/reclamations-score (PR 8 Sprint 3.5).
 *
 * Liste des réclamations de score avec actions MAINTENIR/REDUIRE/ANNULER.
 * Décision propagée automatiquement aux événements + recalcul score.
 */
/* Session D-bis : contenu embarqué comme onglet « Contestations score » de
   /admin/reclamations (l'ancienne route /admin/reclamations-score redirige). */
export function ReclamationsScoreContent() {
  const { afficherNotification } = useNotification();
  const [filtre, setFiltre] = useState<'PENDING' | 'TREATED' | 'TOUS'>('PENDING');
  const [reclamations, setReclamations] = useState<Reclamation[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectionnee, setSelectionnee] = useState<Reclamation | null>(null);
  const [justificatifEnCours, setJustificatifEnCours] = useState<string | null>(null);

  async function ouvrirJustificatif(reclamation: Reclamation) {
    if (!reclamation.justificatif_storage_path) return;
    setJustificatifEnCours(reclamation.id);
    const { data, error } = await supabase.storage
      .from('justificatifs')
      .createSignedUrl(reclamation.justificatif_storage_path, 300);
    setJustificatifEnCours(null);

    if (error || !data?.signedUrl) {
      afficherNotification({ type: 'erreur', message: 'Impossible d’ouvrir le justificatif. Veuillez réessayer.' });
      return;
    }

    const lien = document.createElement('a');
    lien.href = data.signedUrl;
    lien.target = '_blank';
    lien.rel = 'noopener noreferrer';
    lien.click();
  }

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_reclamations' as any, {
      p_statut: filtre, p_limit: 100,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
    } else if ((data as any)?.success) {
      setReclamations(((data as any).reclamations || []) as Reclamation[]);
    }
    setLoading(false);
  }, [afficherNotification, filtre]);

  useEffect(() => { charger(); }, [charger]);

  return (
      <div className="space-y-4">

        <div className="flex gap-2">
          {(['PENDING', 'TREATED', 'TOUS'] as const).map(f => (
            <BoutonY2K key={f} size="sm" variant={filtre === f ? 'primary' : 'secondary'} onClick={() => setFiltre(f)}>
              {f === 'PENDING' ? 'En attente' : f === 'TREATED' ? 'Traitées' : 'Toutes'}
            </BoutonY2K>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>
        ) : reclamations.length === 0 ? (
          <EmptyState
            icone={<FileText />}
            mascotte={filtre === 'PENDING' ? 'happy' : 'empty'}
            titre={filtre === 'PENDING' ? 'Aucune réclamation à traiter' : 'Aucune réclamation'}
            description={filtre === 'PENDING' ? 'Toutes les réclamations en attente ont été traitées.' : undefined}
            variant={filtre === 'PENDING' ? 'success' : 'info'}
          />
        ) : (
          <div className="space-y-2">
            {reclamations.map(r => (
              <div key={r.id}
                className={`rounded-xl border p-4 ${r.statut === 'PENDING' && r.jours_attente > 7
                  ? 'border-destructive bg-destructive/5'
                  : r.statut === 'PENDING'
                  ? 'border-amber-300 bg-amber-50/40 dark:bg-amber-950/20'
                  : 'border-border bg-card'}`}>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-xs font-mono bg-muted px-1.5 py-0.5 rounded">{LIBELLES_EVENEMENT_TYPE[r.evenement_type] ?? r.evenement_type}</span>
                      <span className="font-semibold text-foreground">{libelleTypeEvenement(r.event_type_evenement)}</span>
                      <span className="font-mono text-destructive">{r.event_points} pts</span>
                      {r.statut === 'PENDING' && (
                        <BadgeY2K variant={r.jours_attente > 7 ? 'error' : 'warning'} size="sm">
                          {Math.round(r.jours_attente)}j d'attente
                        </BadgeY2K>
                      )}
                      {r.statut === 'TREATED' && r.decision_admin && (
                        <BadgeY2K
                          variant={r.decision_admin === 'ANNULER' ? 'success' : r.decision_admin === 'REDUIRE' ? 'info' : 'info'}
                          size="sm"
                        >
                          {LIBELLES_DECISION[r.decision_admin]}
                        </BadgeY2K>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      <strong>Événement :</strong> {r.event_motif}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">
                      <strong>Motif réclamation :</strong> {r.motif_categorie}
                    </p>
                    <p className="text-sm text-foreground mt-2 italic">« {r.texte_libre} »</p>
                    {r.justificatif_storage_path && (
                      <button
                        type="button"
                        onClick={() => ouvrirJustificatif(r)}
                        disabled={justificatifEnCours === r.id}
                        className="text-xs text-primary inline-flex items-center gap-1 mt-1 hover:underline disabled:opacity-50"
                      >
                        {justificatifEnCours === r.id
                          ? <Loader2 className="h-3 w-3 animate-spin" aria-hidden="true" />
                          : <FileText className="h-3 w-3" aria-hidden="true" />}
                        {justificatifEnCours === r.id ? 'Ouverture…' : 'Ouvrir le justificatif'}
                      </button>
                    )}
                    {r.motif_admin && (
                      <p className="text-xs mt-2 bg-muted/40 p-2 rounded">
                        <strong>Décision admin :</strong> {r.motif_admin}
                      </p>
                    )}
                    <p className="text-[10px] text-muted-foreground mt-2">
                      Créée {format(new Date(r.cree_le), "d MMM yyyy 'à' HH:mm", { locale: fr })}
                    </p>
                  </div>
                  {r.statut === 'PENDING' && (
                    <BoutonY2K variant="primary" size="sm" onClick={() => setSelectionnee(r)}>Traiter</BoutonY2K>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {selectionnee && (
          <ModaleDecision
            reclamation={selectionnee}
            onFermer={() => setSelectionnee(null)}
            onTraitee={() => { setSelectionnee(null); charger(); }}
          />
        )}
      </div>
  );
}

function ModaleDecision({ reclamation, onFermer, onTraitee }: {
  reclamation: Reclamation; onFermer: () => void; onTraitee: () => void;
}) {
  const { afficherNotification } = useNotification();
  const [decision, setDecision] = useState<'MAINTENIR' | 'REDUIRE' | 'ANNULER'>('MAINTENIR');
  const [pointsCorriges, setPointsCorriges] = useState<string>(Math.max(-5, Math.ceil(reclamation.event_points / 2)).toString());
  const [motifAdmin, setMotifAdmin] = useState('');
  const [loading, setLoading] = useState(false);
  const dialogueRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    dialogueRef.current?.focus();
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !loading) onFermer();
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [loading, onFermer]);

  async function soumettre() {
    if (motifAdmin.trim().length < 10) {
        afficherNotification({ type: 'erreur', message: 'Le motif doit contenir au moins 10 caractères.' });
      return;
    }
    if (decision === 'REDUIRE') {
      const pc = parseInt(pointsCorriges);
      if (isNaN(pc) || pc >= 0) {
        afficherNotification({ type: 'erreur', message: 'Points corrigés doivent être négatifs (ex: -5).' });
        return;
      }
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_admin_traiter_reclamation' as any, {
        p_reclamation_id: reclamation.id,
        p_decision: decision,
        p_points_corriges: decision === 'REDUIRE' ? parseInt(pointsCorriges) : null,
        p_motif_admin: motifAdmin.trim(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur' });
        return;
      }
      afficherNotification({ type: 'succes', message: 'Décision appliquée. Score recalculé + notif envoyée.' });
      onTraitee();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur réseau' });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={onFermer}>
      <div
        ref={dialogueRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="admin-reclamation-decision-title"
        tabIndex={-1}
        className="bg-card border border-border rounded-xl max-w-lg w-full p-6 space-y-4 outline-none"
        onClick={e => e.stopPropagation()}
      >
        <h2 id="admin-reclamation-decision-title" className="text-lg font-bold text-foreground">Décider la réclamation</h2>

        <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-1">
          <p className="font-semibold">{libelleTypeEvenement(reclamation.event_type_evenement)} <span className="font-mono text-destructive">({reclamation.event_points} pts)</span></p>
          <p>Catégorie du motif : <strong>{reclamation.motif_categorie}</strong></p>
          <p className="italic">« {reclamation.texte_libre} »</p>
        </div>

        <div className="space-y-2">
          <span className="text-xs font-medium block">Décision *</span>
          {[
            { v: 'MAINTENIR', l: 'MAINTENIR la pénalité (réclamation rejetée)', i: <XCircle className="h-4 w-4 text-muted-foreground" /> },
            { v: 'REDUIRE', l: 'RÉDUIRE la pénalité', i: <Edit3 className="h-4 w-4 text-blue-600" /> },
            { v: 'ANNULER', l: 'ANNULER complètement (événement neutralisé)', i: <CheckCircle className="h-4 w-4 text-emerald-600" /> },
          ].map(opt => (
            <label key={opt.v} className="flex items-center gap-2 cursor-pointer p-2 rounded hover:bg-muted">
              <input type="radio" checked={decision === opt.v} onChange={() => setDecision(opt.v as any)} />
              {opt.i}
              <span className="text-sm">{opt.l}</span>
            </label>
          ))}
        </div>

        {decision === 'REDUIRE' && (
          <label className="block">
            <span className="text-xs font-medium mb-1 block">Points corrigés (négatif, ex: -5)</span>
            <input type="number" max="-1" value={pointsCorriges} onChange={e => setPointsCorriges(e.target.value)} className="input-base" />
            <span className="text-[10px] text-muted-foreground">Original : {reclamation.event_points} pts</span>
          </label>
        )}

        <label className="block">
          <span className="text-xs font-medium mb-1 block">Motif de la décision * (minimum 10 caractères, visible par l'utilisateur)</span>
          <textarea value={motifAdmin} onChange={e => setMotifAdmin(e.target.value)} className="input-base" rows={3}
            placeholder="Ex: Certif médical fourni est conforme, justification valide..." />
        </label>

        <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs flex gap-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <p>La décision sera <strong>appliquée automatiquement</strong> à l'événement de score, le score sera recalculé et l'utilisateur recevra une notification par e-mail et push.</p>
        </div>

        <div className="flex gap-2">
          <BoutonY2K variant="secondary" size="md" onClick={onFermer} disabled={loading} className="flex-1">Annuler</BoutonY2K>
          <BoutonY2K variant="primary" size="md" onClick={soumettre} disabled={loading} loading={loading} className="flex-1">
            Appliquer la décision
          </BoutonY2K>
        </div>
      </div>
    </div>
  );
}

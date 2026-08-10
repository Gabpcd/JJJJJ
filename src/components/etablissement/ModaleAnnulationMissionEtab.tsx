import { useEffect, useState } from 'react';
import { Loader2, AlertCircle, AlertTriangle, FileText } from 'lucide-react';
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
  ouvert: boolean;
  onFermer: () => void;
  onAnnulee?: () => void;
  mission: {
    id: string;
    intitule: string;
    statut: string;
    debut_le: string;
    fin_le: string;
    duree_heures: number;
    taux_horaire_base: number;
    total_brut?: number | null;
    type_contrat_applique?: string | null;
    type_contrat_recherche?: string | null;
  };
  /** Nom du soignant si déjà assigné (affichage UI) */
  soignantNom?: string | null;
}

interface IndemniteCalc {
  montant: number;
  motif: string;
  base_calcul: string;
  type_contrat: string;
}

const MOTIFS = [
  { value: 'BESOIN_DISPARU', label: '🚫 Besoin disparu' },
  { value: 'BUDGET_REVU', label: '💰 Budget revu' },
  { value: 'REMPLACEMENT_INTERNE', label: '👥 Remplacement interne trouvé' },
  { value: 'CHANGEMENT_PLANNING', label: '📅 Changement de planning' },
  { value: 'CAS_FORCE_MAJEURE', label: '⚡ Cas de force majeure' },
  { value: 'AUTRE', label: '❓ Autre' },
];

/**
 * Modale d'annulation mission par l'établissement avec décomposition complète
 * des conséquences financières et score (Sprint 3.5 PR 5).
 *
 * Buckets affichés AVANT confirmation :
 *  1. OUVERTE  → libre, 0 pt, 0 €
 *  2. ACCEPTEE sans contrat signé → -3 pts, 0 €
 *  3. CDD signé avant pointage → -10 pts + indemnité L1243-8 (Code travail)
 *     formule : durée × taux × 1.10 (salaire + précarité 10%)
 *  4. Libéral signé avant pointage → -10 pts + clause pénale art. 1231-5 Code civil
 *     - < 24h : 50% du montant total
 *     - 24-48h : 30%
 *     - > 48h : 10%
 *  5. Après pointage → -20 pts + salaires/honoraires complets dus
 *
 * Appelle `fn_calculer_indemnite_annulation_etab` côté front pour pré-calcul,
 * puis `fn_annuler_mission_etab` côté serveur pour exécution.
 */
export function ModaleAnnulationMissionEtab({
  ouvert, onFermer, onAnnulee, mission, soignantNom,
}: Props) {
  const { afficherNotification } = useNotification();
  const [motif, setMotif] = useState('');
  const [texte, setTexte] = useState('');
  const [accepte, setAccepte] = useState(false);
  const [loading, setLoading] = useState(false);
  const [indemnite, setIndemnite] = useState<IndemniteCalc | null>(null);
  const [pointageEnCours, setPointageEnCours] = useState<boolean>(false);
  const [contratSigne, setContratSigne] = useState<boolean>(false);
  const [calculLoading, setCalculLoading] = useState(true);

  useEffect(() => {
    if (!ouvert) return;
    let cancelled = false;

    async function calculer() {
      setCalculLoading(true);
      // Détecte pointage existant
      const { data: pres } = await supabase
        .from('presences' as any)
        .select('id')
        .eq('mission_id', mission.id)
        .limit(1);
      const hasPresence = Array.isArray(pres) && pres.length > 0;

      // Détecte contrat signé
      const { data: contrat } = await supabase
        .from('contrats_mission' as any)
        .select('id, statut, type_contrat')
        .eq('mission_id', mission.id)
        .maybeSingle();
      const contratExiste = Boolean(contrat);
      // Un engagement financier n'est définitif que lorsque les deux parties
      // ont signé. Les états partiels restent visibles mais ne valent pas
      // contrat complet.
      const contratValide = Boolean(contrat && (contrat as any).statut === 'SIGNE_COMPLET');

      if (cancelled) return;
      setPointageEnCours(hasPresence);
      setContratSigne(contratValide);

      const typeContrat =
        (contrat as any)?.type_contrat ||
        mission.type_contrat_applique ||
        mission.type_contrat_recherche ||
        'CDD';
      const deltaMs = new Date(mission.debut_le).getTime() - Date.now();
      const deltaHours = Math.max(0, Math.floor(deltaMs / 3600_000));
      const interval = hasPresence ? '0 hours' : `${deltaHours} hours`;
      const montantTotal = mission.total_brut ?? (mission.duree_heures * mission.taux_horaire_base);

      // Appel helper IMMUTABLE pour pré-calcul (transparence)
      if (contratValide || hasPresence) {
        const { data } = await supabase.rpc('fn_calculer_indemnite_annulation_etab' as any, {
          p_type_contrat: typeContrat,
          p_montant_total: hasPresence ? montantTotal : montantTotal,
          p_duree_heures: mission.duree_heures,
          p_taux_horaire: mission.taux_horaire_base,
          p_delta_mission: interval,
        });
        if (!cancelled && data) setIndemnite(data as IndemniteCalc);
      } else {
        setIndemnite({ montant: 0, motif: 'aucune_indemnite', base_calcul: '', type_contrat: typeContrat });
      }
      // Note : si on ignore que le contrat existe mais n'est pas signé, on stocke quand même contratExiste pour bucket -3
      void contratExiste;

      if (!cancelled) setCalculLoading(false);
    }
    calculer();
    return () => { cancelled = true; };
  }, [ouvert, mission]);

  const bucket = determinerBucket(mission.statut, contratSigne, pointageEnCours);
  const indemniteMontant = indemnite?.montant ?? 0;
  const revueForceMajeure = motif === 'CAS_FORCE_MAJEURE' && mission.statut !== 'OUVERTE';

  async function confirmer() {
    if (!motif) {
      afficherNotification({ type: 'erreur', message: 'Sélectionnez un motif.' });
      return;
    }
    if (texte.trim().length < 10) {
      afficherNotification({ type: 'erreur', message: 'Texte libre obligatoire (min 10 caractères).' });
      return;
    }
    if (!accepte && bucket.points < 0) {
      afficherNotification({ type: 'erreur', message: 'Veuillez cocher la case de confirmation des conséquences.' });
      return;
    }
    setLoading(true);
    try {
      // Une force majeure alléguée nécessite une qualification humaine. On
      // ouvre une revue sans annuler ni appliquer de pénalité automatiquement.
      if (revueForceMajeure) {
        const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
          p_mission_id: mission.id,
          p_type_litige: 'AUTRE',
          p_motif: `Demande de revue avant annulation pour force majeure : ${texte.trim()}`,
        });
        if (error) throw error;
        const result = data as any;
        if (!result?.success) {
          afficherNotification({ type: 'erreur', message: result?.error || 'La demande de revue n’a pas pu être ouverte.' });
          return;
        }
        afficherNotification({
          type: 'succes',
          message: 'Demande de revue ouverte. La mission reste active et aucune pénalité n’est appliquée avant décision.',
        });
        onFermer();
        return;
      }
      const { data, error } = await supabase.rpc('fn_annuler_mission_etab' as any, {
        p_mission_id: mission.id,
        p_motif_categorie: motif,
        p_texte_libre: texte.trim(),
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        const code = result?.error_code;
        const message = result?.error || codeErreurFr(code) || 'Erreur lors de l\'annulation.';
        afficherNotification({ type: 'erreur', message });
        return;
      }
      const msg = result?.indemnite_montant > 0
        ? `Mission annulée. Indemnité de ${formatEur(result.indemnite_montant)} due au soignant.`
        : 'Mission annulée.';
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
    <DialogResponsive open={ouvert} onOpenChange={(o) => { if (!o && !loading) onFermer(); }}>
      <DialogResponsiveContent maxWidth="xl">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle>Annuler cette mission</DialogResponsiveTitle>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          {/* Récap mission */}
          <div className="rounded-lg bg-muted/40 p-3 text-xs space-y-0.5">
            <p className="font-semibold text-foreground">{mission.intitule}</p>
            {soignantNom && <p className="text-muted-foreground">Soignant : {soignantNom}</p>}
            <p className="text-muted-foreground">
              Du {new Date(mission.debut_le).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
              {' '}au{' '}
              {new Date(mission.fin_le).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
            </p>
            <p className="text-muted-foreground">
              {mission.duree_heures}h × {mission.taux_horaire_base.toFixed(2)} €/h = {formatEur(mission.total_brut ?? mission.duree_heures * mission.taux_horaire_base)} brut
            </p>
          </div>

          {/* Décomposition des conséquences */}
          {revueForceMajeure ? (
            <div className="rounded-xl border-2 border-info/40 bg-info/5 p-4 text-sm text-foreground">
              <p className="font-semibold">Revue avant toute annulation</p>
              <p className="text-xs text-muted-foreground mt-1">La mission reste active. Aucun score, aucune indemnité et aucun mouvement financier ne sont appliqués automatiquement pendant l'examen de la force majeure.</p>
            </div>
          ) : calculLoading ? (
            <div className="flex items-center justify-center py-6">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              <span className="ml-2 text-sm text-muted-foreground">Calcul des conséquences…</span>
            </div>
          ) : (
            <ConsequencesBlock bucket={bucket} indemniteMontant={indemniteMontant} indemnite={indemnite} />
          )}

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
            <span className="text-xs font-medium text-foreground mb-1 block">Explication détaillée * (min 10 caractères)</span>
            <textarea
              value={texte}
              onChange={(e) => setTexte(e.target.value)}
              className="input-base"
              rows={3}
              placeholder="Expliquez la situation : pourquoi annuler la mission ?"
            />
            <span className="text-[10px] text-muted-foreground">{texte.length} / 10+</span>
          </label>

          {/* Coche obligatoire si conséquences */}
          {bucket.points < 0 && (
            <label className="flex items-start gap-2 rounded-lg border border-border bg-background p-3 cursor-pointer">
              <input
                type="checkbox"
                checked={accepte}
                onChange={(e) => setAccepte(e.target.checked)}
                className="mt-1 h-4 w-4 rounded border-border"
                disabled={loading}
              />
              <span className="text-xs text-foreground">
                {revueForceMajeure
                  ? 'Je demande une revue de la force majeure. La mission restera active et aucune conséquence ne sera appliquée automatiquement avant décision.'
                  : <>J'ai compris les conséquences financières {indemniteMontant > 0 ? `(${formatEur(indemniteMontant)} à traiter au bénéfice du soignant)` : ''} et l'impact sur mon score établissement ({bucket.points} pts).</>}
              </span>
            </label>
          )}

          <div className="rounded-lg bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 flex gap-2">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <p>{revueForceMajeure
              ? 'La force majeure sera examinée avant toute annulation, pénalité ou indemnité. Le dossier reste modifiable pendant la revue.'
              : 'Le soignant sera notifié immédiatement (push + email). L’impact sur votre score établissement est contestable depuis votre page score.'}</p>
          </div>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button onClick={onFermer} disabled={loading} className="btn-secondary min-h-[44px] disabled:opacity-50">
            Garder la mission
          </button>
          <button
            onClick={confirmer}
            disabled={loading || calculLoading || !motif || texte.trim().length < 10 || (bucket.points < 0 && !accepte)}
            className="btn-primary min-h-[44px] disabled:opacity-50 inline-flex items-center justify-center gap-2"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            {revueForceMajeure ? 'Demander la revue' : 'Confirmer l’annulation'}
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

interface Bucket {
  code: 'OUVERTE' | 'ACCEPTEE_SANS_CONTRAT' | 'CDD_SIGNE' | 'LIBERAL_SIGNE' | 'APRES_POINTAGE';
  points: number;
  titre: string;
}

function determinerBucket(statut: string, contratSigne: boolean, pointageEnCours: boolean): Bucket {
  if (pointageEnCours) {
    return { code: 'APRES_POINTAGE', points: -20, titre: 'Annulation après pointage' };
  }
  if (statut === 'OUVERTE') {
    return { code: 'OUVERTE', points: 0, titre: 'Mission OUVERTE — annulation libre' };
  }
  if (!contratSigne) {
    return { code: 'ACCEPTEE_SANS_CONTRAT', points: -3, titre: 'Mission acceptée, contrat non encore signé' };
  }
  // contratSigne = true
  return { code: 'CDD_SIGNE', points: -10, titre: 'Contrat signé avant pointage' };
}

function ConsequencesBlock({ bucket, indemniteMontant, indemnite }: { bucket: Bucket; indemniteMontant: number; indemnite: IndemniteCalc | null }) {
  const styleBucket = bucket.points <= -20
    ? 'border-destructive/50 bg-destructive/5 text-destructive'
    : bucket.points <= -10
      ? 'border-orange-500/40 bg-orange-50 dark:bg-orange-950/20 text-orange-700 dark:text-orange-300'
      : bucket.points < 0
        ? 'border-warning/40 bg-warning/5 text-warning'
        : 'border-success/40 bg-success/5 text-success';

  const isLiberal = indemnite?.type_contrat === 'REMPLACEMENT_LIBERAL' || indemnite?.type_contrat === 'LIBERAL';
  const articleLoi = bucket.code === 'CDD_SIGNE' && !isLiberal
    ? 'art. L1243-4 et L1243-8 Code du travail'
    : isLiberal
      ? 'art. 1231-5 Code civil (clause pénale)'
      : null;

  return (
    <div className={`rounded-xl border-2 p-4 space-y-2 ${styleBucket}`}>
      <div className="flex items-center gap-2 font-semibold text-sm">
        {bucket.points < 0 ? <AlertTriangle className="h-4 w-4" /> : <FileText className="h-4 w-4" />}
        <span>{bucket.titre}</span>
      </div>

      <div className="space-y-1.5 text-xs">
        {bucket.code === 'OUVERTE' && (
          <p>Aucun soignant n'a accepté cette mission. L'annulation est libre, sans pénalité ni indemnité.</p>
        )}
        {bucket.code === 'ACCEPTEE_SANS_CONTRAT' && (
          <>
            <p>Le soignant a accepté mais aucun contrat n'a été signé. Pas d'indemnité due.</p>
            <p>Impact score établissement : <strong>{bucket.points} pts</strong> (contestable).</p>
          </>
        )}
        {bucket.code === 'CDD_SIGNE' && !isLiberal && (
          <>
            <p>Le CDD est signé. Une rupture anticipée à l'initiative de l'employeur peut ouvrir droit au minimum aux rémunérations jusqu'au terme, ainsi qu'à l'indemnité de fin de contrat (art. L1243-4 et L1243-8 du Code du travail) :</p>
            <p className="font-mono bg-background/50 rounded px-2 py-1">
              {indemnite?.base_calcul}
            </p>
            <p>Indemnité à verser au soignant : <strong>{formatEur(indemniteMontant)}</strong></p>
            <p>Impact score établissement : <strong>{bucket.points} pts</strong> (contestable).</p>
          </>
        )}
        {bucket.code === 'CDD_SIGNE' && isLiberal && (
          <>
            <p>Le contrat de remplacement libéral est signé. L'annulation déclenche la clause pénale prévue par l'article 1231-5 du Code civil :</p>
            <p className="font-mono bg-background/50 rounded px-2 py-1">
              {indemnite?.base_calcul}
            </p>
            <p>Clause pénale à verser au soignant : <strong>{formatEur(indemniteMontant)}</strong></p>
            <p>Impact score établissement : <strong>{bucket.points} pts</strong> (contestable).</p>
          </>
        )}
        {bucket.code === 'APRES_POINTAGE' && (
          <>
            <p>Le soignant a déjà pointé son arrivée. La mission est considérée comme effectuée.</p>
            <p>Salaires/honoraires complets dus : <strong>{formatEur(indemniteMontant)}</strong></p>
            <p>Impact score établissement : <strong>{bucket.points} pts</strong> (contestable).</p>
          </>
        )}

        {indemniteMontant > 0 && (
          <p className="text-[11px] italic mt-2">
            Cette somme est enregistrée comme due. Pour un CDD, l'établissement doit la traiter en paie ; pour une mission libérale, il doit la régler selon le contrat et conserver la preuve. Jolene ne déclare pas un virement tant qu'il n'est pas réellement exécuté.
            {articleLoi && ` Cadre légal : ${articleLoi}.`}
          </p>
        )}
      </div>
    </div>
  );
}

function codeErreurFr(code?: string): string | null {
  if (!code) return null;
  switch (code) {
    case 'NON_AUTHENTIFIE': return 'Session expirée, reconnectez-vous.';
    case 'NON_AUTORISE': return 'Vous n\'êtes pas autorisé(e) à annuler cette mission.';
    case 'MOTIF_INVALIDE': return 'Motif invalide.';
    case 'MISSION_INTROUVABLE': return 'Mission introuvable.';
    case 'STATUT_INVALIDE': return 'La mission ne peut plus être annulée dans son état actuel.';
    case 'TEXTE_REQUIS': return 'Veuillez expliquer le motif (min 10 caractères).';
    default: return null;
  }
}

function formatEur(v: number): string {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 }).format(v ?? 0);
}

import { useEffect, useState } from 'react';
import { ChevronLeft, ChevronRight, Loader2, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { extraireMessageErreur } from '@/lib/erreurs';
import { chargerFacturesContestables, type FactureContestable } from '@/lib/facturesContestables';
import { useNotification } from '@/contexts/NotificationContext';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

type TypeLitige = 'PAIEMENT' | 'CONDITIONS' | 'COMPORTEMENT' | 'AUTRE';

interface Props {
  missionId: string;
  missionIntitule?: string;
  factureHonorairesId?: string;
  initialType?: TypeLitige;
  onClose: () => void;
  onSuccess?: () => void;
}

const TYPES: { value: TypeLitige; label: string; description: string }[] = [
  { value: 'PAIEMENT', label: '💰 Paiement', description: 'Montant erroné, retard de paiement, heures non comptées…' },
  { value: 'CONDITIONS', label: '⏱️ Conditions de travail', description: 'Horaires non respectés, poste différent, matériel manquant…' },
  { value: 'COMPORTEMENT', label: '⚠️ Comportement', description: "Conflit avec l'équipe, irrespect, comportement inapproprié…" },
  { value: 'AUTRE', label: '📝 Autre', description: 'Autre problème lié à la mission' },
];

/**
 * Wizard 3 étapes pour ouvrir un litige depuis l'historique soignant.
 *
 * Sprint 6 PR 2 — Fix P1-2 audit Sprint 5.
 *
 * Étape 1 : type de litige (4 catégories structurées)
 * Étape 2 : détail du problème (min 20 chars)
 * Étape 3 : récap + confirmation (justificatifs via messagerie litige post-création)
 *
 * Sprint 8 ter-E PR 5 — Migration vers DialogResponsive (fullscreen mobile + nav sticky).
 */
export function WizardOuvertureLitige({
  missionId,
  missionIntitule,
  factureHonorairesId,
  initialType,
  onClose,
  onSuccess,
}: Props) {
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<1 | 2 | 3>(1);
  const [typeLitige, setTypeLitige] = useState<TypeLitige | null>(initialType ?? null);
  const [detail, setDetail] = useState('');
  const [erreur, setErreur] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [factures, setFactures] = useState<FactureContestable[]>([]);
  const [factureSelectionnee, setFactureSelectionnee] = useState(factureHonorairesId ?? '');
  const [lecture, setLecture] = useState({ cle: '', statut: 'chargement' as 'chargement' | 'ok' | 'erreur' });
  const [tentativeLecture, setTentativeLecture] = useState(0);
  const cleLecture = `${missionId}:${factureHonorairesId ?? ''}:${tentativeLecture}`;
  const statutLecture = lecture.cle === cleLecture ? lecture.statut : 'chargement';
  const lectureRequise = typeLitige === 'PAIEMENT' || Boolean(factureHonorairesId);

  useEffect(() => {
    let actif = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    setLecture({ cle: cleLecture, statut: 'chargement' });
    setFactures([]);
    setFactureSelectionnee('');
    void (async () => {
      try {
        const options = await chargerFacturesContestables(missionId, factureHonorairesId, controller.signal);
        if (!actif) return;
        setFactures(options);
        setFactureSelectionnee(factureHonorairesId ?? (options.length === 1 ? options[0].id : ''));
        setLecture({ cle: cleLecture, statut: 'ok' });
      } catch {
        if (actif) setLecture({ cle: cleLecture, statut: 'erreur' });
      } finally {
        clearTimeout(timeout);
      }
    })();
    return () => { actif = false; clearTimeout(timeout); controller.abort(); };
  }, [missionId, factureHonorairesId, cleLecture]);

  const factureRequise = typeLitige === 'PAIEMENT' && factures.length > 1;
  const pieceVerifiee = !lectureRequise || (statutLecture === 'ok'
    && (!factureRequise || Boolean(factureSelectionnee))
    && (!factureHonorairesId || factures.some(f => f.id === factureSelectionnee)));
  const peutAvancer1 = typeLitige !== null && pieceVerifiee;
  const peutAvancer2 = detail.trim().length >= 20;

  async function creerLitige() {
    if (creating || !typeLitige || !pieceVerifiee || detail.trim().length < 20) return;
    setErreur(null);

    const motifStructure = `[${typeLitige}] ${detail.trim()}`;

    setCreating(true);
    const typeServeur = typeLitige === 'PAIEMENT'
      ? 'DESACCORD_MONTANT_FACTURE'
      : typeLitige === 'CONDITIONS'
        ? 'CONDITIONS_MISSION_NON_RESPECTEES'
        : 'AUTRE';
    const params: Record<string, unknown> = {
      p_mission_id: missionId,
      p_type_litige: typeServeur,
      p_motif: motifStructure,
    };
    // Une demande de revue hors délai reste rattachée au document exact : le
    // passage en catégorie AUTRE ne doit jamais faire perdre le périmètre.
    if (statutLecture === 'ok' && factureSelectionnee
      && factures.some(facture => facture.id === factureSelectionnee)) {
      params.p_facture_id = factureSelectionnee;
    }
    try {
      const { data, error } = await supabase.rpc(
        'fn_ouvrir_litige_rate_limited' as any,
        params,
      );
      if (error) throw error;
      if ((data as any)?.error) {
        setErreur((data as any).error);
        return;
      }
      if ((data as any)?.success !== true || typeof (data as any)?.litige_id !== 'string' || !(data as any).litige_id) {
        setErreur('La création du litige n’a pas pu être confirmée. Réessayez.');
        return;
      }

      afficherNotification({ type: 'succes', message: 'Litige ouvert. Vous pouvez suivre son traitement dans l’app.' });
      onSuccess?.();
      onClose();
    } catch (error) {
      setErreur(extraireMessageErreur(error));
    } finally {
      setCreating(false);
    }
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !creating) onClose(); }}>
      <DialogResponsiveContent maxWidth="lg">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle className="inline-flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-warning" />
            Signaler un problème
          </DialogResponsiveTitle>
          <DialogResponsiveDescription className="sr-only">
            Choisissez le type de problème, décrivez-le puis confirmez votre demande.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-4">
          {missionIntitule && (
            <div className="rounded-lg bg-muted/40 p-3 text-xs">
              <p className="text-muted-foreground">Mission concernée :</p>
              <p className="font-semibold text-foreground">{missionIntitule}</p>
            </div>
          )}

          <ol className="flex items-center gap-2 text-xs" aria-label="Progression wizard">
            {[1, 2, 3].map((n) => (
              <li key={n} className={`flex-1 h-1.5 rounded-full ${etape >= n ? 'bg-primary' : 'bg-muted'}`} />
            ))}
          </ol>
          <p className="text-[11px] text-muted-foreground -mt-2">Étape {etape} / 3</p>

          {etape === 1 && (
            <div className="space-y-3">
              <p className="text-sm font-medium text-foreground">Quel type de problème ?</p>
              <div className="space-y-2">
                {TYPES.map((t) => (
                  <label
                    key={t.value}
                    className={`flex items-start gap-2 rounded-lg border-2 p-3 cursor-pointer transition-colors min-h-[44px] ${
                      typeLitige === t.value
                        ? 'border-primary bg-primary/5'
                        : 'border-border bg-background hover:border-primary/40'
                    }`}
                  >
                    <input
                      type="radio"
                      name="type-litige"
                      value={t.value}
                      checked={typeLitige === t.value}
                      onChange={() => setTypeLitige(t.value)}
                      className="mt-1"
                    />
                    <div>
                      <p className="text-sm font-medium text-foreground">{t.label}</p>
                      <p className="text-[11px] text-muted-foreground">{t.description}</p>
                    </div>
                  </label>
                ))}
              </div>
              {lectureRequise && statutLecture === 'chargement' && (
                <p role="status" className="text-sm text-muted-foreground">Chargement de la facture concernée…</p>
              )}
              {lectureRequise && statutLecture === 'erreur' && (
                <div role="alert" className="rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm">
                  <p>Impossible de vérifier la facture concernée. Réessayez avant de continuer.</p>
                  <button type="button" className="btn-secondary mt-2 min-h-[44px]" onClick={() => setTentativeLecture(n => n + 1)}>
                    Réessayer le chargement des factures
                  </button>
                </div>
              )}
              {lectureRequise && statutLecture === 'ok' && factures.length > 0 && (
                <div className="rounded-lg border border-border bg-muted/20 p-3">
                  <label htmlFor="facture-contestee" className="mb-1 block text-sm font-medium">
                    Facture concernée{factures.length > 1 ? ' *' : ''}
                  </label>
                  <select
                    id="facture-contestee"
                    className="input-base min-h-[44px] w-full text-sm"
                    value={factureSelectionnee}
                    disabled={Boolean(factureHonorairesId)}
                    onChange={(event) => setFactureSelectionnee(event.target.value)}
                  >
                    {factures.length > 1 && <option value="">Choisir la période exacte…</option>}
                    {factures.map((facture) => (
                      <option key={facture.id} value={facture.id}>
                        {facture.numero_facture} · {facture.periode_debut ?? '—'} → {facture.periode_fin ?? '—'} · {Number(facture.montant_ttc).toFixed(2)} €
                      </option>
                    ))}
                  </select>
                  <p className="mt-1 text-[11px] text-muted-foreground">
                    Votre demande reste rattachée à cette facture. Les autres périodes ne sont pas concernées.
                  </p>
                </div>
              )}
            </div>
          )}

          {etape === 2 && (
            <div className="space-y-2">
              <label htmlFor="wizard-litige-detail" className="block text-sm font-medium text-foreground">
                Décrivez précisément le problème
              </label>
              <p className="text-[11px] text-muted-foreground">
                Soyez factuel : dates, horaires, montants, faits observés. Vous pourrez ajouter des pièces
                justificatives depuis le fil de discussion une fois le litige ouvert.
              </p>
              <textarea
                id="wizard-litige-detail"
                value={detail}
                onChange={(e) => setDetail(e.target.value)}
                rows={6}
                className="input-base font-normal text-sm"
                placeholder="Le 15 mai, j'ai pointé à 7h00 mais le décompte affiche 8h. La différence (1h × 25€) n'a pas été payée…"
                disabled={creating || !pieceVerifiee}
                minLength={20}
                maxLength={2000}
              />
              <p className="text-[10px] text-muted-foreground text-right">
                {detail.length} / 2000 caractères (min 20)
              </p>
            </div>
          )}

          {etape === 3 && (
            <div className="space-y-3">
              <p className="text-sm font-medium text-foreground">Récapitulatif</p>
              <div className="rounded-lg border border-border bg-muted/30 p-3 space-y-2 text-sm">
                <div>
                  <p className="text-[11px] uppercase text-muted-foreground">Type</p>
                  <p className="font-medium">{TYPES.find((t) => t.value === typeLitige)?.label}</p>
                </div>
                <div>
                  <p className="text-[11px] uppercase text-muted-foreground">Détail</p>
                  <p className="whitespace-pre-wrap text-xs">{detail.trim()}</p>
                </div>
                {statutLecture === 'ok' && factures.some(facture => facture.id === factureSelectionnee) && (
                  <div>
                    <p className="text-[11px] uppercase text-muted-foreground">Facture ciblée</p>
                    <p className="text-xs font-medium">
                      {factures.find((facture) => facture.id === factureSelectionnee)?.numero_facture
                        ?? factureSelectionnee}
                    </p>
                  </div>
                )}
              </div>
              <div className="rounded-lg bg-info/5 border border-info/30 p-3 text-[11px] text-foreground">
                <p className="font-medium mb-1">Ce qui se passe après confirmation :</p>
                <ul className="list-disc list-inside space-y-0.5 text-muted-foreground">
                  <li>Le suivi du litige est disponible dans l’app.</li>
                  <li>Un fil de discussion s'ouvre pour échanger et joindre des documents</li>
                  <li>L'admin Jolene peut intervenir en médiation après 72h sans accord</li>
                  <li>Aucune sanction automatique : tout est discutable</li>
                </ul>
              </div>
            </div>
          )}
        </DialogResponsiveBody>
        <DialogResponsiveFooter className="flex-col sm:flex-col">
          {erreur && (
            <p role="alert" className="w-full rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
              {erreur}
            </p>
          )}
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-between">
            {etape > 1 ? (
              <button
                type="button"
                onClick={() => setEtape((etape - 1) as 1 | 2)}
                disabled={creating}
                className="btn-secondary text-sm inline-flex items-center justify-center gap-1 min-h-[44px] disabled:opacity-50"
              >
                <ChevronLeft className="h-4 w-4" /> Précédent
              </button>
            ) : <div />}
            {etape === 1 && (
              <button
                type="button"
                onClick={() => setEtape(2)}
                disabled={!peutAvancer1}
                className="btn-primary text-sm inline-flex items-center justify-center gap-1 min-h-[44px] disabled:opacity-50"
              >
                Suivant <ChevronRight className="h-4 w-4" />
              </button>
            )}
            {etape === 2 && (
              <button
                type="button"
                onClick={() => setEtape(3)}
                disabled={!peutAvancer2 || !pieceVerifiee}
                className="btn-primary text-sm inline-flex items-center justify-center gap-1 min-h-[44px] disabled:opacity-50"
              >
                Suivant <ChevronRight className="h-4 w-4" />
              </button>
            )}
            {etape === 3 && (
              <button
                type="button"
                onClick={creerLitige}
                disabled={creating || !pieceVerifiee}
                className="btn-primary text-sm inline-flex items-center justify-center gap-2 min-h-[44px] disabled:opacity-50"
              >
                {creating && <Loader2 className="h-4 w-4 animate-spin" />}
                Confirmer l'ouverture du litige
              </button>
            )}
          </div>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

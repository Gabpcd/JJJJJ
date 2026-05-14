import { useState } from 'react';
import { ChevronLeft, ChevronRight, Loader2, AlertTriangle } from 'lucide-react';
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
  missionId: string;
  missionIntitule?: string;
  onClose: () => void;
  onSuccess?: () => void;
}

type TypeLitige = 'PAIEMENT' | 'CONDITIONS' | 'COMPORTEMENT' | 'AUTRE';

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
export function WizardOuvertureLitige({ missionId, missionIntitule, onClose, onSuccess }: Props) {
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<1 | 2 | 3>(1);
  const [typeLitige, setTypeLitige] = useState<TypeLitige | null>(null);
  const [detail, setDetail] = useState('');
  const [creating, setCreating] = useState(false);

  const peutAvancer1 = typeLitige !== null;
  const peutAvancer2 = detail.trim().length >= 20;

  async function creerLitige() {
    if (!typeLitige || detail.trim().length < 20) return;

    const motifStructure = `[${typeLitige}] ${detail.trim()}`;

    setCreating(true);
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: missionId,
      p_motif: motifStructure,
    });
    setCreating(false);

    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      return;
    }
    if ((data as any)?.error) {
      afficherNotification({ type: 'erreur', message: (data as any).error });
      return;
    }

    afficherNotification({ type: 'succes', message: 'Litige ouvert. L\'établissement et l\'admin Jolene ont été notifiés.' });
    onSuccess?.();
    onClose();
  }

  return (
    <DialogResponsive open={true} onOpenChange={(o) => { if (!o && !creating) onClose(); }}>
      <DialogResponsiveContent maxWidth="lg" aria-labelledby="wizard-litige-titre">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle id="wizard-litige-titre" className="inline-flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-warning" />
            Signaler un problème
          </DialogResponsiveTitle>
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
                disabled={creating}
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
              </div>
              <div className="rounded-lg bg-info/5 border border-info/30 p-3 text-[11px] text-foreground">
                <p className="font-medium mb-1">Ce qui se passe après confirmation :</p>
                <ul className="list-disc list-inside space-y-0.5 text-muted-foreground">
                  <li>L'établissement reçoit une notification + email immédiate</li>
                  <li>Un fil de discussion s'ouvre pour échanger et joindre des documents</li>
                  <li>L'admin Jolene peut intervenir en médiation après 72h sans accord</li>
                  <li>Aucune sanction automatique : tout est discutable</li>
                </ul>
              </div>
            </div>
          )}
        </DialogResponsiveBody>
        <DialogResponsiveFooter className="sm:justify-between">
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
              disabled={!peutAvancer2}
              className="btn-primary text-sm inline-flex items-center justify-center gap-1 min-h-[44px] disabled:opacity-50"
            >
              Suivant <ChevronRight className="h-4 w-4" />
            </button>
          )}
          {etape === 3 && (
            <button
              type="button"
              onClick={creerLitige}
              disabled={creating}
              className="btn-primary text-sm inline-flex items-center justify-center gap-2 min-h-[44px] disabled:opacity-50"
            >
              {creating && <Loader2 className="h-4 w-4 animate-spin" />}
              Confirmer l'ouverture du litige
            </button>
          )}
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

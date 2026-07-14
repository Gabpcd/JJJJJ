import React, { useMemo, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { Info, AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { toast } from 'sonner';
import { LitigesSimilairesPanel } from './LitigesSimilairesPanel';
import {
  ACTIONS_FINANCIERES,
  EN_FAVEUR_DE,
  LABELS_ACTION_FINANCIERE,
  LABELS_EN_FAVEUR_DE,
  type ActionFinanciere,
  type EnFaveurDe,
  type LitigeEnrichi,
} from './types';

type Props = {
  litige: LitigeEnrichi | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onResolved?: () => void;
};

type ResolutionResult = {
  ok?: boolean;
  error?: string;
  litige_id?: string;
  action_financiere?: ActionFinanciere;
  nouvelle_facture_id?: string | null;
  avoir_id?: string | null;
  mode_remboursement?: string | null;
  regularisation_sociale_requise?: boolean;
  regen_pdf_request_ids?: string[];
  [key: string]: unknown;
};

const LABELS_TYPE_ACCORD: Record<string, string> = {
  MODIFICATION_HORAIRES: 'Correction des horaires',
  MODIFICATION_MONTANT: 'Ajustement du montant total',
  MIXTE: 'Correction des horaires et du montant',
  ANNULATION_TOTALE: 'Annulation totale',
  COMPENSATION_PARTIELLE: 'Compensation partielle',
};

function formatDateAccord(value: unknown): string | null {
  if (typeof value !== 'string' || !value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('fr-FR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });
}

export function LitigeResolutionModal({
  litige,
  open,
  onOpenChange,
  onResolved,
}: Props) {
  const [resolutionText, setResolutionText] = useState('');
  const [enFaveurDe, setEnFaveurDe] = useState<EnFaveurDe | ''>('');
  const [ajusterHeures, setAjusterHeures] = useState('');
  const [ajusterTaux, setAjusterTaux] = useState('');
  const [actionFinanciere, setActionFinanciere] = useState<ActionFinanciere>('AUTO');
  const [submitting, setSubmitting] = useState(false);
  const [resultat, setResultat] = useState<ResolutionResult | null>(null);

  const heuresNum = useMemo(
    () => (ajusterHeures ? Number.parseFloat(ajusterHeures) : null),
    [ajusterHeures],
  );
  const tauxNum = useMemo(
    () => (ajusterTaux ? Number.parseFloat(ajusterTaux) : null),
    [ajusterTaux],
  );
  const heuresInvalides =
    heuresNum != null &&
    (!Number.isFinite(heuresNum) || heuresNum <= 0 || heuresNum > 168);
  const tauxInvalide =
    tauxNum != null &&
    (!Number.isFinite(tauxNum) || tauxNum < 0.01 || tauxNum > 1000);

  const preview = useMemo(() => {
    if (!litige) return null;
    const messages: string[] = [];
    if (heuresNum != null && !Number.isNaN(heuresNum)) {
      messages.push(
        `Heures → ${heuresNum} h (recalcul montant facture en fonction).`,
      );
    }
    if (tauxNum != null && !Number.isNaN(tauxNum)) {
      messages.push(`Taux horaire → ${tauxNum} €/h.`);
    }
    if (messages.length === 0) {
      messages.push('Aucun ajustement financier — clôture litige uniquement.');
    }
    switch (actionFinanciere) {
      case 'AUTO':
        messages.push(
          'Action financière : AUTO → le serveur choisit selon le statut de la facture (BROUILLON / ÉMISE ou EN RETARD / PAYÉE).',
        );
        break;
      case 'RECALCUL':
        messages.push(
          'Action financière : RECALCUL → facture BROUILLON modifiée en place (disponible immédiatement).',
        );
        break;
      case 'ANNULER_REEMETTRE':
        messages.push(
          'Action financière : ANNULER + réémettre → une nouvelle facture remplace l’actuelle (ÉMISE ou EN RETARD).',
        );
        break;
      case 'AVOIR':
        messages.push(
          'Action financière : AVOIR → un avoir partiel est émis sur une facture payée, uniquement pour une correction à la baisse.',
        );
        break;
    }
    return messages;
  }, [litige, heuresNum, tauxNum, actionFinanciere]);

  const disclaimerURSSAF = heuresNum != null && heuresNum > 0;
  const accord = litige?.statut === 'REVUE_ADMIN'
    ? litige.payload_modifications
    : null;
  const accordModifications = accord?.modifications ?? {};
  const accordArrivee = formatDateAccord(
    accordModifications.pointage_arrivee_le,
  );
  const accordDepart = formatDateAccord(
    accordModifications.pointage_depart_le,
  );

  const reset = () => {
    setResolutionText('');
    setEnFaveurDe('');
    setAjusterHeures('');
    setAjusterTaux('');
    setActionFinanciere('AUTO');
    setResultat(null);
  };

  const handleClose = (nextOpen: boolean) => {
    if (!nextOpen) reset();
    onOpenChange(nextOpen);
  };

  const submit = async () => {
    if (!litige) return;
    if (!resolutionText.trim() || resolutionText.trim().length < 10) {
      toast.error('La résolution doit contenir au moins 10 caractères.');
      return;
    }
    if (!enFaveurDe) {
      toast.error('Veuillez choisir en faveur de qui trancher.');
      return;
    }
    if (heuresInvalides) {
      toast.error('Les heures doivent être strictement positives et limitées à 168 h.');
      return;
    }
    if (tauxInvalide) {
      toast.error('Le taux doit être strictement positif et limité à 1 000 €.');
      return;
    }

    setSubmitting(true);
    setResultat(null);

    const payload: Record<string, unknown> = {
      p_litige_id: litige.id,
      p_resolution: resolutionText.trim(),
      p_en_faveur_de: enFaveurDe,
      p_ajuster_heures: heuresNum,
      p_ajuster_taux: tauxNum,
      p_action_financiere: actionFinanciere,
    };

    const { data, error } = await supabase.rpc(
      'fn_admin_resoudre_litige' as any,
      payload,
    );

    if (error) {
      logger.error('fn_admin_resoudre_litige error', error);
      toast.error(error.message || 'Erreur lors de la résolution.');
      setSubmitting(false);
      return;
    }

    const result = data as ResolutionResult | null;
    if (result?.error) {
      toast.error(result.error);
      setResultat(result);
      setSubmitting(false);
      return;
    }

    toast.success('Litige résolu avec succès.');
    setResultat(result);
    setSubmitting(false);
    onResolved?.();
  };

  if (!litige) return null;

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-h-[92vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Résoudre le litige</DialogTitle>
          <DialogDescription>
            {litige.motif} — ouvert le{' '}
            {new Date(litige.cree_le).toLocaleDateString('fr-FR')}
          </DialogDescription>
        </DialogHeader>

        <TooltipProvider delayDuration={200}>
          <div className="space-y-4">
            <LitigesSimilairesPanel litigeId={litige.id} />
            {accord && (
              <div
                className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-950"
                data-testid="accord-parties-reference"
              >
                <p className="font-semibold">
                  Accord exact accepté par les deux parties
                </p>
                <p className="mt-1 text-amber-800">
                  Le serveur appliquera exactement cette référence si les champs
                  ci-dessous restent vides. Toute valeur différente constituera
                  une décision admin de remplacement auditée.
                </p>
                <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
                  <dt className="font-medium">Type</dt>
                  <dd>{LABELS_TYPE_ACCORD[accord.type] ?? accord.type}</dd>
                  {accordArrivee && (
                    <>
                      <dt className="font-medium">Arrivée</dt>
                      <dd>{accordArrivee}</dd>
                    </>
                  )}
                  {accordDepart && (
                    <>
                      <dt className="font-medium">Départ</dt>
                      <dd>{accordDepart}</dd>
                    </>
                  )}
                  {typeof accordModifications.montant_total_corrige === 'number' && (
                    <>
                      <dt className="font-medium">Montant convenu</dt>
                      <dd>{accordModifications.montant_total_corrige} € TTC</dd>
                    </>
                  )}
                  {typeof accordModifications.pourcentage_compensation === 'number' && (
                    <>
                      <dt className="font-medium">Compensation</dt>
                      <dd>{accordModifications.pourcentage_compensation} %</dd>
                    </>
                  )}
                  {typeof accordModifications.motif_annulation === 'string' && (
                    <>
                      <dt className="font-medium">Motif</dt>
                      <dd>{accordModifications.motif_annulation}</dd>
                    </>
                  )}
                  <dt className="font-medium">Justification</dt>
                  <dd>{accord.justification}</dd>
                </dl>
              </div>
            )}
            <div>
              <Label className="mb-1.5 block">Résolution *</Label>
              <Textarea
                value={resolutionText}
                onChange={(e) => setResolutionText(e.target.value)}
                placeholder="Expliquez la décision prise et son fondement..."
                rows={3}
                aria-label="Résolution"
              />
              <p className="mt-1 text-[11px] text-muted-foreground">
                Minimum 10 caractères.
              </p>
            </div>

            <div>
              <Label className="mb-1.5 block">En faveur de *</Label>
              <Select
                value={enFaveurDe}
                onValueChange={(v) => setEnFaveurDe(v as EnFaveurDe)}
              >
                <SelectTrigger aria-label="En faveur de">
                  <SelectValue placeholder="Choisir..." />
                </SelectTrigger>
                <SelectContent>
                  {EN_FAVEUR_DE.map((v) => (
                    <SelectItem key={v} value={v}>
                      {LABELS_EN_FAVEUR_DE[v]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <div className="mb-1.5 flex items-center gap-1">
                  <Label>Ajuster les heures</Label>
                  {disclaimerURSSAF && (
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <button
                          type="button"
                          aria-label="Disclaimer URSSAF/Carpimko"
                          className="text-warning"
                          data-testid="urssaf-disclaimer"
                        >
                          <AlertTriangle className="h-3.5 w-3.5" />
                        </button>
                      </TooltipTrigger>
                      <TooltipContent className="max-w-xs text-xs">
                        Ajuster les heures à la hausse déclenche une
                        régularisation sociale URSSAF / Carpimko côté soignant
                        libéral. Un email{' '}
                        <code>REGULARISATION_SOCIALE_REQUISE</code> sera
                        poussé.
                      </TooltipContent>
                    </Tooltip>
                  )}
                </div>
                <Input
                  type="number"
                  step="0.25"
                  min="0.01"
                  max="168"
                  value={ajusterHeures}
                  onChange={(e) => setAjusterHeures(e.target.value)}
                  placeholder="Heures réelles"
                  aria-label="Ajuster les heures"
                />
              </div>
              <div>
                <Label className="mb-1.5 block">Ajuster le taux (€/h)</Label>
                <Input
                  type="number"
                  step="0.01"
                  min="0.01"
                  max="1000"
                  value={ajusterTaux}
                  onChange={(e) => setAjusterTaux(e.target.value)}
                  placeholder="Nouveau taux"
                  aria-label="Ajuster le taux"
                />
              </div>
            </div>

            <div>
              <div className="mb-1.5 flex items-center gap-1.5">
                <Label>Action financière</Label>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      type="button"
                      aria-label="Info action financière"
                      className="text-muted-foreground"
                    >
                      <Info className="h-3.5 w-3.5" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent className="max-w-xs text-xs">
                    Détermine comment l'ajustement financier est répercuté
                    comptablement. <strong>AUTO</strong> est sûr par défaut.
                  </TooltipContent>
                </Tooltip>
              </div>
              <Select
                value={actionFinanciere}
                onValueChange={(v) => setActionFinanciere(v as ActionFinanciere)}
              >
                <SelectTrigger aria-label="Action financière">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ACTIONS_FINANCIERES.map((a) => (
                    <SelectItem key={a} value={a}>
                      <div className="flex flex-col">
                        <span>{LABELS_ACTION_FINANCIERE[a].label}</span>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="mt-1 text-[11px] text-muted-foreground">
                {LABELS_ACTION_FINANCIERE[actionFinanciere].tooltip}
              </p>
            </div>

            {preview && (
              <div
                className="rounded-lg border border-blue-200 bg-blue-50 p-3"
                data-testid="preview-resolution"
              >
                <p className="mb-1 text-xs font-semibold uppercase text-blue-800">
                  Ce que cette résolution va faire
                </p>
                <ul className="list-inside list-disc space-y-0.5 text-xs text-blue-900">
                  {preview.map((m, i) => (
                    <li key={i}>{m}</li>
                  ))}
                </ul>
              </div>
            )}

            {resultat && !resultat.error && (
              <div
                className="rounded-lg border border-green-200 bg-green-50 p-3 text-xs"
                data-testid="result-json"
              >
                <p className="mb-1 font-semibold uppercase text-green-800">
                  Retour <code>fn_admin_resoudre_litige</code>
                </p>
                <dl className="grid grid-cols-[auto_1fr] gap-x-2 gap-y-0.5 text-green-900">
                  <dt>action_financiere</dt>
                  <dd className="font-mono">{resultat.action_financiere ?? '—'}</dd>
                  <dt>nouvelle_facture_id</dt>
                  <dd className="font-mono break-all">
                    {resultat.nouvelle_facture_id ?? '—'}
                  </dd>
                  <dt>avoir_id</dt>
                  <dd className="font-mono break-all">
                    {resultat.avoir_id ?? '—'}
                  </dd>
                  <dt>mode_remboursement</dt>
                  <dd className="font-mono">
                    {resultat.mode_remboursement ?? '—'}
                  </dd>
                  <dt>régularisation sociale</dt>
                  <dd className="font-mono">
                    {resultat.regularisation_sociale_requise ? 'oui' : 'non'}
                  </dd>
                  <dt>regen_pdf_request_ids</dt>
                  <dd className="font-mono break-all">
                    {resultat.regen_pdf_request_ids?.length
                      ? resultat.regen_pdf_request_ids.join(', ')
                      : '—'}
                  </dd>
                </dl>
              </div>
            )}
          </div>
        </TooltipProvider>

        <DialogFooter>
          <BoutonY2K variant="ghost" onClick={() => handleClose(false)}>
            Fermer
          </BoutonY2K>
          <BoutonY2K
            onClick={submit}
            disabled={
              submitting ||
              resolutionText.trim().length < 10 ||
              !enFaveurDe ||
              heuresInvalides ||
              tauxInvalide
            }
            loading={submitting}
          >
            {submitting ? 'Résolution…' : 'Valider la résolution'}
          </BoutonY2K>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

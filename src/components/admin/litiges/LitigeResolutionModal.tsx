import React, { useEffect, useMemo, useState } from 'react';
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
import {
  decrireAccordAccepte,
  estMissionSalariee,
  formatHeuresArbitrage,
  heuresContractuellesMission,
  LABELS_TYPE_ACCORD,
  tauxContractuelMission,
  tauxEffectifCalculMission,
  TYPES_ACCORD_VALIDATION_DEDIEE,
} from '@/lib/litigeResolutionUi';

type Props = {
  litige: LitigeEnrichi | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onResolved?: () => void;
};

type ResolutionResult = {
  success?: boolean;
  error?: string;
  litige_id?: string;
  action_financiere?: ActionFinanciere | 'RECTIFICATION_DESCRIPTIVE' | 'RECTIFICATION_PAIE_SALARIEE';
  nouvelle_facture_id?: string | null;
  avoir_id?: string | null;
  rectification_id?: string | null;
  mode_remboursement?: string | null;
  delta_ttc?: number | null;
  regularisation_sociale_requise?: boolean;
  regularisation_paiement_requise?: boolean;
  ecart_paiement?: number | null;
  salaire_brut?: number | null;
  net_avant_impot?: number | null;
  bulletin_annule_id?: string | null;
  bulletin_rectificatif_id?: string | null;
  document_commission_id?: string | null;
  document_commission_type?: string | null;
  regen_pdf_request_ids?: string[];
  [key: string]: unknown;
};

type SoldeCorrection = {
  success?: boolean;
  error?: string;
  facture_id?: string;
  montant_ht?: number;
  montant_tva?: number;
  montant_ttc?: number;
  a_des_corrections?: boolean;
};

type FactureCible = {
  id: string;
  numero_facture: string;
  statut: string;
  montant_ht: number;
  montant_tva: number;
  montant_ttc: number;
  taux_tva: number;
  periode_debut: string | null;
  periode_fin: string | null;
  quantite_heures_snapshot: number | null;
  taux_horaire_snapshot: number | null;
  nature_correction: string | null;
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
  const [factureCible, setFactureCible] = useState<FactureCible | null>(null);
  const [soldeCorrection, setSoldeCorrection] = useState<SoldeCorrection | null>(null);
  const [factureLoading, setFactureLoading] = useState(false);
  const [factureErreur, setFactureErreur] = useState<string | null>(null);

  useEffect(() => {
    let actif = true;
    if (!open || !litige?.facture_id) {
      setFactureCible(null);
      setSoldeCorrection(null);
      setFactureErreur(null);
      return () => { actif = false; };
    }
    setFactureLoading(true);
    setFactureCible(null);
    setSoldeCorrection(null);
    setFactureErreur(null);
    void (async () => {
      const [factureResult, soldeResult] = await Promise.all([
        supabase
          .from('factures_honoraires')
          .select('id, numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva, periode_debut, periode_fin, quantite_heures_snapshot, taux_horaire_snapshot, nature_correction')
          .eq('id', litige.facture_id)
          .maybeSingle(),
        supabase.rpc('fn_admin_solde_correction_facture_honoraires', {
          p_facture_id: litige.facture_id,
        }),
      ]);
      if (!actif) return;
      setFactureLoading(false);
      const solde = soldeResult.data as SoldeCorrection | null;
      if (
        factureResult.error
        || !factureResult.data
        || soldeResult.error
        || !solde?.success
        || !Number.isFinite(Number(solde.montant_ttc))
      ) {
        setFactureCible(null);
        setSoldeCorrection(null);
        setFactureErreur(
          solde?.error
            || 'Impossible de charger la facture exacte et son solde corrigé.',
        );
        return;
      }
      setFactureCible(factureResult.data as FactureCible);
      setSoldeCorrection(solde);
    })();
    return () => { actif = false; };
  }, [open, litige?.facture_id]);

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
  const soldeActuelTtc = soldeCorrection?.montant_ttc != null
    ? Number(soldeCorrection.montant_ttc)
    : null;
  const aDejaDesCorrections = soldeCorrection?.a_des_corrections === true;
  const missionSalariee = estMissionSalariee(litige);
  const tauxContractuel = tauxContractuelMission(litige);
  const tauxMission = tauxEffectifCalculMission(litige);
  const heuresMission = heuresContractuellesMission(litige);
  const heuresEffectives = heuresNum
    ?? (tauxNum != null && !aDejaDesCorrections
      ? factureCible?.quantite_heures_snapshot ?? heuresMission
      : null);
  const tauxEffectif = tauxNum
    ?? (heuresNum != null && !aDejaDesCorrections
      ? factureCible?.taux_horaire_snapshot ?? tauxMission
      : null);
  const montantProjete = heuresEffectives != null && tauxEffectif != null
    ? Number((heuresEffectives * tauxEffectif * (1 + Number(factureCible?.taux_tva ?? 0) / 100)).toFixed(2))
    : null;
  const deltaProjete = montantProjete != null && soldeActuelTtc != null
    ? Number((montantProjete - soldeActuelTtc).toFixed(2))
    : null;
  const ajustementReferenceIncomplet = (heuresNum != null || tauxNum != null)
    && (heuresEffectives == null || tauxEffectif == null);
  const factureContextInvalide = Boolean(
    litige?.facture_id && !factureLoading && !factureCible,
  );
  const accord = litige?.statut === 'REVUE_ADMIN'
    ? litige.payload_modifications
    : null;
  const accordModifications = accord?.modifications ?? {};
  const accordValidationDediee = Boolean(
    accord?.type && TYPES_ACCORD_VALIDATION_DEDIEE.has(accord.type),
  );

  const preview = useMemo(() => {
    if (!litige) return null;
    const messages: string[] = [];
    if (heuresNum != null && !Number.isNaN(heuresNum)) {
      messages.push(
        missionSalariee
          ? `Heures retenues → ${formatHeuresArbitrage(heuresNum)} (recalcul de la paie simulée et de la commission).`
          : `Heures → ${heuresNum} h (recalcul du montant de la facture).`,
      );
      if (tauxNum == null && factureCible == null && tauxMission != null) {
        messages.push(`Taux contractuel figé repris automatiquement → ${tauxMission} €/h.`);
      }
    }
    if (tauxNum != null && !Number.isNaN(tauxNum)) {
      messages.push(`Taux horaire → ${tauxNum} €/h.`);
    }
    if (messages.length === 0 && accord) {
      messages.push(...decrireAccordAccepte(accord));
    } else if (messages.length === 0) {
      messages.push('Aucun ajustement financier — clôture litige uniquement.');
    }
    if (accordValidationDediee) {
      messages.push('Cet accord doit être exécuté depuis l’action dédiée « Valider l’accord et exécuter ».');
      return messages;
    }
    if (factureCible && montantProjete != null && deltaProjete != null) {
      messages.push(
        `Facture ${factureCible.numero_facture} : solde corrigé ${Number(soldeActuelTtc).toFixed(2)} € → ${montantProjete.toFixed(2)} € TTC (écart ${deltaProjete >= 0 ? '+' : ''}${deltaProjete.toFixed(2)} €).`,
      );
    }
    if (missionSalariee) {
      if (montantProjete != null) {
        messages.push(
          `Base brute avant IFM/ICP et cotisations → ${montantProjete.toFixed(2)} € (${formatHeuresArbitrage(heuresEffectives)} × ${tauxEffectif} €/h).`,
        );
      }
      messages.push(
        'Action financière : rectification salariée automatique → l’ancienne simulation est annulée, une nouvelle simulation liée au litige est émise, puis la commission est recalculée. Un paiement déjà déclaré n’est jamais réécrit silencieusement.',
      );
      return messages;
    }
    switch (actionFinanciere) {
      case 'AUTO':
        messages.push(
          'Action financière : AUTO → brouillon recalculé, émise remplacée, payée régularisée par avoir ou complément ; si le total payé reste identique, seule une rectification descriptive immuable est créée.',
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
      case 'COMPLEMENT':
        messages.push(
          'Action financière : FACTURE COMPLÉMENTAIRE → sur une facture déjà payée, seul le delta positif est facturé. L’originale reste intacte.',
        );
        break;
    }
    return messages;
  }, [litige, heuresNum, tauxNum, accord, accordValidationDediee, actionFinanciere, factureCible, montantProjete, deltaProjete, soldeActuelTtc, tauxMission, missionSalariee, heuresEffectives, tauxEffectif]);

  const disclaimerURSSAF = heuresNum != null && heuresNum > 0;
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
    if (accordValidationDediee) {
      toast.error('Utilisez « Valider l’accord et exécuter » pour appliquer cet accord exact.');
      return;
    }
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
    if (factureContextInvalide) {
      toast.error('La facture exacte doit être chargée avant toute résolution.');
      return;
    }
    if (factureLoading) {
      toast.error('Attendez le chargement du solde corrigé avant de valider.');
      return;
    }
    if (ajustementReferenceIncomplet) {
      toast.error(
        aDejaDesCorrections
          ? 'Cette facture a déjà été corrigée : renseignez les heures et le taux finaux pour éviter de reprendre une ancienne base.'
          : 'Renseignez les heures et le taux : la facture ne contient pas toute la base historique.',
      );
      return;
    }

    setSubmitting(true);
    setResultat(null);

    // Une Checkout Session ouverte contient les anciens montants. Elle doit
    // être expirée avant de remplacer une facture non payée ; le serveur ne
    // touche qu'à la tentative de la facture exacte liée à ce litige.
    if (factureCible && ['EMISE', 'EN_RETARD'].includes(factureCible.statut)) {
      const { data: expiration, error: expirationError } = await supabase.functions.invoke(
        'expire-invoice-checkout-for-dispute',
        { body: { litige_id: litige.id } },
      );
      if (expirationError || expiration?.error) {
        logger.error('expire-invoice-checkout-for-dispute error', expirationError || expiration);
        toast.error(
          expiration?.message
            || 'Impossible de sécuriser la tentative de paiement en cours. Rechargez le litige avant de réessayer.',
        );
        setSubmitting(false);
        return;
      }
    }

    const payload = {
      p_litige_id: litige.id,
      p_resolution: resolutionText.trim(),
      p_en_faveur_de: enFaveurDe,
      p_ajuster_heures: heuresEffectives ?? undefined,
      p_ajuster_taux: tauxEffectif ?? undefined,
      p_action_financiere: actionFinanciere,
    };

    const { data, error } = await supabase.rpc(
      'fn_admin_resoudre_litige_intelligent',
      payload,
    );

    if (error) {
      logger.error('fn_admin_resoudre_litige_intelligent error', error);
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
            {litige.facture_id && (
              <div className="rounded-lg border border-border bg-muted/30 p-3 text-xs">
                {factureLoading ? (
                  <p className="text-muted-foreground">Chargement de la facture ciblée…</p>
                ) : factureErreur ? (
                  <p className="font-medium text-destructive">{factureErreur}</p>
                ) : factureCible ? (
                  <>
                    <p className="font-semibold">Facture exacte à corriger : {factureCible.numero_facture}</p>
                    <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
                      <dt>Statut</dt><dd>{factureCible.statut}</dd>
                      <dt>Période</dt><dd>{factureCible.periode_debut ?? '—'} → {factureCible.periode_fin ?? '—'}</dd>
                      <dt>Montant d’origine</dt>
                      <dd>{Number(factureCible.montant_ttc).toFixed(2)} € TTC</dd>
                      <dt>Solde après corrections</dt>
                      <dd className="font-semibold">
                        {soldeActuelTtc != null ? soldeActuelTtc.toFixed(2) : '—'} € TTC
                      </dd>
                      <dt>Base figée</dt>
                      <dd>
                        {factureCible.quantite_heures_snapshot ?? '—'} h × {factureCible.taux_horaire_snapshot ?? '—'} €/h
                      </dd>
                    </dl>
                    <p className="mt-2 text-muted-foreground">
                      AUTO conserve l’originale : brouillon recalculé, facture émise remplacée, facture payée régularisée par avoir ou complément selon l’écart.
                    </p>
                    {aDejaDesCorrections && (
                      <p className="mt-2 font-medium text-amber-700">
                        Cette facture possède déjà une correction. Pour un nouvel ajustement, saisissez toujours les heures et le taux finaux ; le delta sera calculé sur le solde cumulé ci-dessus.
                      </p>
                    )}
                  </>
                ) : null}
              </div>
            )}
            {!litige.facture_id && tauxMission != null && (
              <div className="rounded-lg border border-border bg-muted/30 p-3 text-xs">
                <p className="font-semibold">Base contractuelle de la mission</p>
                <p className="mt-1 text-muted-foreground">
                  {litige.mission?.type_contrat_applique === 'SALARIE'
                    ? 'Mission salariée sans facture d’honoraires'
                    : 'Aucune facture d’honoraires encore rattachée'}
                  {' · '}taux demandé figé : <strong>{tauxContractuel} €/h</strong>
                  {missionSalariee
                    && litige.mission?.rist_plafond_applique
                    && tauxMission !== tauxContractuel
                    ? <> · taux retenu après plafond RIST : <strong>{tauxMission} €/h</strong></>
                    : null}.
                </p>
                <p className="mt-1 text-muted-foreground">
                  Le taux effectivement applicable est repris automatiquement si vous corrigez uniquement les heures.
                </p>
                {missionSalariee && heuresMission != null && (
                  <p className="mt-1 text-muted-foreground">
                    Durée actuellement retenue : <strong>{formatHeuresArbitrage(heuresMission)}</strong>.
                  </p>
                )}
              </div>
            )}
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
            {accordValidationDediee && (
              <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs text-destructive" role="alert">
                Cette résolution générique est désactivée : revenez au litige et utilisez
                « Valider l’accord et exécuter » afin d’appliquer exactement l’accord accepté.
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
                        {missionSalariee
                          ? 'Toute correction recalcule la simulation de paie, les cotisations et la commission. Si un paiement existe déjà, une régularisation explicite sera signalée.'
                          : (
                            <>
                              Ajuster les heures à la hausse déclenche une
                              régularisation sociale URSSAF / Carpimko côté soignant
                              libéral. Un email{' '}
                              <code>REGULARISATION_SOCIALE_REQUISE</code> sera poussé.
                            </>
                          )}
                      </TooltipContent>
                    </Tooltip>
                  )}
                </div>
                <Input
                  type="number"
                  step="0.01"
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

            {missionSalariee ? (
              <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-xs" data-testid="action-paie-salariee">
                <p className="font-semibold text-foreground">Rectification de paie automatique</p>
                <p className="mt-1 text-muted-foreground">
                  Aucun choix de facture d’honoraires n’est applicable à une mission salariée. Les preuves restent conservées et les nouveaux montants sont liés à ce litige.
                </p>
              </div>
            ) : <div>
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
            </div>}

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
                  Résultat comptable appliqué
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
                  <dt>rectification_id</dt>
                  <dd className="font-mono break-all">
                    {resultat.rectification_id ?? '—'}
                  </dd>
                  <dt>mode_remboursement</dt>
                  <dd className="font-mono">
                    {resultat.mode_remboursement ?? '—'}
                  </dd>
                  <dt>delta TTC</dt>
                  <dd className="font-mono">
                    {resultat.delta_ttc != null ? `${resultat.delta_ttc} €` : '—'}
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
                  {resultat.action_financiere === 'RECTIFICATION_PAIE_SALARIEE' && (
                    <>
                      <dt>nouvelle simulation</dt>
                      <dd className="font-mono break-all">{resultat.bulletin_rectificatif_id ?? '—'}</dd>
                      <dt>simulation annulée</dt>
                      <dd className="font-mono break-all">{resultat.bulletin_annule_id ?? '—'}</dd>
                      <dt>brut recalculé</dt>
                      <dd className="font-mono">{resultat.salaire_brut != null ? `${resultat.salaire_brut} €` : '—'}</dd>
                      <dt>net avant impôt</dt>
                      <dd className="font-mono">{resultat.net_avant_impot != null ? `${resultat.net_avant_impot} €` : '—'}</dd>
                      <dt>régularisation paiement</dt>
                      <dd className="font-mono">
                        {resultat.regularisation_paiement_requise
                          ? `requise (${resultat.ecart_paiement ?? '—'} €)`
                          : 'non'}
                      </dd>
                    </>
                  )}
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
              tauxInvalide ||
              factureLoading ||
              factureContextInvalide ||
              ajustementReferenceIncomplet
              || accordValidationDediee
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

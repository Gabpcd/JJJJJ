import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { HandCoins } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { FileDeTravail } from '@/components/admin/FileDeTravail';
import { Checkbox } from '@/components/ui/checkbox';

export const STATUTS_AVOIR = [
  'BROUILLON',
  'EMISE',
  'REMBOURSE',
  'ANNULEE',
] as const;
export type StatutAvoir = (typeof STATUTS_AVOIR)[number];

export const LABELS_STATUT_AVOIR: Record<StatutAvoir, string> = {
  BROUILLON: 'Brouillon',
  EMISE: 'Émis — en attente remboursement',
  REMBOURSE: 'Remboursé',
  ANNULEE: 'Annulé',
};

export const MODES_REMBOURSEMENT = [
  'N_A',
  'AUTO_STRIPE',
  'VIREMENT_MANUEL',
] as const;
export type ModeRemboursement = (typeof MODES_REMBOURSEMENT)[number];

export const LABELS_MODE_REMB: Record<ModeRemboursement, string> = {
  N_A: 'N/A',
  AUTO_STRIPE: 'Auto (Stripe)',
  VIREMENT_MANUEL: 'Virement manuel requis',
};

export type AvoirEnrichi = {
  id: string;
  numero_facture: string | null;
  type_document: string;
  statut: string;
  mode_remboursement: string | null;
  montant_ht: number | null;
  montant_tva: number | null;
  montant_ttc: number | null;
  date_emission: string | null;
  date_remboursement: string | null;
  reference_remboursement: string | null;
  soignant_id: string | null;
  etablissement_id: string | null;
  litige_id: string | null;
  soignant_nom?: string | null;
  etablissement_nom?: string | null;
};

export type MontantsAvoir = {
  ht: number | null;
  tva: number | null;
  ttc: number | null;
  montantRemboursement: number | null;
};

export function calculerMontantsAvoir(
  avoir: Pick<AvoirEnrichi, 'montant_ht' | 'montant_tva' | 'montant_ttc'>,
): MontantsAvoir {
  const nombreFini = (value: number | null): number | null =>
    value != null && Number.isFinite(Number(value)) ? Number(value) : null;
  const ht = nombreFini(avoir.montant_ht);
  const ttc = nombreFini(avoir.montant_ttc);
  const tvaStockee = nombreFini(avoir.montant_tva);
  const tva = tvaStockee ?? (ht != null && ttc != null ? ttc - ht : null);
  return {
    ht,
    tva,
    ttc,
    // Le remboursement est une opération sensible : sans TTC stocké, l'UI
    // bloque l'action au lieu d'assimiler silencieusement le HT au TTC.
    montantRemboursement: ttc,
  };
}

const formatDate = (d?: string | null) =>
  d ? new Date(d).toLocaleDateString('fr-FR') : '—';

const formatMontant = (v: number | null | undefined): string => {
  if (v == null || Number.isNaN(Number(v))) return '—';
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
  }).format(Number(v));
};

function badgeStatut(statut: string): 'success' | 'warning' | 'error' | 'info' {
  if (statut === 'REMBOURSE') return 'success';
  if (statut === 'ANNULEE') return 'info';
  if (statut === 'EMISE') return 'warning';
  return 'info';
}

export function filtrerAvoirs(
  avoirs: AvoirEnrichi[],
  statut: StatutAvoir | 'TOUS',
): AvoirEnrichi[] {
  if (statut === 'TOUS') return avoirs;
  return avoirs.filter((a) => a.statut === statut);
}

type Props = {
  onChanged?: () => void;
};

export function AvoirsList({ onChanged }: Props) {
  const [avoirs, setAvoirs] = useState<AvoirEnrichi[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [avoirCible, setAvoirCible] = useState<AvoirEnrichi | null>(null);
  const [reference, setReference] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [confirmationMontant, setConfirmationMontant] = useState(false);

  const charger = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    const { data, error } = await supabase
      .from('factures_honoraires')
      .select(
        'id, numero_facture, type_document, statut, mode_remboursement, montant_ht, montant_tva, montant_ttc, date_emission, date_remboursement, reference_remboursement, soignant_id, etablissement_id, litige_id',
      )
      .eq('type_document', 'AVOIR')
      .order('date_emission', { ascending: false })
      .limit(200);

    if (error) {
      logger.error('charger avoirs error', error);
      setAvoirs([]);
      setLoadError(error.message || 'Impossible de charger les avoirs.');
      setLoading(false);
      return;
    }
    if (!data) {
      setAvoirs([]);
      setLoadError('Réponse des avoirs absente.');
      setLoading(false);
      return;
    }

    const bruts = data as AvoirEnrichi[];
    const soignantIds = [...new Set(bruts.map((a) => a.soignant_id).filter(Boolean))] as string[];
    const etabIds = [...new Set(bruts.map((a) => a.etablissement_id).filter(Boolean))] as string[];

    const [resSg, resEt] = await Promise.all([
      soignantIds.length
        ? supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds)
        : Promise.resolve({ data: [] } as any),
      etabIds.length
        ? supabase.from('etablissements').select('id, nom').in('id', etabIds)
        : Promise.resolve({ data: [] } as any),
    ]);

    if (resSg.error || resEt.error) {
      const enrichError = resSg.error ?? resEt.error;
      logger.error('enrichir avoirs error', enrichError);
      setAvoirs([]);
      setLoadError(enrichError?.message || 'Impossible de charger les bénéficiaires des avoirs.');
      setLoading(false);
      return;
    }

    const sgMap = new Map<string, string>();
    for (const s of (resSg.data ?? []) as Array<any>) {
      sgMap.set(s.id, `${s.prenom ?? ''} ${s.nom ?? ''}`.trim() || '—');
    }
    const etMap = new Map<string, string>();
    for (const e of (resEt.data ?? []) as Array<any>) {
      etMap.set(e.id, e.nom ?? '—');
    }

    setAvoirs(
      bruts.map((a) => ({
        ...a,
        soignant_nom: a.soignant_id ? sgMap.get(a.soignant_id) ?? '—' : '—',
        etablissement_nom: a.etablissement_id
          ? etMap.get(a.etablissement_id) ?? '—'
          : '—',
      })),
    );
    setLoading(false);
  }, []);

  useEffect(() => {
    charger();
  }, [charger]);

  // File de travail : avoirs EMISE à rembourser (virement manuel en premier,
  // plus anciens d'abord) ; le reste (remboursés, annulés, brouillons) en historique.
  const { aRembourser, historique } = useMemo(() => {
    const emis = avoirs
      .filter((a) => a.statut === 'EMISE')
      .sort((a, b) => {
        const ma = a.mode_remboursement === 'VIREMENT_MANUEL' ? 0 : 1;
        const mb = b.mode_remboursement === 'VIREMENT_MANUEL' ? 0 : 1;
        if (ma !== mb) return ma - mb;
        return (a.date_emission ?? '').localeCompare(b.date_emission ?? '');
      });
    const autres = avoirs.filter((a) => a.statut !== 'EMISE');
    return { aRembourser: emis, historique: autres };
  }, [avoirs]);

  const ouvrirDialogConfirmation = (a: AvoirEnrichi) => {
    setAvoirCible(a);
    setReference('');
    setConfirmationMontant(false);
    setDialogOpen(true);
  };

  const confirmerRemboursement = async () => {
    if (!avoirCible) return;
    if (!confirmationMontant) {
      toast.error('Confirmez explicitement le montant TTC remboursé.');
      return;
    }
    const ref = reference.trim();
    if (ref.length < 4) {
      toast.error('Référence virement requise (min 4 caractères).');
      return;
    }
    setSubmitting(true);
    const { data, error } = await supabase.rpc(
      'fn_confirmer_remboursement_avoir' as any,
      { p_avoir_id: avoirCible.id, p_reference_virement: ref },
    );

    if (error) {
      logger.error('fn_confirmer_remboursement_avoir error', error);
      toast.error(error.message || 'Erreur lors de la confirmation.');
      setSubmitting(false);
      return;
    }
    if ((data as any)?.error) {
      toast.error((data as any).error);
      setSubmitting(false);
      return;
    }

    toast.success('Remboursement confirmé.');
    setSubmitting(false);
    setDialogOpen(false);
    setAvoirCible(null);
    setReference('');
    setConfirmationMontant(false);
    await charger();
    onChanged?.();
  };

  const tableAvoirs = (rows: AvoirEnrichi[], emptyTestId?: string) => (
    <div className="overflow-x-auto rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>N° avoir</TableHead>
            <TableHead>Soignant</TableHead>
            <TableHead>Établissement</TableHead>
            <TableHead className="text-right">Montant HT</TableHead>
            <TableHead className="text-right">TVA</TableHead>
            <TableHead className="text-right">Montant TTC</TableHead>
            <TableHead>Mode remboursement</TableHead>
            <TableHead>Statut</TableHead>
            <TableHead>Émission</TableHead>
            <TableHead className="text-right">Action</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.length === 0 && (
            <TableRow>
              <TableCell
                colSpan={10}
                className="py-6 text-center text-muted-foreground"
                data-testid={emptyTestId}
              >
                Aucun avoir.
              </TableCell>
            </TableRow>
          )}
          {rows.map((a) => {
            const montants = calculerMontantsAvoir(a);
            const remboursable =
              a.statut === 'EMISE'
              && a.mode_remboursement === 'VIREMENT_MANUEL'
              && (montants.montantRemboursement ?? 0) > 0;
            return (
              <TableRow key={a.id} data-testid="avoir-row" data-avoir-id={a.id}>
                <TableCell className="font-mono text-xs">
                  {a.numero_facture ?? '—'}
                </TableCell>
                <TableCell>{a.soignant_nom ?? '—'}</TableCell>
                <TableCell>{a.etablissement_nom ?? '—'}</TableCell>
                <TableCell className="text-right font-mono">
                  {formatMontant(montants.ht)}
                </TableCell>
                <TableCell className="text-right font-mono text-muted-foreground">
                  {formatMontant(montants.tva)}
                </TableCell>
                <TableCell className="text-right font-mono font-semibold">
                  {formatMontant(montants.ttc)}
                </TableCell>
                <TableCell>
                  <BadgeY2K variant="info" size="sm">
                    {LABELS_MODE_REMB[
                      a.mode_remboursement as ModeRemboursement
                    ] ?? a.mode_remboursement ?? '—'}
                  </BadgeY2K>
                </TableCell>
                <TableCell>
                  <BadgeY2K variant={badgeStatut(a.statut)}>
                    {LABELS_STATUT_AVOIR[a.statut as StatutAvoir] ?? a.statut}
                  </BadgeY2K>
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {formatDate(a.date_emission)}
                </TableCell>
                <TableCell className="text-right">
                  {remboursable ? (
                    <BoutonY2K
                      size="sm"
                      variant="secondary"
                      onClick={() => ouvrirDialogConfirmation(a)}
                      aria-label={`Confirmer remboursement avoir ${a.numero_facture ?? a.id}`}
                    >
                      Confirmer remboursement
                    </BoutonY2K>
                  ) : (
                    <span className="text-xs text-muted-foreground">—</span>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );

  if (loading) {
    return (
      <div className="py-6 text-center text-muted-foreground" data-testid="avoirs-list">
        Chargement…
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-5 text-center" data-testid="avoirs-list" role="alert">
        <p className="font-semibold text-destructive">Avoirs indisponibles</p>
        <p className="mt-1 text-sm text-muted-foreground">{loadError}</p>
        <BoutonY2K className="mt-3" size="sm" onClick={charger}>Réessayer</BoutonY2K>
      </div>
    );
  }

  const montantsCible = avoirCible ? calculerMontantsAvoir(avoirCible) : null;

  return (
    <div className="space-y-4" data-testid="avoirs-list">
      <FileDeTravail
        nbATraiter={aRembourser.length}
        aTraiter={tableAvoirs(aRembourser, 'avoirs-empty')}
        nbHistorique={historique.length}
        historique={tableAvoirs(historique)}
        labelATraiter="À rembourser"
        labelHistorique="Historique (remboursés, annulés, brouillons)"
        titreVide="Aucun avoir à rembourser"
        descriptionVide="Tous les avoirs émis ont été remboursés."
        iconeVide={<HandCoins />}
      />

      <Dialog
        open={dialogOpen}
        onOpenChange={(open) => {
          setDialogOpen(open);
          if (!open) {
            setAvoirCible(null);
            setReference('');
            setConfirmationMontant(false);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmer le remboursement manuel</DialogTitle>
            <DialogDescription>
              Avoir <span className="font-mono">{avoirCible?.numero_facture ?? '—'}</span>
            </DialogDescription>
          </DialogHeader>

          <div className="rounded-lg border bg-muted/30 p-3 text-sm">
            <div className="flex justify-between gap-4"><span>Montant HT</span><span>{formatMontant(montantsCible?.ht)}</span></div>
            <div className="mt-1 flex justify-between gap-4"><span>TVA</span><span>{formatMontant(montantsCible?.tva)}</span></div>
            <div className="mt-2 flex justify-between gap-4 border-t pt-2 font-bold">
              <span>Montant TTC réellement remboursé</span>
              <span>{formatMontant(montantsCible?.montantRemboursement)}</span>
            </div>
          </div>

          <div>
            <Label className="mb-1.5 block" htmlFor="reference-virement">
              Référence virement *
            </Label>
            <Input
              id="reference-virement"
              value={reference}
              onChange={(e) => setReference(e.target.value)}
              placeholder="Ex : VIR-2026-04-17-XYZ"
              aria-label="Référence virement"
              minLength={4}
            />
            <p className="mt-1 text-[11px] text-muted-foreground">
              Minimum 4 caractères. Saisissez la référence bancaire du virement
              effectué.
            </p>
          </div>

          <div className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/5 p-3">
            <Checkbox
              id="confirmation-montant-remboursement"
              checked={confirmationMontant}
              onCheckedChange={(checked) => setConfirmationMontant(checked === true)}
            />
            <Label htmlFor="confirmation-montant-remboursement" className="cursor-pointer text-sm leading-snug">
              Je confirme avoir effectué le virement de{' '}
              <strong>{formatMontant(montantsCible?.montantRemboursement)} TTC</strong>
              {' '}au bénéficiaire indiqué.
            </Label>
          </div>

          <DialogFooter>
            <BoutonY2K variant="ghost" onClick={() => setDialogOpen(false)}>
              Annuler
            </BoutonY2K>
            <BoutonY2K
              onClick={confirmerRemboursement}
              disabled={submitting || reference.trim().length < 4 || !confirmationMontant}
              loading={submitting}
            >
              {submitting
                ? 'Confirmation…'
                : `Confirmer ${formatMontant(montantsCible?.montantRemboursement)} TTC`}
            </BoutonY2K>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

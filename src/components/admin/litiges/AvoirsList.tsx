import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
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
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';

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
  const [filtreStatut, setFiltreStatut] = useState<StatutAvoir | 'TOUS'>('TOUS');

  const [dialogOpen, setDialogOpen] = useState(false);
  const [avoirCible, setAvoirCible] = useState<AvoirEnrichi | null>(null);
  const [reference, setReference] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('factures_honoraires')
      .select(
        'id, numero_facture, type_document, statut, mode_remboursement, montant_ht, montant_ttc, date_emission, date_remboursement, reference_remboursement, soignant_id, etablissement_id, litige_id',
      )
      .eq('type_document', 'AVOIR')
      .order('date_emission', { ascending: false })
      .limit(200);

    if (error) {
      logger.error('charger avoirs error', error);
      toast.error('Impossible de charger les avoirs.');
      setLoading(false);
      return;
    }

    const bruts = (data ?? []) as AvoirEnrichi[];
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

  const visibles = useMemo(
    () => filtrerAvoirs(avoirs, filtreStatut),
    [avoirs, filtreStatut],
  );

  const ouvrirDialogConfirmation = (a: AvoirEnrichi) => {
    setAvoirCible(a);
    setReference('');
    setDialogOpen(true);
  };

  const confirmerRemboursement = async () => {
    if (!avoirCible) return;
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
    await charger();
    onChanged?.();
  };

  return (
    <div className="space-y-4" data-testid="avoirs-list">
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-[220px]">
          <Label className="mb-1.5 block text-xs">Statut</Label>
          <Select
            value={filtreStatut}
            onValueChange={(v) => setFiltreStatut(v as StatutAvoir | 'TOUS')}
          >
            <SelectTrigger aria-label="Filtre statut avoir">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="TOUS">Tous</SelectItem>
              {STATUTS_AVOIR.map((s) => (
                <SelectItem key={s} value={s}>
                  {LABELS_STATUT_AVOIR[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="ml-auto text-xs text-muted-foreground">
          {visibles.length} avoir{visibles.length > 1 ? 's' : ''} affiché
          {visibles.length > 1 ? 's' : ''}
        </div>
      </div>

      <div className="overflow-x-auto rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>N° avoir</TableHead>
              <TableHead>Soignant</TableHead>
              <TableHead>Établissement</TableHead>
              <TableHead className="text-right">Montant HT</TableHead>
              <TableHead>Mode remboursement</TableHead>
              <TableHead>Statut</TableHead>
              <TableHead>Émission</TableHead>
              <TableHead className="text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {loading && (
              <TableRow>
                <TableCell colSpan={8} className="py-6 text-center text-muted-foreground">
                  Chargement…
                </TableCell>
              </TableRow>
            )}
            {!loading && visibles.length === 0 && (
              <TableRow>
                <TableCell
                  colSpan={8}
                  className="py-6 text-center text-muted-foreground"
                  data-testid="avoirs-empty"
                >
                  Aucun avoir pour ce filtre.
                </TableCell>
              </TableRow>
            )}
            {!loading &&
              visibles.map((a) => {
                const remboursable =
                  a.statut === 'EMISE' && a.mode_remboursement === 'VIREMENT_MANUEL';
                return (
                  <TableRow key={a.id} data-testid="avoir-row" data-avoir-id={a.id}>
                    <TableCell className="font-mono text-xs">
                      {a.numero_facture ?? '—'}
                    </TableCell>
                    <TableCell>{a.soignant_nom ?? '—'}</TableCell>
                    <TableCell>{a.etablissement_nom ?? '—'}</TableCell>
                    <TableCell className="text-right font-mono">
                      {formatMontant(a.montant_ht)}
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

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmer le remboursement manuel</DialogTitle>
            <DialogDescription>
              Avoir <span className="font-mono">{avoirCible?.numero_facture ?? '—'}</span>
              {' — '}
              {formatMontant(avoirCible?.montant_ht)}
            </DialogDescription>
          </DialogHeader>

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

          <DialogFooter>
            <BoutonY2K variant="ghost" onClick={() => setDialogOpen(false)}>
              Annuler
            </BoutonY2K>
            <BoutonY2K
              onClick={confirmerRemboursement}
              disabled={submitting || reference.trim().length < 4}
              loading={submitting}
            >
              {submitting ? 'Confirmation…' : 'Confirmer le remboursement'}
            </BoutonY2K>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

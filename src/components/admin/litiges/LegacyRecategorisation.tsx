import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent } from '@/components/y2k/CardY2K';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import {
  LABELS_TYPE_LITIGE,
  TYPES_LITIGE,
  type TypeLitige,
} from './types';

export type LitigeLegacy = {
  id: string;
  motif: string;
  cree_le: string;
  statut: string;
  mission_id: string;
  soignant_id: string;
  etablissement_id: string;
  type_litige: 'AUTRE' | null;
  type_legacy: boolean | null;
};

const formatDate = (d?: string | null) =>
  d
    ? new Date(d).toLocaleDateString('fr-FR', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      })
    : '—';

type Props = {
  onChanged?: () => void;
  onCountChange?: (count: number) => void;
};

export function LegacyRecategorisation({ onChanged, onCountChange }: Props) {
  const [legacies, setLegacies] = useState<LitigeLegacy[]>([]);
  const [loading, setLoading] = useState(true);
  const [selections, setSelections] = useState<Record<string, TypeLitige | ''>>({});
  const [submittingId, setSubmittingId] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('litiges')
      .select(
        'id, motif, cree_le, statut, mission_id, soignant_id, etablissement_id, type_litige, type_legacy',
      )
      .eq('type_legacy', true)
      .eq('type_litige', 'AUTRE')
      .order('cree_le', { ascending: false })
      .limit(200);

    if (error) {
      logger.error('charger legacy error', error);
      toast.error('Impossible de charger les litiges legacy.');
      setLoading(false);
      return;
    }

    const rows = (data ?? []) as LitigeLegacy[];
    setLegacies(rows);
    setLoading(false);
    onCountChange?.(rows.length);
  }, [onCountChange]);

  useEffect(() => {
    charger();
  }, [charger]);

  const count = legacies.length;

  const recategoriser = async (litige: LitigeLegacy) => {
    const nouveau = selections[litige.id];
    if (!nouveau) {
      toast.error('Veuillez choisir un nouveau type.');
      return;
    }
    if (nouveau === 'AUTRE') {
      toast.error('Sélectionnez un type autre que AUTRE pour recatégoriser.');
      return;
    }

    setSubmittingId(litige.id);
    const { data, error } = await supabase.rpc(
      'fn_admin_recategoriser_litige_legacy' as any,
      { p_litige_id: litige.id, p_nouveau_type: nouveau },
    );

    if (error) {
      logger.error('fn_admin_recategoriser_litige_legacy error', error);
      toast.error(error.message || 'Erreur lors de la recatégorisation.');
      setSubmittingId(null);
      return;
    }
    if ((data as any)?.error) {
      toast.error((data as any).error);
      setSubmittingId(null);
      return;
    }

    toast.success('Litige recatégorisé.');
    setSelections((prev) => {
      const next = { ...prev };
      delete next[litige.id];
      return next;
    });
    setSubmittingId(null);
    await charger();
    onChanged?.();
  };

  return (
    <div className="space-y-4" data-testid="legacy-list">
      <div className="flex items-center gap-2">
        <BadgeY2K variant="info" data-testid="legacy-count">
          {count} litige{count > 1 ? 's' : ''} legacy restant
          {count > 1 ? 's' : ''}
        </BadgeY2K>
        <span className="text-xs text-muted-foreground">
          Litiges avec <code>type_legacy = TRUE</code> et{' '}
          <code>type_litige = AUTRE</code>. Recatégoriser lève le flag
          legacy et recalcule automatiquement la catégorie.
        </span>
      </div>

      {loading && (
        <p className="py-6 text-center text-sm text-muted-foreground">
          Chargement…
        </p>
      )}

      {!loading && count === 0 && (
        <p
          className="py-8 text-center text-sm text-muted-foreground"
          data-testid="legacy-empty"
        >
          Aucun litige historique à recatégoriser.
        </p>
      )}

      {!loading && count > 0 && (
        <div className="space-y-3">
          {legacies.map((l) => {
            const choix = selections[l.id] ?? '';
            const busy = submittingId === l.id;
            return (
              <CardY2K noPadding key={l.id} data-testid="legacy-card" data-litige-id={l.id}>
                <CardY2KContent className="space-y-3 pt-4">
                  <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <BadgeY2K variant="info" size="sm">
                      Statut : {l.statut}
                    </BadgeY2K>
                    <span>Ouvert {formatDate(l.cree_le)}</span>
                  </div>
                  <div>
                    <p className="text-xs uppercase tracking-wide text-muted-foreground">
                      Motif original
                    </p>
                    <p className="mt-1 text-sm text-foreground">
                      {l.motif || '—'}
                    </p>
                  </div>
                  <div className="flex flex-wrap items-end gap-3">
                    <div className="min-w-[260px] flex-1">
                      <label
                        className="mb-1.5 block text-xs font-medium"
                        htmlFor={`type-${l.id}`}
                      >
                        Nouveau type
                      </label>
                      <Select
                        value={choix}
                        onValueChange={(v) =>
                          setSelections((prev) => ({
                            ...prev,
                            [l.id]: v as TypeLitige,
                          }))
                        }
                      >
                        <SelectTrigger
                          id={`type-${l.id}`}
                          aria-label={`Choisir nouveau type pour litige ${l.id}`}
                        >
                          <SelectValue placeholder="Choisir un type..." />
                        </SelectTrigger>
                        <SelectContent>
                          {TYPES_LITIGE.filter((t) => t !== 'AUTRE').map((t) => (
                            <SelectItem key={t} value={t}>
                              {LABELS_TYPE_LITIGE[t]}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <BoutonY2K
                      size="sm"
                      onClick={() => recategoriser(l)}
                      disabled={busy || !choix || choix === 'AUTRE'}
                      loading={busy}
                      aria-label={`Recatégoriser litige ${l.id}`}
                    >
                      {busy ? 'Recatégorisation…' : 'Recatégoriser'}
                    </BoutonY2K>
                  </div>
                </CardY2KContent>
              </CardY2K>
            );
          })}
        </div>
      )}
    </div>
  );
}

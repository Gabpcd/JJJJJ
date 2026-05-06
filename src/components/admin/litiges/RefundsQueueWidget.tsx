import React, { useEffect, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';
import { AlertTriangle, RefreshCcw } from 'lucide-react';

type StatsRefunds = {
  count: number;
  plus_ancienne_iso: string | null;
};

const SEUIL_ALERTE_COUNT = 10;
const SEUIL_ALERTE_HEURES = 48;

export function alerteConditions(stats: StatsRefunds): boolean {
  if (stats.count <= 0) return false;
  if (stats.count > SEUIL_ALERTE_COUNT) return true;
  if (!stats.plus_ancienne_iso) return false;
  const heures = (Date.now() - new Date(stats.plus_ancienne_iso).getTime()) / (1000 * 60 * 60);
  return heures > SEUIL_ALERTE_HEURES;
}

/**
 * CP-LITIGES-7b-3 — Widget count remboursements Stripe en attente.
 * Simple read-only, consommation vraie en Sub-PR 3.
 */
export function RefundsQueueWidget() {
  const [stats, setStats] = useState<StatsRefunds>({ count: 0, plus_ancienne_iso: null });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let annule = false;
    (async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('stripe_refunds_queue' as any)
        .select('id, cree_le', { count: 'exact' })
        .in('statut', ['EN_ATTENTE', 'EN_COURS'])
        .order('cree_le', { ascending: true })
        .limit(1);

      if (annule) return;
      if (error) {
        logger.error('stripe_refunds_queue read error', error);
        setLoading(false);
        return;
      }
      const rows = (data ?? []) as unknown as Array<{ cree_le: string }>;
      const count = (data as any)?.length != null && (data as any)?.count == null
        ? rows.length
        : ((data as any)?.count ?? rows.length);

      setStats({
        count,
        plus_ancienne_iso: rows[0]?.cree_le ?? null,
      });
      setLoading(false);
    })();
    return () => {
      annule = true;
    };
  }, []);

  if (loading) {
    return (
      <div className="inline-flex items-center gap-2 rounded-md border bg-muted/30 px-3 py-1.5 text-xs text-muted-foreground">
        <RefreshCcw className="h-3.5 w-3.5 animate-spin" />
        Remboursements Stripe…
      </div>
    );
  }

  if (stats.count <= 0) return null;

  const alerte = alerteConditions(stats);

  return (
    <div
      className={`inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-xs ${
        alerte
          ? 'border-red-300 bg-red-50 text-red-900'
          : 'border-blue-200 bg-blue-50 text-blue-900'
      }`}
      data-testid="refunds-widget"
      data-alerte={alerte ? '1' : '0'}
      data-count={stats.count}
    >
      {alerte && <AlertTriangle className="h-3.5 w-3.5" />}
      <Badge variant="outline" className="bg-white/60">
        {stats.count}
      </Badge>
      <span>
        remboursement{stats.count > 1 ? 's' : ''} Stripe en attente
        {alerte && ' — seuil dépassé'}
      </span>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { AlertTriangle, RefreshCcw, WalletCards } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';

type OperationItem = {
  id: string;
  statut: string;
  montantEuros: number;
  tentatives: number | null;
  derniereTentative: string | null;
  erreur: string | null;
  reference: string | null;
};

type CanalOperations = {
  label: string;
  count: number | null;
  items: OperationItem[];
  error: string | null;
  notice: string | null;
};

type OperationsState = {
  escrow: CanalOperations;
  refunds: CanalOperations;
  transfers: CanalOperations;
};

const etatInitial = (): OperationsState => ({
  escrow: {
    label: 'Escrows',
    count: null,
    items: [],
    error: null,
    notice: 'Détail protégé côté backend (lecture frontend non autorisée).',
  },
  refunds: { label: 'Remboursements ouverts', count: null, items: [], error: null, notice: null },
  transfers: { label: 'Transferts ouverts', count: null, items: [], error: null, notice: null },
});

const eur = (value: number) => new Intl.NumberFormat('fr-FR', {
  style: 'currency',
  currency: 'EUR',
}).format(value);

const dateHeure = (value: string | null) => value
  ? new Date(value).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })
  : 'aucune tentative';

export function statutOperationCritique(statut: string): boolean {
  return ['ECHOUE', 'ECHEC', 'DISPUTE'].includes(statut);
}

export function FinancialOperationsMonitor() {
  const [state, setState] = useState<OperationsState>(etatInitial);
  const [loading, setLoading] = useState(true);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let actif = true;
    void (async () => {
      setLoading(true);
      const [refundsRes, transfersRes] = await Promise.all([
        supabase
          .from('stripe_refunds_queue' as any)
          .select('id, statut, montant_cts, tentatives, dernier_essai_le, erreur, cree_le, stripe_refund_id', { count: 'exact' })
          .in('statut', ['EN_ATTENTE', 'EN_COURS', 'ECHEC'])
          .order('cree_le', { ascending: false })
          .limit(3),
        supabase
          .from('stripe_transfers')
          .select('id, statut, montant_total, erreur, cree_le, transfere_le, stripe_transfer_id, stripe_payout_id, dispute_statut', { count: 'exact' })
          .or('statut.in.(EN_ATTENTE,CHARGE_REUSSI,ECHOUE),dispute_statut.eq.OUVERT')
          .order('cree_le', { ascending: false })
          .limit(3),
      ]);
      if (!actif) return;

      const next = etatInitial();
      if (refundsRes.error || typeof refundsRes.count !== 'number') {
        logger.error('monitor refunds read error', refundsRes.error ?? new Error('count absent'));
        next.refunds.error = refundsRes.error?.message || 'Comptage remboursements indisponible';
      } else {
        next.refunds.count = refundsRes.count;
        next.refunds.items = ((refundsRes.data ?? []) as any[]).map((row) => ({
          id: row.id,
          statut: row.dispute_statut === 'OUVERT' ? 'DISPUTE' : row.statut,
          montantEuros: Number(row.montant_cts ?? 0) / 100,
          tentatives: Number(row.tentatives ?? 0),
          derniereTentative: row.dernier_essai_le,
          erreur: row.erreur,
          reference: row.stripe_refund_id,
        }));
      }

      if (transfersRes.error || typeof transfersRes.count !== 'number') {
        logger.error('monitor transfers read error', transfersRes.error ?? new Error('count absent'));
        next.transfers.error = transfersRes.error?.message || 'Comptage transferts indisponible';
      } else {
        next.transfers.count = transfersRes.count;
        next.transfers.items = ((transfersRes.data ?? []) as any[]).map((row) => ({
          id: row.id,
          statut: row.statut,
          montantEuros: Number(row.montant_total ?? 0),
          tentatives: null,
          derniereTentative: row.transfere_le ?? row.cree_le,
          erreur: row.erreur,
          reference: row.stripe_payout_id ?? row.stripe_transfer_id,
        }));
      }

      setState(next);
      setLoading(false);
    })().catch((error) => {
      if (!actif) return;
      logger.error('monitor financial operations error', error);
      const next = etatInitial();
      for (const canal of Object.values(next)) canal.error = 'Suivi indisponible';
      setState(next);
      setLoading(false);
    });

    return () => { actif = false; };
  }, [reloadKey]);

  return (
    <section className="rounded-xl border border-border bg-card" aria-labelledby="financial-operations-title">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-4">
        <div>
          <h2 id="financial-operations-title" className="flex items-center gap-2 font-semibold text-foreground">
            <WalletCards className="h-4 w-4 text-primary" /> Suivi des opérations financières
          </h2>
          <p className="mt-0.5 text-xs text-muted-foreground">Lecture seule · files non finalisées et derniers incidents</p>
        </div>
        <BoutonY2K
          size="sm"
          variant="secondary"
          disabled={loading}
          onClick={() => setReloadKey((value) => value + 1)}
          iconeGauche={<RefreshCcw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />}
        >
          Actualiser
        </BoutonY2K>
      </div>

      <div className="grid gap-px bg-border md:grid-cols-3">
        {Object.entries(state).map(([key, canal]) => (
          <div key={key} className="min-w-0 bg-card p-4">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-foreground">{canal.label}</h3>
              <span className={`rounded-full px-2 py-0.5 text-xs font-bold ${canal.error ? 'bg-destructive/10 text-destructive' : 'bg-muted text-foreground'}`}>
                {loading ? '…' : canal.error ? 'indisponible' : canal.notice ? 'protégé' : canal.count}
              </span>
            </div>

            {canal.error ? (
              <p className="mt-3 flex items-start gap-1.5 text-xs text-destructive" role="alert">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" /> {canal.error}
              </p>
            ) : canal.notice ? (
              <p className="mt-3 text-xs text-muted-foreground">{canal.notice}</p>
            ) : !loading && canal.items.length === 0 ? (
              <p className="mt-3 text-xs text-muted-foreground">Aucune opération ouverte.</p>
            ) : (
              <div className="mt-3 space-y-2">
                {canal.items.map((item) => (
                  <div key={item.id} className="rounded-lg border border-border/70 bg-muted/20 p-2 text-xs">
                    <div className="flex items-center justify-between gap-2">
                      <span className={`font-semibold ${statutOperationCritique(item.statut) ? 'text-destructive' : 'text-foreground'}`}>
                        {item.statut}
                      </span>
                      <span className="font-mono font-semibold">{eur(item.montantEuros)}</span>
                    </div>
                    <p className="mt-1 text-[11px] text-muted-foreground">
                      {item.tentatives != null ? `${item.tentatives} tentative(s) · ` : ''}{dateHeure(item.derniereTentative)}
                    </p>
                    {item.reference && <p className="mt-1 truncate font-mono text-[10px] text-muted-foreground">{item.reference}</p>}
                    {item.erreur && <p className="mt-1 line-clamp-2 text-[11px] text-destructive">{item.erreur}</p>}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { supabase } from '@/integrations/supabase/client';
import { etatVersementConnect, lireVersementsConnect, type ConnectPayoutRow } from '@/lib/connectPayoutUi';

const eur = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });

export default function SuiviVersementsConnect() {
  const { user } = useAuth();
  const { role, loading: roleLoading, resolved, error: roleError } = useRole();
  const userId = user?.id ?? null;
  const authorized = !!userId && resolved && !roleLoading && !roleError && role === 'SOIGNANT';
  const [reloadKey, setReloadKey] = useState(0);
  const [result, setResult] = useState<{ userId: string | null; state: 'loading' | 'ready' | 'error'; rows: ConnectPayoutRow[] }>({ userId: null, state: 'loading', rows: [] });

  useEffect(() => {
    if (!authorized || !userId) return;
    let active = true;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    setResult({ userId, state: 'loading', rows: [] });
    void (async () => {
      try {
        const query = supabase.from('stripe_transfers')
          .select('id,mission_id,statut,montant_soignant,stripe_payout_id,standard_payout_state,paye_le')
          .eq('soignant_id', userId)
          .in('statut', ['CHARGE_REUSSI', 'TRANSFERE', 'PAYE'])
          .order('cree_le', { ascending: false })
          .order('id', { ascending: false })
          .limit(20)
          .abortSignal(controller.signal);
        const { data, error } = await Promise.race([
          Promise.resolve(query),
          new Promise<never>((_, reject) => {
            timer = setTimeout(() => { controller.abort(); reject(new Error('Versements indisponibles')); }, 15_000);
          }),
        ]);
        if (error) throw error;
        const rows = lireVersementsConnect(data);
        if (active) setResult({ userId, state: 'ready', rows });
      } catch {
        if (active) setResult({ userId, state: 'error', rows: [] });
      } finally {
        if (timer !== undefined) clearTimeout(timer);
      }
    })();
    return () => { active = false; controller.abort(); if (timer !== undefined) clearTimeout(timer); };
  }, [authorized, userId, reloadKey]);

  // Never retain another user's rows while the role/session changes.
  if (!authorized || result.userId !== userId) return null;
  if (result.state === 'ready' && result.rows.length === 0) return null;
  return (
    <section aria-label="Versements bancaires Stripe" className="card-base mb-6 space-y-3">
      <h2 className="text-sm font-semibold">Derniers versements Stripe</h2>
      <p className="text-xs text-muted-foreground">Un transfert vers le solde Stripe se distingue de l’arrivée sur ton compte bancaire.</p>
      {result.state === 'loading' ? <p role="status" className="text-sm">Chargement des versements…</p> : result.state === 'error' ? (
        <div role="status" className="space-y-2">
          <p className="text-sm">Le suivi des versements bancaires est indisponible. Aucun versement bancaire ne peut être confirmé ici.</p>
          <button type="button" className="btn-secondary min-h-[44px] text-sm" onClick={() => setReloadKey(value => value + 1)}>Réessayer le suivi des versements</button>
        </div>
      ) : (
        <>
          <ul className="divide-y divide-border">
            {result.rows.map(row => {
              const state = etatVersementConnect(row);
              return (
                <li key={row.id} className="space-y-1 py-3">
                  <p className={state.paid ? 'text-sm font-semibold text-success' : 'text-sm font-semibold'}>{state.label} · {eur.format(row.montant_soignant)}</p>
                  <p className="text-xs text-muted-foreground">{state.detail}</p>
                  <Link className="inline-flex min-h-[44px] items-center text-sm underline" to={`/soignant/missions/${encodeURIComponent(row.mission_id)}`}>Voir la mission</Link>
                </li>
              );
            })}
          </ul>
          {result.rows.length === 20 ? <p className="text-xs text-muted-foreground">Les 20 derniers paiements Stripe sont affichés. Cette liste ne constitue pas un total des revenus.</p> : null}
        </>
      )}
    </section>
  );
}

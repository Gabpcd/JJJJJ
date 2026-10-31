import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { PresenceWorkflowError, type PendingPresenceScan, type PresenceContext, type PresenceScanResult } from '../../workflows/presence/types';
import { presenceScopeKey, type PresenceScreenGateway } from './types';
import { usePresenceVisibility } from './usePresenceResource';
import { reconcilePresencePresentation } from './transitions';

/** Mutations never resume automatically. Focus and foreground re-read the journal before enabling entry. */
export function usePresenceScan(gateway: PresenceScreenGateway, context: PresenceContext) {
  const key = presenceScopeKey(gateway, context); const visibility = usePresenceVisibility();
  const [pending, setPending] = useState<PendingPresenceScan | null>(null);
  const [journalReady, setJournalReady] = useState(false);
  const [journalError, setJournalError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false); const [result, setResult] = useState<PresenceScanResult | null>(null);
  const latestResult = useRef<PresenceScanResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const mounted = useRef(false); const journalSequence = useRef(0);
  const write = useRef<AbortController | null>(null); const ready = useRef(false);
  const saved = useRef<PendingPresenceScan | null>(null); const scope = useRef(key); scope.current = key;
  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; ready.current = false;
    ++journalSequence.current; write.current?.abort(); }; }, []);
  const readJournal = useCallback(async () => {
    if (!mounted.current || !visibility.available.current || write.current) return;
    const request = ++journalSequence.current; ready.current = false; setJournalReady(false);
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error('timeout')), 20_000); });
      const receipt = await Promise.race([gateway.pending(context), timeout]);
      if (!mounted.current || !visibility.available.current || request !== journalSequence.current || scope.current !== key) return;
      saved.current = receipt; ready.current = true; setPending(receipt); setJournalReady(true); setJournalError(null);
    } catch {
      if (mounted.current && visibility.available.current && request === journalSequence.current && scope.current === key)
        setJournalError('Le suivi du dernier pointage doit être relu avant de saisir un code. Actualisez pour réessayer.');
    } finally { if (timer) clearTimeout(timer); }
  }, [gateway, key, visibility.available]);
  useLayoutEffect(() => {
    ready.current = false; setJournalReady(false); ++journalSequence.current;
    write.current?.abort(); write.current = null; setBusy(false);
    saved.current = null; setPending(null); latestResult.current = null; setResult(null); setError(null); setJournalError(null);
    return () => { ready.current = false; ++journalSequence.current; write.current?.abort(); };
  }, [key, visibility.visible, visibility.revision]);
  useEffect(() => { if (visibility.visible) void readJournal(); }, [visibility.visible, visibility.revision, readJournal]);

  const perform = useCallback(async (kind: 'scan' | 'reconcile', code?: string) => {
    if (!mounted.current || !visibility.available.current || write.current || !ready.current
      || kind === 'scan' && saved.current || kind === 'reconcile' && !saved.current) return null;
    const controller = new AbortController(); write.current = controller;
    ready.current = false; ++journalSequence.current; setJournalReady(false); setBusy(true); setError(null);
    if (kind === 'scan') { latestResult.current = null; setResult(null); }
    const attemptId = saved.current?.attemptId;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('timeout')); }, 90_000); });
      const operation = kind === 'scan' ? gateway.scan(context, code ?? '', controller.signal)
        : gateway.reconcile(context, attemptId!, controller.signal);
      const receipt = await Promise.race([operation, timeout]);
      if (!mounted.current || !visibility.available.current || scope.current !== key || write.current !== controller || controller.signal.aborted) return null;
      if (receipt.kind === 'confirmed' && receipt.proof.soignant_id !== context.userId) throw new Error('scope');
      const presented = reconcilePresencePresentation(latestResult.current, receipt);
      latestResult.current = presented.result; setResult(presented.result);
      if (presented.localReadWarning) setError(presented.localReadWarning);
      return presented.result;
    } catch (reason) {
      if (!mounted.current || scope.current !== key || write.current !== controller || !visibility.available.current) return null;
      setError(reason instanceof PresenceWorkflowError ? reason.message : 'Le résultat de la demande ne peut pas encore être confirmé. Relisez le dernier pointage avant de saisir un autre code.');
      return null;
    } finally {
      if (timer) clearTimeout(timer);
      if (write.current === controller) {
        write.current = null;
        if (mounted.current && scope.current === key) { setBusy(false); if (visibility.available.current) void readJournal(); }
      }
    }
  }, [gateway, key, readJournal, visibility.available]);
  return { pending, journalReady, journalError, busy, result, error, readJournal,
    scan: (code: string) => perform('scan', code), reconcile: () => perform('reconcile'),
    visible: visibility.visible, canScan: visibility.visible && journalReady && !journalError && !busy && !pending,
    canReconcile: visibility.visible && journalReady && !journalError && !busy && !!pending };
}

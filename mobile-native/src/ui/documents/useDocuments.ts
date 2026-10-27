import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { DocumentWorkflowError, type DocumentContext, type DocumentDossier, type DocumentMutationResult } from '../../workflows/documents/types';
import type { DocumentScreenGateway, DocumentUploadJournal, PendingDocumentUpload } from './adapters';
import { advanceDocumentVisibility } from './visibility';

type Resource = { data: DocumentDossier | null; loading: boolean; error: string | null };

/** Reads on focus/resume; one explicit mutation at a time; never repeat an uncertain write. */
export function useDocuments(gateway: DocumentScreenGateway, context: DocumentContext, journal: DocumentUploadJournal) {
  const focused = useIsFocused();
  const [visibility, setVisibility] = useState({ active: AppState.currentState === 'active', revision: 0 });
  const { active, revision: visibilityRevision } = visibility;
  const [resource, setResource] = useState<Resource>({ data: null, loading: true, error: null });
  const [busy, setBusy] = useState<string | null>(null);
  const [receipt, setReceipt] = useState<DocumentMutationResult | null>(null);
  const [needsRead, setNeedsRead] = useState(false);
  const [uncertainUpload, setUncertainUpload] = useState<string | null>(null);
  const [journalReady, setJournalReady] = useState(false);
  const [journalError, setJournalError] = useState<string | null>(null);
  const read = useRef<AbortController | null>(null);
  const write = useRef<AbortController | null>(null);
  const generation = useRef(0);
  const mounted = useRef(false);
  const pending = useRef<string | null>(null);
  const journalAvailable = useRef(false);
  const journalGeneration = useRef(0);
  const available = useRef(false);
  const visibilityState = useRef(visibility);

  useLayoutEffect(() => {
    mounted.current = true;
    const sub = AppState.addEventListener('change', state => {
      const nextActive = state === 'active';
      const next = advanceDocumentVisibility(visibilityState.current, nextActive);
      if (next === visibilityState.current) return;
      visibilityState.current = next;
      // Revoke mutation access synchronously, before React renders the resumed screen.
      available.current = false; journalAvailable.current = false; ++journalGeneration.current;
      setJournalReady(false); setVisibility(next);
    });
    return () => {
      mounted.current = false; available.current = false; journalAvailable.current = false;
      ++generation.current; ++journalGeneration.current; read.current?.abort(); write.current?.abort(); sub.remove();
    };
  }, []);

  const readJournal = useCallback(async (owner?: AbortController) => {
    if (!mounted.current || !available.current || (write.current && write.current !== owner)) return;
    const request = ++journalGeneration.current;
    journalAvailable.current = false; setJournalReady(false);
    try {
      const receipt = await journal.read(context.userId);
      if (!mounted.current || !available.current || request !== journalGeneration.current) return;
      pending.current = receipt?.storageKey ?? null;
      journalAvailable.current = true;
      setUncertainUpload(pending.current); setJournalReady(true); setJournalError(null);
    } catch {
      if (mounted.current && available.current && request === journalGeneration.current) { setJournalReady(false); setJournalError('Le suivi de ton dernier envoi est indisponible. Actualise avant d’ajouter un document.'); }
    }
  }, [journal, context.userId]);
  useLayoutEffect(() => {
    available.current = focused && active;
    journalAvailable.current = false; ++journalGeneration.current; setJournalReady(false);
    if (available.current) void readJournal();
    return () => {
      available.current = false; journalAvailable.current = false; ++journalGeneration.current;
    };
  }, [focused, active, visibilityRevision, readJournal]);

  const refresh = useCallback(async () => {
    if (!available.current || write.current) return;
    read.current?.abort();
    const abort = new AbortController(); read.current = abort;
    const request = ++generation.current;
    let timer: ReturnType<typeof setTimeout> | undefined;
    setResource(previous => ({ ...previous, loading: true, error: null }));
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, 20_000); });
      const dossier = await Promise.race([gateway.readDossier(context, abort.signal), timeout]);
      if (!mounted.current || request !== generation.current || abort.signal.aborted) return;
      if (dossier.userId !== context.userId) throw new Error('scope');
      setResource({ data: dossier, loading: false, error: null });
      setNeedsRead(false);
    } catch {
      if (!mounted.current || request !== generation.current) return;
      setResource({ data: null, loading: false, error: 'Vos documents sont temporairement indisponibles. Vérifiez votre connexion puis réessayez.' });
    } finally {
      if (timer) clearTimeout(timer);
      if (read.current === abort) read.current = null;
    }
  }, [gateway, context.userId, focused, active, visibilityRevision]);

  useEffect(() => {
    if (focused && active) void refresh();
    return () => { ++generation.current; read.current?.abort(); read.current = null; };
  }, [focused, active, refresh]);
  useEffect(() => {
    if (focused) return;
    write.current?.abort(); write.current = null; setBusy(null); setNeedsRead(true);
  }, [focused]);

  const perform = useCallback(async (key: string, action: (signal: AbortSignal,
    onPrepared: (receipt: PendingDocumentUpload) => Promise<void>,
    onNotStarted: (receipt: PendingDocumentUpload) => Promise<void>) => Promise<DocumentMutationResult>) => {
    if (!available.current || !mounted.current || write.current || !journalAvailable.current || (pending.current && key !== 'reconcile')) return null;
    read.current?.abort(); read.current = null; ++generation.current; ++journalGeneration.current;
    const abort = new AbortController(); write.current = abort;
    // This operation owns this key. Never use the latest pending.current when clearing later.
    let operationStorageKey = key === 'reconcile' ? pending.current : null;
    const onPrepared = async (receipt: PendingDocumentUpload) => {
      if (abort.signal.aborted || write.current !== abort || (operationStorageKey && operationStorageKey !== receipt.storageKey)) throw new Error('stale-upload');
      operationStorageKey = receipt.storageKey;
      // Await persistence before the gateway may send bytes to Storage, including on app termination.
      await journal.write(context.userId, receipt);
      if (mounted.current && write.current === abort) {
        pending.current = receipt.storageKey; setUncertainUpload(receipt.storageKey);
      }
    };
    const onNotStarted = async (receipt: PendingDocumentUpload) => {
      if (!operationStorageKey || receipt.storageKey !== operationStorageKey) throw new Error('scope');
      // The gateway proves Storage was never invoked. This cleanup must survive abort/unmount.
      // The journal still refuses to erase any newer receipt belonging to this account.
      await journal.clear(context.userId, operationStorageKey);
      if (mounted.current && available.current && (!write.current || write.current === abort)) await readJournal(abort);
    };
    setBusy(key); setReceipt(null);
    setResource(previous => ({ ...previous, loading: false }));
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, 90_000); });
      const result = await Promise.race([action(abort.signal, onPrepared, onNotStarted), timeout]);
      if (!mounted.current || write.current !== abort || abort.signal.aborted) return null;
      if (result.dossier && result.dossier.userId !== context.userId) throw new Error('scope');
      if (operationStorageKey && result.reconciliation && result.reconciliation.storageKey !== operationStorageKey) throw new Error('scope');
      if (operationStorageKey && result.kind === 'confirmed' && result.document?.s3_cle !== operationStorageKey) throw new Error('scope');
      setReceipt(result);
      if (result.dossier) setResource({ data: result.dossier, loading: false, error: null });
      setNeedsRead(result.kind === 'unconfirmed');
      if (result.reconciliation) {
        pending.current = result.reconciliation.storageKey;
        setUncertainUpload(pending.current);
        try { await journal.write(context.userId, result.reconciliation); }
        catch { if (mounted.current) setJournalError('Le suivi de l’envoi n’a pas pu être conservé. Ne renvoie pas le fichier avant sa vérification.'); }
      } else if ((key === 'upload' || key === 'reconcile') && result.kind === 'confirmed' && operationStorageKey) {
        try {
          await journal.clear(context.userId, operationStorageKey);
          // Another screen may already have prepared a newer operation. Preserve its receipt.
          await readJournal(abort);
        } catch { if (mounted.current) setJournalError('Le fichier est enregistré, mais le suivi local doit encore être actualisé. Vérifie l’envoi précédent.'); }
      }
      return result;
    } catch (reason) {
      if (!mounted.current || write.current !== abort) return null;
      const result: DocumentMutationResult = { kind: 'unconfirmed', dossier: null, document: null,
        message: reason instanceof DocumentWorkflowError ? reason.message : 'Action non confirmée. Actualise le dossier avant de réessayer.' };
      setReceipt(result); setNeedsRead(true);
      return result;
    } finally {
      if (timer) clearTimeout(timer);
      if (write.current === abort) {
        write.current = null;
        if (mounted.current) {
          setBusy(null);
          // A focus/resume that occurred during the write still needs its fresh journal read.
          if (available.current && !journalAvailable.current) void readJournal();
        }
      }
    }
  }, [context.userId, journal, readJournal]);

  return { ...resource, busy, receipt, needsRead, uncertainUpload, journalError, journalReady, refresh, perform, readJournal,
    interactive: focused && active && journalReady && !journalError && !resource.loading && !resource.error && !busy && !needsRead && !uncertainUpload };
}

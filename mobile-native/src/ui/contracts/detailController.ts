import { canOfferSignature, matchingRevision } from '../../workflows/contracts/business';
import { ContractWorkflowError, type ContractContext, type ContractDetails, type ContractGateway, type ContractRevision,
  type ContractSignResult, type OtpRequestResult } from '../../workflows/contracts/types';
import { detailMatches, revisionKey } from './presentation';

export interface ContractDetailState {
  active: boolean; loading: boolean; details: ContractDetails | null; error: string | null;
  busy: 'request' | 'sign' | null; presented: ContractRevision | null; accepted: ContractRevision | null;
  readerError: string | null; needsRead: boolean; result: OtpRequestResult | ContractSignResult | null;
}
/** UI lifecycle only; server rights, revision and TEST admission are checked again by the gateway. */
export function createContractDetailController(gateway: ContractGateway, source: ContractContext, contractId: string) {
  const context = { ...source }; const listeners = new Set<() => void>();
  let state: ContractDetailState = { active: false, loading: false, details: null, error: null, busy: null,
    presented: null, accepted: null, readerError: null, needsRead: false, result: null };
  let generation = 0, request: AbortController | null = null, disposed = false;
  const emit = (patch: Partial<ContractDetailState>) => { state = { ...state, ...patch }; listeners.forEach(listener => listener()); };
  const current = (sequence: number, abort: AbortController) => !disposed && state.active && sequence === generation && !abort.signal.aborted;
  const reset = () => ({ presented: null, accepted: null, readerError: null });
  const sourceMatches = (details: ContractDetails) => !details.original || details.original.source ===
    (gateway.mode === 'demo' ? 'synthetic' : 'database-and-storage');
  async function bounded<T>(operation: Promise<T>, abort: AbortController, milliseconds: number): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancelled: (() => void) | undefined;
    try { return await Promise.race([operation, new Promise<never>((_, reject) => {
      cancelled = () => reject(new Error('aborted'));
      abort.signal.addEventListener('abort', cancelled, { once: true });
      if (abort.signal.aborted) cancelled();
      timer = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, milliseconds);
    })]); } finally {
      if (timer) clearTimeout(timer);
      if (cancelled) abort.signal.removeEventListener('abort', cancelled);
    }
  }
  const reload = async () => {
    if (disposed || !state.active || state.busy) return;
    request?.abort(); const abort = new AbortController(); request = abort; const sequence = ++generation;
    emit({ ...reset(), loading: true, error: null, details: null, result: null });
    try {
      const details = await bounded(gateway.read(context, contractId, abort.signal), abort, 20_000);
      if (!current(sequence, abort)) return;
      if (!detailMatches(context, contractId, details) || !sourceMatches(details)) throw new Error('scope');
      emit({ details, loading: false, needsRead: false });
    } catch (error) {
      if (disposed || !state.active || sequence !== generation) return;
      emit({ details: null, loading: false, needsRead: true, error: error instanceof ContractWorkflowError
        ? error.message : 'Le contrat ne peut pas être actualisé. Vérifiez votre connexion puis réessayez.' });
    } finally { if (request === abort) request = null; }
  };
  const consentReady = () => !!state.details && state.active && !state.loading && !state.busy && !state.needsRead
    && !state.readerError && canOfferSignature(state.details) && !!state.accepted && !!state.presented
    && matchingRevision(state.details.original, state.accepted) && revisionKey(state.accepted) === revisionKey(state.presented);
  const perform = async (kind: 'request' | 'sign', code?: string) => {
    if (!consentReady()) return;
    if (kind === 'sign' && !/^[0-9]{6}$/.test(code ?? '')) return;
    const consent = { accepted: true as const, revision: { ...state.accepted! } };
    const abort = new AbortController(); request?.abort(); request = abort; const sequence = ++generation;
    emit({ busy: kind, result: null, error: null });
    try {
      const operation = kind === 'request' ? gateway.requestOtp(context, consent, abort.signal)
        : gateway.sign(context, { ...consent, code: code! }, abort.signal);
      const result = await bounded<OtpRequestResult | ContractSignResult>(operation, abort, 60_000);
      if (!current(sequence, abort)) return;
      if (result.contract && (!detailMatches(context, contractId, result.contract) || !sourceMatches(result.contract))) throw new Error('scope');
      const sameRevision = result.contract && matchingRevision(result.contract.original, consent.revision);
      emit({ result, details: result.contract ?? state.details, busy: null, needsRead: result.kind === 'unconfirmed' || !result.contract,
        ...(!sameRevision || result.kind === 'confirmed' || result.kind === 'already_signed' ? reset() : {}) });
    } catch (error) {
      if (disposed || !state.active || sequence !== generation) return;
      emit({ busy: null, needsRead: true, error: error instanceof ContractWorkflowError ? error.message
        : 'La demande ne peut pas être confirmée. Actualisez le contrat avant toute nouvelle action.' });
    } finally { if (request === abort) request = null; }
  };
  return {
    getSnapshot: () => state,
    subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    activate() { if (!disposed && !state.active) { emit({ active: true }); void reload(); } },
    deactivate() {
      ++generation; request?.abort(); request = null;
      emit({ ...reset(), active: false, details: null, loading: false, busy: null, result: null, error: null, needsRead: true });
    },
    dispose() { disposed = true; ++generation; request?.abort(); request = null; listeners.clear(); state = { ...state, ...reset(), active: false, details: null, result: null }; },
    reload,
    presented(revision: ContractRevision) {
      if (disposed || !state.active || state.loading || !matchingRevision(state.details?.original ?? null, revision)) return;
      if (revisionKey(state.presented) === revisionKey(revision) && !state.readerError) return;
      emit({ presented: { ...revision }, accepted: null, readerError: null });
    },
    unavailable(revision: ContractRevision, message: string) {
      if (!disposed && state.active && matchingRevision(state.details?.original ?? null, revision)) {
        emit({ presented: null, accepted: null, readerError: message });
      }
    },
    accept(value: boolean) {
      if (disposed || !state.active || state.loading || state.busy || state.needsRead || !state.presented || !state.details
        || !canOfferSignature(state.details) || !matchingRevision(state.details.original, state.presented)) return;
      emit({ accepted: value ? { ...state.presented } : null });
    },
    requestOtp: () => perform('request'), sign: (code: string) => perform('sign', code),
  };
}

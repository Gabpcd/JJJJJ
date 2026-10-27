import type { MissionReadContext } from '../../data/types';
import type { ApplicationSnapshot, ApplyInput, ApplyResult, ContractOption, MissionWorkflowGateway } from './types';

export interface ApplicationState {
  data: ApplicationSnapshot | null; loading: boolean; submitting: boolean;
  error: string | null; result: ApplyResult | null; options: ContractOption[]; needsRecheck: boolean;
}

/** Screen lifecycle boundary: one action at a time and no late response after account/mission change. */
export function createApplicationController(gateway: MissionWorkflowGateway, context: MissionReadContext, missionId: string) {
  let state: ApplicationState = { data: null, loading: true, submitting: false, error: null, result: null, options: [], needsRecheck: false };
  let alive = true; let generation = 0; let read: AbortController | null = null; let mutation: AbortController | null = null;
  const listeners = new Set<() => void>();
  const emit = (patch: Partial<ApplicationState>) => { if (alive) { state = { ...state, ...patch }; listeners.forEach(listener => listener()); } };
  return {
    activate() { alive = true; },
    getSnapshot: () => state,
    subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; },
    async refresh() {
      if (!alive || state.submitting) return;
      read?.abort(); const abort = new AbortController(); read = abort; const current = ++generation;
      emit({ loading: true, error: null, options: [], result: null });
      try {
        const data = await gateway.readApplication(context, missionId, abort.signal);
        if (!alive || abort.signal.aborted || current !== generation) return;
        emit({ data, loading: false, needsRecheck: false });
      } catch (error) {
        if (!alive || abort.signal.aborted || current !== generation) return;
        emit({ loading: false, error: error instanceof Error ? error.message : 'La mission ne peut pas être chargée.' });
      }
    },
    async submit(input: ApplyInput) {
      if (!alive || state.loading || state.submitting || state.needsRecheck || !state.data) return;
      read?.abort(); const current = ++generation; const abort = new AbortController(); mutation = abort;
      emit({ submitting: true, error: null, result: null });
      try {
        const result = await gateway.apply(context, state.data, input, abort.signal);
        if (!alive || abort.signal.aborted || current !== generation) return;
        emit({ submitting: false, data: result.snapshot ?? state.data, result,
          options: result.kind === 'choice' ? result.options : [], needsRecheck: result.kind === 'unconfirmed',
          error: result.kind === 'rejected' || result.kind === 'unconfirmed' ? result.message : null });
      } catch (error) {
        if (!alive || abort.signal.aborted || current !== generation) return;
        emit({ submitting: false, needsRecheck: true, error: error instanceof Error ? error.message : 'Rechargez la mission pour vérifier son état.' });
      }
    },
    async retryEmails() {
      if (!alive || state.loading || state.submitting || !state.data) return;
      const current = ++generation; const abort = new AbortController(); mutation = abort;
      emit({ submitting: true, error: null });
      try {
        const acceptanceEmails = await gateway.retryAcceptanceEmails(context, missionId, abort.signal);
        if (!alive || abort.signal.aborted || current !== generation || !state.data) return;
        emit({ submitting: false, data: { ...state.data, acceptanceEmails } });
      } catch (error) {
        if (!alive || abort.signal.aborted || current !== generation) return;
        emit({ submitting: false, error: error instanceof Error ? error.message : 'Les emails ne peuvent pas être vérifiés.' });
      }
    },
    dispose() { alive = false; ++generation; read?.abort(); mutation?.abort(); listeners.clear(); },
  };
}

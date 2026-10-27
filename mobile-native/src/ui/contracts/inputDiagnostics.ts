// Bounded, opt-in demo evidence. This API never accepts input text or identities.
const RESET_REASONS = ['app-active', 'app-nonactive', 'focus-cleanup', 'revision-change',
  'submit', 'refresh', 'error-reload', 'reconcile', 'request-otp'] as const;
export type ContractCodeResetReason = typeof RESET_REASONS[number];
type Entry = { sequence: number; elapsedMs: number; event: 'native-change' | 'text-change' | 'committed' | 'reset';
  length?: number; eventCount?: number; reason?: ContractCodeResetReason };
export function createContractInputDiagnostics(options: {
  gatewayMode: string; appMode: string | undefined; flag: string | undefined; emit: (entry: Entry) => void;
}) {
  const enabled = options.gatewayMode === 'demo' && options.appMode === 'demo' && options.flag === '1';
  const started = Date.now(); let sequence = 0;
  const validLength = (value: number) => Number.isSafeInteger(value) && value >= 0 && value <= 1024;
  const write = (entry: Omit<Entry, 'sequence' | 'elapsedMs'>) => {
    if (!enabled || sequence >= 128) return;
    // A diagnostic sink must never affect editing, reset, or signing behavior.
    try { options.emit({ sequence: ++sequence, elapsedMs: Math.max(0, Date.now() - started), ...entry }); }
    catch { /* Existing UI assertions remain authoritative. */ }
  };
  return {
    nativeChange(length: number, eventCount: number) {
      if (validLength(length) && Number.isSafeInteger(eventCount) && eventCount >= 0) {
        write({ event: 'native-change', length, eventCount });
      }
    },
    textChange(length: number) { if (validLength(length)) write({ event: 'text-change', length }); },
    committed(length: number) { if (validLength(length)) write({ event: 'committed', length }); },
    reset(reason: ContractCodeResetReason) {
      if (RESET_REASONS.includes(reason)) write({ event: 'reset', reason });
    },
  };
}

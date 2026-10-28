// Bounded, opt-in demo evidence. This API never accepts input text or identities.
const RESET_REASONS = ['app-active', 'app-nonactive', 'focus-cleanup', 'revision-change',
  'submit', 'refresh', 'error-reload', 'reconcile', 'request-otp'] as const;
export type ContractCodeResetReason = typeof RESET_REASONS[number];
type Entry = { sequence: number; elapsedMs: number; startedAtMs: number; atMs: number; event: 'native-change' | 'text-change' | 'committed' | 'reset' | 'key-press' | 'focus' | 'blur' | 'selection';
  length?: number; active?: boolean; blocked?: boolean; eventCount?: number; reason?: ContractCodeResetReason;
  count?: number; start?: number; end?: number };
export function createContractInputDiagnostics(options: {
  gatewayMode: string; appMode: string | undefined; flag: string | undefined; emit: (entry: Entry) => void;
}) {
  const enabled = options.gatewayMode === 'demo' && options.appMode === 'demo' && options.flag === '1';
  const started = Date.now(); let sequence = 0;
  const counts = { 'key-press': 0, focus: 0, blur: 0, selection: 0 };
  const validLength = (value: number) => Number.isSafeInteger(value) && value >= 0 && value <= 1024;
  const write = (entry: Omit<Entry, 'sequence' | 'elapsedMs' | 'startedAtMs' | 'atMs'>) => {
    if (!enabled || sequence >= 128) return;
    // A diagnostic sink must never affect editing, reset, or signing behavior.
    try { const atMs = Date.now(); options.emit({ sequence: ++sequence, elapsedMs: Math.max(0, atMs - started), startedAtMs: started, atMs, ...entry }); }
    catch { /* Existing UI assertions remain authoritative. */ }
  };
  const observation = (event: keyof typeof counts, fields: { length?: number; start?: number; end?: number } = {}) => {
    if (!enabled || sequence >= 128) return;
    write({ event, count: ++counts[event], ...fields });
  };
  return {
    enabled,
    keyPress(length: number) { if (validLength(length)) observation('key-press', { length }); },
    focus() { observation('focus'); },
    blur() { observation('blur'); },
    selection(start: number, end: number) {
      if (validLength(start) && validLength(end) && start <= end) observation('selection', { start, end });
    },
    nativeChange(length: number, eventCount: number) {
      if (validLength(length) && Number.isSafeInteger(eventCount) && eventCount >= 0) {
        write({ event: 'native-change', length, eventCount });
      }
    },
    textChange(length: number) { if (validLength(length)) write({ event: 'text-change', length }); },
    committed(length: number, active?: boolean, blocked?: boolean) {
      if (validLength(length) && (active === undefined || typeof active === 'boolean')
        && (blocked === undefined || typeof blocked === 'boolean')) {
        write({ event: 'committed', length, ...(active === undefined ? {} : { active }),
          ...(blocked === undefined ? {} : { blocked }) });
      }
    },
    reset(reason: ContractCodeResetReason) {
      if (RESET_REASONS.includes(reason)) write({ event: 'reset', reason });
    },
  };
}

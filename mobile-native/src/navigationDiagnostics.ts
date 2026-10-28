// Opt-in simulator diagnostics only. Never record users, route params or tokens.
const enabled = process.env.EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS === '1'
  && process.env.EXPO_PUBLIC_JOLENE_MODE === 'demo';
let sequence = 0;
const started = Date.now();

export function traceNativeNavigation(event: string, detail?: string) {
  if (!enabled || sequence >= 512) return;
  const atMs = Date.now();
  console.log('[jolene-native-navigation]', JSON.stringify({
    sequence: ++sequence, elapsedMs: atMs - started, startedAtMs: started, atMs, event, detail,
  }));
}

type NavigationTree = { index?: number; routes: readonly { name: string; state?: NavigationTree }[] };
export function traceNavigationState(state: NavigationTree | undefined) {
  if (!enabled || !state) return;
  const path: string[] = [];
  let cursor: NavigationTree | undefined = state;
  while (cursor && path.length < 8) {
    const route: NavigationTree['routes'][number] | undefined = cursor.routes[cursor.index ?? 0];
    if (!route) break;
    path.push(`${route.name}[${cursor.index ?? 0}/${cursor.routes.length}]`);
    cursor = route.state;
  }
  traceNativeNavigation('state', path.join('/'));
}

export const diagnosticStackListeners = ({ route }: { route: { name: string } }) => ({
  transitionStart: ({ data }: { data: { closing: boolean } }) => traceNativeNavigation('transitionStart', `${route.name}:${data.closing ? 'pop' : 'push'}`),
  transitionEnd: ({ data }: { data: { closing: boolean } }) => traceNativeNavigation('transitionEnd', `${route.name}:${data.closing ? 'pop' : 'push'}`),
  gestureCancel: () => traceNativeNavigation('gestureCancel', route.name),
});
export const diagnosticTouch = enabled ? () => traceNativeNavigation('rootTouch') : undefined;

// Login-only observations share the existing bounded demo stream. Never retain
// touch coordinates, native event objects or form values, and never claim a responder.
const loginDiagnostic = (event: string) => enabled ? () => {
  try { traceNativeNavigation(event); } catch { /* Observation must not block the tap handler. */ }
} : undefined;
export const diagnosticLoginTouch = {
  start: loginDiagnostic('loginTouchStart'),
  end: loginDiagnostic('loginTouchEnd'),
  cancel: loginDiagnostic('loginTouchCancel'),
  dragStart: loginDiagnostic('loginScrollDragStart'),
};
export const diagnosticEnterDemo = {
  pressIn: loginDiagnostic('enterDemoPressIn'),
  pressOut: loginDiagnostic('enterDemoPressOut'),
  handler: loginDiagnostic('enterDemoHandlerEntry'),
};

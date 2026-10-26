import { createContext, useContext, useEffect, useSyncExternalStore, type PropsWithChildren } from 'react';
import { AppState } from 'react-native';
import type { NativeSessionController } from './controller';

const SessionContext = createContext<NativeSessionController | null>(null);

export function SessionProvider({ controller, children }: PropsWithChildren<{ controller: NativeSessionController }>) {
  useEffect(() => {
    controller.start();
    let previousState = AppState.currentState;
    controller.setForeground(previousState === 'active');
    const subscription = AppState.addEventListener('change', (state) => {
      controller.setForeground(state === 'active');
      if (state === 'active' && previousState !== 'active') void controller.revalidate();
      previousState = state;
    });
    return () => { subscription.remove(); controller.stop(); };
  }, [controller]);
  return <SessionContext.Provider value={controller}>{children}</SessionContext.Provider>;
}

export function useSession() {
  const controller = useContext(SessionContext);
  if (!controller) throw new Error('SessionProvider manquant.');
  const snapshot = useSyncExternalStore(controller.subscribe, controller.getSnapshot, controller.getSnapshot);
  return { ...snapshot, snapshot, signIn: controller.signIn, enterDemo: controller.enterDemo, signOut: controller.signOut, retry: controller.revalidate };
}

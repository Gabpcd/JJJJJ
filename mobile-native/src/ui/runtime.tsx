import { createContext, useContext, useState, type PropsWithChildren } from 'react';
import type { NativeRuntime } from '../session/nativeRuntime';
import { DemoProfileGateway, SupabaseProfileGateway, type ProfileGateway } from '../caregiver/profile';
import { EstablishmentGateway } from '../establishment';
import { DemoMissionWorkflowGateway, SupabaseMissionWorkflowGateway, type MissionWorkflowGateway } from '../workflows/missions';

type Services = { runtime: NativeRuntime; profile: ProfileGateway; establishment: EstablishmentGateway; missions: MissionWorkflowGateway };
const RuntimeContext = createContext<NativeRuntime | null>(null);
const ServicesContext = createContext<Services | null>(null);
export function RuntimeProvider({ runtime, children }: PropsWithChildren<{ runtime: NativeRuntime }>) {
  return <RuntimeContext.Provider value={runtime}>{children}</RuntimeContext.Provider>;
}
export function useNativeRuntime() {
  const runtime = useContext(RuntimeContext);
  if (!runtime) throw new Error('Configuration native absente.');
  return runtime;
}
/** Mounted once per authenticated epoch so synthetic data never crosses accounts. */
export function AccountServicesProvider({ children }: PropsWithChildren) {
  const runtime = useNativeRuntime();
  const [services] = useState<Services>(() => ({ runtime,
    profile: runtime.client ? new SupabaseProfileGateway(runtime.client) : new DemoProfileGateway(),
    establishment: new EstablishmentGateway(runtime.client),
    missions: runtime.client ? new SupabaseMissionWorkflowGateway(runtime.client) : new DemoMissionWorkflowGateway(runtime.gateway),
  }));
  return <ServicesContext.Provider value={services}>{children}</ServicesContext.Provider>;
}
export function useAccountServices() {
  const services = useContext(ServicesContext);
  if (!services) throw new Error('Services du compte absents.');
  return services;
}

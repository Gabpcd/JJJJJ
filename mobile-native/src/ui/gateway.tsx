import { createContext, useContext, type ReactNode } from 'react';
import type { MissionGateway } from '../data/types';

const GatewayContext = createContext<MissionGateway | null>(null);

export function GatewayProvider({ gateway, children }: { gateway: MissionGateway; children: ReactNode }) {
  return <GatewayContext.Provider value={gateway}>{children}</GatewayContext.Provider>;
}

export function useGateway() {
  const gateway = useContext(GatewayContext);
  if (!gateway) throw new Error('MissionGateway manquant');
  return gateway;
}

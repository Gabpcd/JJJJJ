import type { PresenceContext, PresenceGateway } from '../../workflows/presence/types';

/** Same business methods; demo is a deliberately separate, in-memory implementation. */
export type PresenceScreenGateway = Omit<PresenceGateway, 'mode'> & { readonly mode: 'supabase' | 'demo' };
export interface PresenceScreenProps {
  gateway: PresenceScreenGateway; context: PresenceContext;
  onMission: (missionId: string) => void;
}
export function presenceScopeKey(gateway: PresenceScreenGateway, context: PresenceContext): string {
  return JSON.stringify([gateway.mode, context.kind, context.userId, context.epoch,
    context.kind === 'etablissement' ? context.etablissementId : null]);
}

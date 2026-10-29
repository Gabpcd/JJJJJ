import type { PresenceScanResult } from '../../workflows/presence/types';

export interface PresenceVisibility { active: boolean; revision: number }
/** Each interruption survives React batching even if the final active boolean is unchanged. */
export function advancePresenceVisibility(previous: PresenceVisibility, active: boolean): PresenceVisibility {
  return previous.active === active ? previous : { active, revision: previous.revision + 1 };
}
export function reconcilePresencePresentation(previous: PresenceScanResult | null, next: PresenceScanResult): {
  result: PresenceScanResult; localReadWarning: string | null;
} {
  if (previous?.kind === 'confirmed' && previous.attemptId === next.attemptId && next.kind !== 'confirmed') {
    return { result: previous, localReadWarning: 'Le pointage reste enregistré. Son suivi local ne peut pas encore être relu ; aucun nouveau pointage n’a été envoyé.' };
  }
  return { result: next, localReadWarning: null };
}

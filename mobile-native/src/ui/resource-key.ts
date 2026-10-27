import type { MissionFilters, MissionReadContext } from '../data/types';

type MissionResource = { kind: 'list'; filters: MissionFilters } | { kind: 'detail'; id: string };

/** All profile fields can influence server visibility; object identity must not. */
export function missionResourceKey(epoch: number, context: MissionReadContext, resource: MissionResource): string {
  return JSON.stringify({
    epoch,
    userId: context.userId,
    email: context.email,
    profile: Object.fromEntries(Object.entries(context.profile).sort(([left], [right]) => left.localeCompare(right))),
    resource: resource.kind === 'detail' ? resource : {
      kind: resource.kind,
      filters: Object.fromEntries(Object.entries(resource.filters).sort(([left], [right]) => left.localeCompare(right))),
    },
  });
}

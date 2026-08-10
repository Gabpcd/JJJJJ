const PREFIXES_MISSION_TEST = ['[playwright-test]', '[pw-test:'] as const;

export function estComptePlaywright(email: string | null | undefined): boolean {
  return email?.startsWith('playwright-') ?? false;
}

export function estMissionPlaywright(mission: { intitule?: string | null }): boolean {
  const intitule = mission.intitule ?? '';
  return PREFIXES_MISSION_TEST.some((prefixe) => intitule.startsWith(prefixe));
}

export function filtrerMissionsPlaywright<T extends { intitule?: string | null }>(
  missions: T[],
  email: string | null | undefined,
): T[] {
  return estComptePlaywright(email)
    ? missions
    : missions.filter((mission) => !estMissionPlaywright(mission));
}

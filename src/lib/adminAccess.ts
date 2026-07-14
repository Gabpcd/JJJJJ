export const ADMIN_ACCESS = {
  DASHBOARD: 'Dashboard',
  UTILISATEURS: 'Utilisateurs',
  MISSIONS: 'Missions',
  LITIGES: 'Litiges & contrats',
  FINANCES: 'Finances',
  MESSAGERIE: 'Messagerie',
  TECHNIQUE: 'Conformité & Technique',
  FONDATEUR: 'Fondateur',
} as const;

export type AdminAccessGroup = (typeof ADMIN_ACCESS)[keyof typeof ADMIN_ACCESS];

export const ADMIN_ACCESS_GROUPS = Object.freeze(
  Object.values(ADMIN_ACCESS),
) as readonly AdminAccessGroup[];

export const ADMIN_ACCESS_DESCRIPTIONS: ReadonlyArray<{
  cle: AdminAccessGroup;
  description: string;
}> = [
  { cle: ADMIN_ACCESS.DASHBOARD, description: 'Dashboard admin' },
  { cle: ADMIN_ACCESS.UTILISATEURS, description: 'Utilisateurs, modération, signalements, scores' },
  { cle: ADMIN_ACCESS.MISSIONS, description: 'Missions, pool urgence, plannings, pointage' },
  { cle: ADMIN_ACCESS.LITIGES, description: 'Litiges, contrats, templates' },
  { cle: ADMIN_ACCESS.FINANCES, description: 'Facturation, impayées, affacturage, commissions' },
  { cle: ADMIN_ACCESS.MESSAGERIE, description: 'Messagerie admin' },
  { cle: ADMIN_ACCESS.TECHNIQUE, description: 'Système : conformité, audits, emails, API' },
  { cle: ADMIN_ACCESS.FONDATEUR, description: 'Pilotage : cockpit, acquisition, équipe, levée' },
];

export function aTousLesAccesAdmin(groupes: readonly string[] | null | undefined): boolean {
  if (!groupes) return false;
  return ADMIN_ACCESS_GROUPS.every((groupe) => groupes.includes(groupe));
}

import {
  ADMIN_LAUNCH_ACCESS_GROUPS,
  hasFullLaunchAdminAccess,
  isCanonicalPlatformAdminRole,
  isConfirmedAuthUser,
} from './admin-auth.ts';

Deno.test('admin lancement: seul ADMIN_PLATEFORME est un rôle canonique', () => {
  if (!isCanonicalPlatformAdminRole('ADMIN_PLATEFORME')) {
    throw new Error('ADMIN_PLATEFORME devrait être accepté');
  }
  for (const role of ['ADMIN', 'admin_plateforme', '', null]) {
    if (isCanonicalPlatformAdminRole(role)) {
      throw new Error(`Rôle non canonique accepté: ${String(role)}`);
    }
  }
});

Deno.test('admin lancement: un compte Auth non confirmé est refusé', () => {
  if (isConfirmedAuthUser(null) || isConfirmedAuthUser({})) {
    throw new Error('Compte sans confirmation accepté');
  }
  if (isConfirmedAuthUser({ email_confirmed_at: null })) {
    throw new Error('Confirmation nulle acceptée');
  }
  if (!isConfirmedAuthUser({ email_confirmed_at: '2026-07-14T00:00:00Z' })) {
    throw new Error('Compte confirmé refusé');
  }
});

Deno.test('admin lancement: equipe_admin est obligatoire, active et 8/8', () => {
  const full = [...ADMIN_LAUNCH_ACCESS_GROUPS];
  const cases: Array<[string, Parameters<typeof hasFullLaunchAdminAccess>[0], boolean]> = [
    ['absent', null, false],
    ['inactif', { actif: false, acces_groupes: full }, false],
    ['groupes absents', { actif: true, acces_groupes: null }, false],
    ['incomplet', { actif: true, acces_groupes: full.slice(0, -1) }, false],
    ['complet', { actif: true, acces_groupes: full }, true],
    ['complet avec droits supplémentaires', { actif: true, acces_groupes: [...full, 'Futur'] }, true],
  ];

  for (const [label, equipe, attendu] of cases) {
    const obtenu = hasFullLaunchAdminAccess(equipe);
    if (obtenu !== attendu) {
      throw new Error(`${label}: attendu ${attendu}, obtenu ${obtenu}`);
    }
  }
});

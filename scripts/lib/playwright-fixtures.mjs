/** Les deux identités techniques fixes seulement ; jamais une entrée opérateur. */
export const FIXTURES = Object.freeze({
  etab: Object.freeze({ key: 'etab', email: 'playwright-etab@jolene.app', role: 'ADMIN_ETABLISSEMENT', table: 'etablissements' }),
  soignant: Object.freeze({ key: 'soignant', email: 'playwright-soignant@jolene.app', role: 'SOIGNANT', table: 'soignants' }),
});

export function requireFixturePassword(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value)) {
    throw new Error('FIXTURE_PRIVATE_SECRET_REQUIRED_64_HEX');
  }
  return value;
}

function fail() { throw new Error('FIXTURE_IDENTITY_PREFLIGHT_FAILED'); }

/** Réponse distante jamais reproduite dans les diagnostics. Aucune écriture. */
async function inspectFixtureAccount(admin, fixture) {
  if (!Object.values(FIXTURES).includes(fixture)) fail();
  const lookup = await admin.rpc('fn_admin_get_user_id_by_email', { p_email: fixture.email });
  if (lookup.error || typeof lookup.data !== 'string' || !/^[0-9a-f-]{36}$/i.test(lookup.data)) fail();
  const userId = lookup.data;
  const auth = await admin.auth.admin.getUserById(userId);
  const user = auth.data?.user;
  if (auth.error || !user || user.id !== userId || user.email !== fixture.email
    || user.app_metadata?.role !== fixture.role
    || user.user_metadata?.role === 'ADMIN_PLATEFORME'
    || user.deleted_at) fail();
  const profile = await admin.from(fixture.table).select('id,est_compte_test').eq('id', userId).maybeSingle();
  if (profile.error || profile.data?.id !== userId || profile.data?.est_compte_test !== true) fail();
  // Même un ancien membre désactivé de l'équipe plateforme est exclu.
  const platform = await admin.from('equipe_admin').select('user_id').eq('user_id', userId).limit(1);
  if (platform.error || !Array.isArray(platform.data) || platform.data.length !== 0) fail();
  const memberships = await admin.from('membres_etablissement')
    .select('etablissement_id,etablissements!inner(est_compte_test)').eq('user_id', userId).eq('actif', true);
  if (memberships.error || !Array.isArray(memberships.data)
    || memberships.data.some((m) => m.etablissements?.est_compte_test !== true)) fail();
  return userId;
}

export async function preflightAllFixtures(admin) {
  const ids = [];
  for (const fixture of Object.values(FIXTURES)) ids.push(await assertFixtureAccount(admin, fixture));
  if (new Set(ids).size !== 2) fail();
  return ids;
}

export async function assertFixtureAccount(admin, fixture) {
  try { return await inspectFixtureAccount(admin, fixture); } catch { fail(); }
}

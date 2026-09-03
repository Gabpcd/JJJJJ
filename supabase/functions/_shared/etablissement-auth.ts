/** Autorisation uniforme des Edge Functions rattachées à un établissement. */
export async function canManageEstablishment(
  admin: any,
  userId: string | null,
  etablissementId: string,
): Promise<boolean> {
  if (!userId) return false;

  // L'administrateur plateforme pilote seul les opérations Jolene. Les Edge
  // Functions reçoivent un client service_role, donc elles doivent reconnaître
  // explicitement le même rôle actif que les RPC `est_admin()` au lieu
  // d'exiger artificiellement une appartenance à chaque établissement.
  const [{ data: authData, error: authError }, { data: adminEntry, error: adminError }] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin
      .from('equipe_admin')
      .select('user_id')
      .eq('user_id', userId)
      .eq('actif', true)
      .maybeSingle(),
  ]);
  if (!authError
    && !adminError
    && authData?.user?.app_metadata?.role === 'ADMIN_PLATEFORME'
    && adminEntry) {
    return true;
  }

  // Compatibilité des comptes historiques : l'utilisateur Auth est aussi la
  // clé primaire de son établissement.
  if (userId === etablissementId) return true;

  const { data: membre, error } = await admin.from('membres_etablissement')
    .select('role')
    .eq('etablissement_id', etablissementId)
    .eq('user_id', userId)
    .eq('actif', true)
    .maybeSingle();
  if (error || !membre) return false;
  return ['PROPRIETAIRE', 'ADMIN_GROUPE'].includes(String((membre as Record<string, unknown>).role || ''));
}

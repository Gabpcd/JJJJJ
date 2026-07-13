/** Autorisation uniforme des Edge Functions rattachées à un établissement. */
export async function canManageEstablishment(
  admin: any,
  userId: string | null,
  etablissementId: string,
): Promise<boolean> {
  if (!userId) return false;

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

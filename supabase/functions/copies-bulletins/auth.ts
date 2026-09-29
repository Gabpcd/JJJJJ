type User = { id: string; deleted_at?: string | null; banned_until?: string | null };
/** Auth distant courant obligatoire : aucune confiance dans un JWT décodé. */
export async function authentifierCopie(
  req: Request,
  getUser: (bearer: string) => Promise<{ data: { user: User | null }; error: unknown }>,
  serviceKey: string,
): Promise<string | null> {
  const bearer = req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!bearer || bearer === serviceKey || bearer.startsWith('sb_secret_')) return null;
  const { data, error } = await getUser(bearer);
  const user = data.user;
  if (error || !user || user.deleted_at) return null;
  if (user.banned_until && (!Number.isFinite(Date.parse(user.banned_until)) || Date.parse(user.banned_until) > Date.now())) return null;
  return user.id;
}

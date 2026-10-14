const STAGING_URL = 'https://mejpriaetwgtcstbgfid.supabase.co';
type RpcClient = { rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{data: unknown; error: unknown}> };

/** Read-only, caller-bound admission; fails closed when supplement is absent. */
export async function readSignatureSmsStagingAdmission(client: RpcClient, url: string, contratId: string, now = Date.now()) {
  if (url !== STAGING_URL || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(contratId)) return null;
  try {
    const {data, error} = await client.rpc('fn_admission_otp_signature_recette', {p_contrat_id: contratId});
    if (error || !data || typeof data !== 'object' || Array.isArray(data)) return null;
    const result = data as Record<string, unknown>;
    if (result.admitted !== true || typeof result.expires_at !== 'string' || !Number.isInteger(result.remaining)
      || Number(result.remaining) < 0 || Number(result.remaining) > 2
      || typeof result.can_send !== 'boolean' || typeof result.can_validate !== 'boolean'
      || result.can_send !== (Number(result.remaining) > 0) || (!result.can_send && !result.can_validate)) return null;
    const expiresAt = Date.parse(result.expires_at);
    if (!Number.isFinite(expiresAt) || expiresAt <= now || expiresAt > now + 60 * 60_000) return null;
    return {expiresAt, canSend: result.can_send, canValidate: result.can_validate};
  } catch { return null; }
}

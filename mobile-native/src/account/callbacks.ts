import { NativeAccountError } from './errors';

/** Must be allowlisted in STAGING Auth before email integration is exercised. */
export const CONFIRMATION_CALLBACK = 'jolene-native-pilot://auth/confirm';
export const RECOVERY_CALLBACK = 'jolene-native-pilot://auth/recovery';
export type NativeAuthCallback = { kind: 'code'; code: string } | { kind: 'token_hash'; tokenHash: string; type: 'signup' | 'email' | 'recovery' };
export function parseNativeAuthCallback(raw: string, purpose: 'confirmation' | 'recovery'): NativeAuthCallback {
  let url: URL;
  try { url = new URL(raw); } catch { throw new NativeAccountError('Le lien reçu est invalide.'); }
  const target = purpose === 'confirmation' ? CONFIRMATION_CALLBACK : RECOVERY_CALLBACK;
  if (`${url.protocol}//${url.host}${url.pathname}` !== target || url.username || url.password || url.port || url.hash) {
    throw new NativeAccountError('Ce lien ne correspond pas à ce parcours natif.');
  }
  if (url.searchParams.has('error') || url.searchParams.has('error_code')) throw new NativeAccountError('Ce lien est invalide ou expiré. Demandez un nouveau lien.');
  const type = url.searchParams.get('type');
  if (type && !(purpose === 'recovery' ? type === 'recovery' : type === 'signup' || type === 'email')) throw new NativeAccountError('Ce lien ne correspond pas à cette opération.');
  const code = url.searchParams.get('code');
  const tokenHash = url.searchParams.get('token_hash');
  if (code && !tokenHash && code.length <= 4096) return { kind: 'code', code };
  if (tokenHash && !code && tokenHash.length <= 4096 && type) return { kind: 'token_hash', tokenHash, type: type as 'signup' | 'email' | 'recovery' };
  throw new NativeAccountError('Le lien reçu ne contient pas de confirmation valide.');
}

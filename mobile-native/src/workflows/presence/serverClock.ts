import { PRESENCE_STAGING_ORIGIN } from './business';
import { PresenceWorkflowError, type PresenceClockPort } from './types';

/** The Date header is an advisory gateway clock. Only PostgreSQL timestamps prove a scan. */
export function createPresenceServerClock(publishableKey: string, request: typeof fetch = fetch): PresenceClockPort {
  if (!/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(publishableKey)) throw new PresenceWorkflowError('INVALID_SCOPE', 'Configuration de TEST invalide.');
  return { async read({ userId, authorization, signal }) {
    const controller = new AbortController();
    const abort = () => controller.abort(); signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) controller.abort();
    const timeout = setTimeout(abort, 15_000);
    try {
      const url = `${PRESENCE_STAGING_ORIGIN}/auth/v1/user`;
      const response = await request(url, { method: 'GET', headers: { apikey: publishableKey, Authorization: authorization },
        signal: controller.signal, redirect: 'error', cache: 'no-store' });
      if (!response.ok || response.url && response.url !== url) throw new Error('clock');
      const user: unknown = await response.json(); const value = response.headers.get('Date');
      if (!user || typeof user !== 'object' || (user as { id?: unknown }).id !== userId || !value || !Number.isFinite(Date.parse(value))) throw new Error('clock');
      return new Date(value).toISOString();
    } catch {
      if (signal?.aborted) throw Object.assign(new Error('Opération interrompue.'), { name: 'AbortError' });
      throw new PresenceWorkflowError('UNAVAILABLE', 'L’heure du serveur ne peut pas être vérifiée.');
    } finally { clearTimeout(timeout); signal?.removeEventListener('abort', abort); }
  } };
}

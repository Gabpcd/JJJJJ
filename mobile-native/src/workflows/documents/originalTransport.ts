import { createClient } from '@supabase/supabase-js';
import { readNativeConfig } from '../../session/config';
import type { OriginalSigningTransport } from './types';

/** Dedicated stateless client: never calls setSession, setAuth, or mutates the shared runtime. */
export function createOriginalSigningTransport(config: { url: string; publishableKey: string },
  fetchImplementation: typeof fetch = fetch): OriginalSigningTransport {
  const admitted = readNativeConfig({ mode: 'staging', url: config.url, publishableKey: config.publishableKey }, ['mejpriaetwgtcstbgfid']);
  if (admitted.mode !== 'staging') throw new Error('Configuration TEST requise.');
  return {
    async sign({ storageKey, authorization, expiresIn, signal }) {
      if (!/^Bearer \S+$/.test(authorization) || !Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 3600) {
        throw new Error('Consultation documentaire invalide.');
      }
      const abort = new AbortController();
      const stop = () => abort.abort();
      if (signal?.aborted) stop();
      signal?.addEventListener('abort', stop, { once: true });
      const timer = setTimeout(stop, 15_000);
      try {
        const pinnedFetch: typeof fetch = async (input, init) => {
          const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
          if (url.origin !== admitted.url || !url.pathname.startsWith('/storage/v1/object/sign/')) {
            throw new Error('Destination documentaire non autorisée.');
          }
          const headers = new Headers(init?.headers);
          headers.set('Authorization', authorization);
          // Pin both authenticated identity and approved origin even when the SDK is reused/refreshed elsewhere.
          return fetchImplementation(input, { ...init, headers, signal: abort.signal, redirect: 'error' });
        };
        const dedicated = createClient(admitted.url, admitted.publishableKey, {
          auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
          global: { headers: { Authorization: authorization }, fetch: pinnedFetch },
        });
        const result = await dedicated.storage.from('jolene-documents').createSignedUrl(storageKey, expiresIn);
        if (abort.signal.aborted || result.error || !result.data?.signedUrl) throw new Error('Le document ne peut pas être ouvert actuellement.');
        return result.data.signedUrl;
      } finally {
        clearTimeout(timer); signal?.removeEventListener('abort', stop);
      }
    },
  };
}

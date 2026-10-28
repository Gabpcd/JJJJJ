import { readNativeConfig } from '../../session/config';
import { MAX_CONTRACT_BYTES, validContractStoragePath } from './business';
import { ContractWorkflowError, type ContractOriginalTransport } from './types';

/** Same authenticated GET path as storage-js download(), without a global JWT mutation or Blob decoder. */
export function createContractOriginalTransport(config: { url: string; publishableKey: string },
  fetchImplementation: typeof fetch = fetch): ContractOriginalTransport {
  const admitted = readNativeConfig({ mode: 'staging', ...config }, ['mejpriaetwgtcstbgfid']);
  if (admitted.mode !== 'staging') throw new Error('Configuration TEST requise.');
  return {
    async read({ contractId, storagePath, authorization, signal }) {
      if (!validContractStoragePath(storagePath, contractId) || !/^Bearer \S+$/.test(authorization)) {
        throw new ContractWorkflowError('INVALID_SCOPE', 'La référence de cet original est invalide.');
      }
      const controller = new AbortController(); const stop = () => controller.abort();
      if (signal?.aborted) stop(); signal?.addEventListener('abort', stop, { once: true });
      const timer = setTimeout(stop, 15_000);
      try {
        if (controller.signal.aborted) throw new Error('Aborted');
        const uri = `${admitted.url}/storage/v1/object/contrats-signes/${storagePath}`;
        const response = await fetchImplementation(uri, { method: 'GET', redirect: 'error', cache: 'no-store',
          headers: { Authorization: authorization, apikey: admitted.publishableKey, Accept: 'text/html' }, signal: controller.signal });
        const contentLength = response.headers.get('content-length');
        if (!response.ok || response.redirected || (response.url && response.url !== uri)
          // Supabase intentionally serves stored HTML as text/plain. The gateway still
          // requires exact equality with the database HTML bytes and its frozen SHA256.
          || !/^text\/(?:html|plain)(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '')
          || (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > MAX_CONTRACT_BYTES))) throw new Error('Invalid original response');
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (controller.signal.aborted || !bytes.length || bytes.length > MAX_CONTRACT_BYTES) {
          bytes.fill(0); throw new Error('Invalid original size');
        }
        return bytes;
      } catch {
        if (signal?.aborted) throw Object.assign(new Error('Lecture interrompue.'), { name: 'AbortError' });
        throw new ContractWorkflowError('UNAVAILABLE', 'L’original du contrat ne peut pas être lu actuellement.');
      } finally { clearTimeout(timer); signal?.removeEventListener('abort', stop); }
    },
  };
}

export type NativeConfig = { mode: 'demo' } | {
  mode: 'staging'; url: string; publishableKey: string; projectRef: string;
};

export interface NativeEnvironment {
  mode?: string;
  url?: string;
  publishableKey?: string;
}

/** Explicit allowlist supplied by the app; an env variable cannot authorize production. */
export function readNativeConfig(env: NativeEnvironment, allowedStagingRefs: readonly string[]): NativeConfig {
  const mode = env.mode?.trim() || 'demo';
  if (mode === 'demo') return { mode: 'demo' };
  if (mode !== 'staging') throw new Error('Ce pilote accepte uniquement les modes Démonstration et TEST.');
  let url: URL;
  try { url = new URL(env.url ?? ''); } catch { throw new Error('L’adresse du serveur TEST est manquante ou invalide.'); }
  const match = /^([a-z0-9]{20})\.supabase\.co$/.exec(url.hostname);
  if (url.protocol !== 'https:' || !match || url.username || url.password || url.port
    || !['', '/'].includes(url.pathname) || url.search || url.hash
    || !allowedStagingRefs.includes(match[1]!)) {
    throw new Error('Ce serveur n’est pas autorisé pour le pilote TEST.');
  }
  const key = env.publishableKey?.trim() ?? '';
  // This new client does not accept legacy JWT keys, preventing service_role mistakes.
  if (!/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(key)) {
    throw new Error('Une clé publique Supabase TEST est nécessaire. Aucune clé secrète ne doit être utilisée.');
  }
  return { mode, url: url.origin, publishableKey: key, projectRef: match[1]! };
}

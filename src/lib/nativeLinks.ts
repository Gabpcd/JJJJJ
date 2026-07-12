import { Capacitor } from '@capacitor/core';

const TRUSTED_WEB_HOSTS = new Set(['jolene.app', 'www.jolene.app', 'app.jolene.app']);

/**
 * Convertit un lien Jolene (URL HTTPS ou chemin interne) en route React.
 * Les query strings et fragments sont conservés : Supabase en a besoin pour
 * les callbacks PKCE et les liens de récupération de mot de passe.
 */
export function normaliserLienJolene(rawUrl: string): string | null {
  if (!rawUrl || typeof rawUrl !== 'string') return null;

  try {
    const isRelative = rawUrl.startsWith('/') && !rawUrl.startsWith('//');
    const isAbsoluteHttps = /^https:\/\//i.test(rawUrl);
    if (!isRelative && !isAbsoluteHttps) return null;

    const url = new URL(rawUrl, 'https://jolene.app');

    // La validation du host reste obligatoire même pour une chaîne qui débute
    // par « / » : les backslashes sont normalisés en séparateurs d'autorité par
    // URL (`/\\evil.example` ne doit pas devenir un chemin interne).
    if (url.protocol !== 'https:' || url.port || !TRUSTED_WEB_HOSTS.has(url.hostname.toLowerCase())) {
      return null;
    }

    if (!url.pathname.startsWith('/') || url.pathname.startsWith('//')) return null;
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return null;
  }
}

/** URL web publique utilisée pour les callbacks qui doivent revenir par Universal Link. */
export function urlCallbackPublique(path: string): string {
  const route = normaliserLienJolene(path);
  if (!route) throw new Error('Chemin de callback Jolene invalide');

  // Dans la coquille native, window.location.origin vaut capacitor://localhost
  // ou https://localhost et ne peut pas servir de redirectTo email/OIDC.
  const nativeOrigin = Capacitor.isNativePlatform();
  const origin = nativeOrigin ? 'https://jolene.app' : window.location.origin;
  return new URL(route, origin).toString();
}

export type RecoveryCredentials =
  | { kind: 'implicit'; accessToken: string; refreshToken: string }
  | { kind: 'pkce'; code: string }
  | { kind: 'token_hash'; tokenHash: string }
  | null;

/** Extrait sans journaliser les secrets d'un callback Supabase recovery. */
export function extraireRecoveryCredentials(url: Pick<Location, 'search' | 'hash'>): RecoveryCredentials {
  const search = new URLSearchParams(url.search);
  const hash = new URLSearchParams(url.hash.startsWith('#') ? url.hash.slice(1) : url.hash);
  const type = hash.get('type') ?? search.get('type');
  const isRecovery = !type || type === 'recovery';
  if (!isRecovery) return null;

  const accessToken = hash.get('access_token');
  const refreshToken = hash.get('refresh_token');
  if (accessToken && refreshToken) return { kind: 'implicit', accessToken, refreshToken };

  const code = search.get('code');
  if (code) return { kind: 'pkce', code };

  const tokenHash = search.get('token_hash');
  if (tokenHash) return { kind: 'token_hash', tokenHash };

  return null;
}

/** Retire les secrets de recovery de la barre d'adresse après consommation. */
export function nettoyerCallbackRecovery(): void {
  window.history.replaceState(null, '', '/reset-password');
}

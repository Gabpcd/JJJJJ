import { isNative } from './platform';

const PSC_HOSTS = new Set([
  'wallet.esw.esante.gouv.fr',
  'wallet.bas.esw.esante.gouv.fr',
  'auth.esw.esante.gouv.fr',
  'auth.bas.esw.esante.gouv.fr',
]);

export function estUrlPscAutorisee(rawUrl: string): boolean {
  try {
    const url = new URL(rawUrl);
    return url.protocol === 'https:'
      && !url.username
      && !url.password
      && !url.port
      && PSC_HOSTS.has(url.hostname.toLowerCase());
  } catch {
    return false;
  }
}

/**
 * Ouvre PSC dans un user-agent système sur mobile (Safari View Controller /
 * Custom Tab), jamais dans le WebView embarqué. C'est nécessaire aux flux
 * OAuth/OIDC natifs et permet au callback Universal Link de revenir à Jolene.
 */
export async function ouvrirUrlPsc(rawUrl: string): Promise<boolean> {
  if (!estUrlPscAutorisee(rawUrl)) return false;

  if (isNative()) {
    try {
      const { Browser } = await import('@capacitor/browser');
      await Browser.open({ url: rawUrl });
      return true;
    } catch {
      return false;
    }
  }

  window.location.assign(rawUrl);
  return true;
}

/** Ferme le navigateur in-app au retour d'un Universal Link PSC. */
export async function fermerNavigateurPsc(): Promise<void> {
  if (!isNative()) return;
  try {
    const { Browser } = await import('@capacitor/browser');
    await Browser.close();
  } catch { /* aucun navigateur PSC ouvert — sans effet */ }
}

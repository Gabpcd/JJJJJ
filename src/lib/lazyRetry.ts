import { lazy, type ComponentType } from 'react';

/**
 * Wrapper autour de React.lazy qui détecte les échecs de chargement de chunk
 * (typiquement après un déploiement : les anciens fichiers JS hachés n'existent
 * plus sur le CDN) et force un reload UNE SEULE FOIS pour charger la nouvelle
 * version. Évite la boucle infinie via sessionStorage.
 */
export function lazyRetry<T extends ComponentType<any>>(
  factory: () => Promise<{ default: T }>,
  chunkName?: string,
) {
  return lazy(async () => {
    const key = `chunk-retry-${chunkName ?? 'global'}`;
    const alreadyRetried = sessionStorage.getItem(key) === '1';

    try {
      const component = await factory();
      sessionStorage.removeItem(key);
      return component;
    } catch (error) {
      if (!alreadyRetried) {
        sessionStorage.setItem(key, '1');
        window.location.reload();
        // Le reload va interrompre l'exécution, mais TypeScript attend un return.
        return new Promise(() => {});
      }
      throw error;
    }
  });
}

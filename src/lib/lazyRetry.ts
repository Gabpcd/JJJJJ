import { lazy, type ComponentType } from 'react';
import { recoverFromChunkLoadError } from './chunkRecovery';

/**
 * Wrapper autour de React.lazy qui détecte les échecs de chargement de chunk
 * (typiquement après un déploiement : les anciens fichiers JS hachés n'existent
 * plus sur le CDN) et force un reload UNE SEULE FOIS pour charger la nouvelle
 * version. Évite la boucle infinie via sessionStorage.
 */
export function lazyRetry<T extends ComponentType<any>>(
  factory: () => Promise<{ default: T }>,
  _chunkName?: string,
) {
  return lazy(async () => {
    try {
      return await factory();
    } catch (error) {
      if (recoverFromChunkLoadError(error)) {
        // Le reload va interrompre l'exécution, mais TypeScript attend un return.
        return new Promise(() => {});
      }
      throw error;
    }
  });
}

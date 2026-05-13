/**
 * Hook `useApiCall` standardisé Sprint 8 PR 4 (chantier 4.3).
 *
 * Wrapper autour d'un appel asynchrone (typiquement `supabase.rpc()` ou `supabase.from()`)
 * avec :
 * - state `loading` géré automatiquement
 * - catch + traduction message via `traduireErreur`
 * - retry exponentiel sur erreurs réseau (3 tentatives, backoff 1/2/4s)
 * - toast affichage optionnel (configurable par appel)
 *
 * Usage :
 *   const { executer, loading } = useApiCall();
 *   const charger = () => executer(() => supabase.rpc('fn_xxx'), {
 *     onSuccess: (data) => setLignes(data),
 *     messageErreur: 'Impossible de charger les données.',
 *   });
 */

import { useCallback, useRef, useState } from 'react';
import { useNotification } from '@/contexts/NotificationContext';
import { traduireErreur, estErreurReseau } from '@/lib/errorMessages';

type Resultat<T> = { data: T | null; error: unknown };

type Options<T> = {
  /** Callback appelé en cas de succès (data non null + error null). */
  onSuccess?: (data: T) => void;
  /** Callback appelé en cas d'erreur après tous les retries. */
  onError?: (erreur: unknown) => void;
  /** Préfixe optionnel au message d'erreur (ex: "Impossible de charger : "). */
  messageErreur?: string;
  /** Affiche automatiquement un toast erreur si true (défaut: true). */
  toastErreur?: boolean;
  /** Nombre max de retries pour erreurs réseau (défaut: 3). */
  retriesReseau?: number;
};

const DELAIS_RETRY_MS = [1000, 2000, 4000];

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function useApiCall() {
  const [loading, setLoading] = useState(false);
  const annuleRef = useRef(false);
  const { afficherNotification } = useNotification();

  const executer = useCallback(
    async <T,>(
      appel: () => Promise<Resultat<T>> | PromiseLike<Resultat<T>>,
      options: Options<T> = {},
    ): Promise<T | null> => {
      const {
        onSuccess,
        onError,
        messageErreur,
        toastErreur = true,
        retriesReseau = 3,
      } = options;

      setLoading(true);
      annuleRef.current = false;
      let derniereErreur: unknown = null;

      try {
        for (let tentative = 0; tentative <= retriesReseau; tentative++) {
          if (annuleRef.current) return null;

          let resultat: Resultat<T>;
          try {
            resultat = await appel();
          } catch (e) {
            // Erreur réseau ou exception JS
            derniereErreur = e;
            if (estErreurReseau(e) && tentative < retriesReseau) {
              await sleep(DELAIS_RETRY_MS[Math.min(tentative, DELAIS_RETRY_MS.length - 1)]);
              continue;
            }
            break;
          }

          if (resultat.error) {
            derniereErreur = resultat.error;
            if (estErreurReseau(resultat.error) && tentative < retriesReseau) {
              await sleep(DELAIS_RETRY_MS[Math.min(tentative, DELAIS_RETRY_MS.length - 1)]);
              continue;
            }
            break;
          }

          // Succès
          if (onSuccess && resultat.data !== null && resultat.data !== undefined) {
            onSuccess(resultat.data);
          }
          return resultat.data;
        }

        // Toutes les tentatives ont échoué
        if (onError) onError(derniereErreur);
        if (toastErreur) {
          const messageTraduit = traduireErreur(derniereErreur);
          afficherNotification({
            type: 'erreur',
            message: messageErreur ? `${messageErreur} ${messageTraduit}` : messageTraduit,
          });
        }
        return null;
      } finally {
        setLoading(false);
      }
    },
    [afficherNotification],
  );

  const annuler = useCallback(() => {
    annuleRef.current = true;
  }, []);

  return { executer, loading, annuler };
}

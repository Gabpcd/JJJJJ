import { useEffect, useState } from 'react';
import type { NativeDocumentRuntime } from '../../documents/runtime';
import type { ManagedDocumentMediaAdapter } from '../../media/documents/types';

/** Preparation is a committed effect, not a picker/file side effect during React render. */
export function useDocumentMedia(runtime: NativeDocumentRuntime, userId: string, epoch: number) {
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState<{ media: ManagedDocumentMediaAdapter | null; error: string | null; loading: boolean }>({
    media: null, error: null, loading: true,
  });
  useEffect(() => {
    let current = true;
    setState({ media: null, error: null, loading: true });
    const timer = setTimeout(() => {
      if (!current) return;
      current = false;
      setState({ media: null, loading: false, error: 'La préparation des documents prend trop de temps. Réessayez.' });
    }, 20_000);
    void runtime.prepareSession({ userId, epoch }).then(media => {
      if (current) setState({ media, loading: false, error: null });
    }, () => {
      if (current) setState({ media: null, loading: false,
        error: 'Les documents ne peuvent pas être préparés. Fermez toute sélection ouverte puis réessayez ; le nettoyage des copies temporaires sera repris.' });
    }).finally(() => clearTimeout(timer));
    return () => { current = false; clearTimeout(timer); };
  }, [runtime, userId, epoch, attempt]);
  return { ...state, retry: () => setAttempt(value => value + 1) };
}

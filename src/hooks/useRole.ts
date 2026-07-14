import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { UserRole } from '@/lib/types';
import type { RpcGetMyRole } from '@/lib/supabase-rpc-types';

export const ROLE_RESOLUTION_TIMEOUT_MS = 8_000;

type RoleCompte = UserRole | 'ETABLISSEMENT' | 'INCONNU';

interface UseRoleResult {
  role: RoleCompte;
  etablissement_id: string | null;
  loading: boolean;
  resolved: boolean;
  error: Error | null;
  retry: () => void;
}

interface RoleState extends Omit<UseRoleResult, 'retry'> {}

const ETAT_INITIAL: RoleState = {
  role: 'INCONNU',
  etablissement_id: null,
  loading: true,
  resolved: false,
  error: null,
};

function normaliserErreur(error: unknown, fallback: string): Error {
  if (error instanceof Error) return error;
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') {
    return new Error(error.message);
  }
  return new Error(fallback);
}

async function recupererRoleAvecDelai(controller: AbortController) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const requete = supabase
    .rpc('fn_get_my_role')
    .abortSignal(controller.signal);

  try {
    return await Promise.race([
      Promise.resolve(requete),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          controller.abort();
          reject(new Error('La vérification de votre accès a expiré. Veuillez réessayer.'));
        }, ROLE_RESOLUTION_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

export function useRole(): UseRoleResult {
  const [state, setState] = useState<RoleState>(ETAT_INITIAL);
  const [retryVersion, setRetryVersion] = useState(0);
  const retry = useCallback(() => setRetryVersion((version) => version + 1), []);

  useEffect(() => {
    let cancelled = false;
    let requestVersion = 0;
    const controllers = new Set<AbortController>();

    const fetchRole = async () => {
      const currentRequest = ++requestVersion;
      setState(ETAT_INITIAL);

      try {
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) throw sessionError;
        if (cancelled || currentRequest !== requestVersion) return;

        if (!sessionData.session) {
          setState({
            role: 'INCONNU',
            etablissement_id: null,
            loading: false,
            resolved: true,
            error: null,
          });
          return;
        }

        const controller = new AbortController();
        controllers.add(controller);
        let response;
        try {
          response = await recupererRoleAvecDelai(controller);
        } finally {
          controllers.delete(controller);
        }

        if (cancelled || currentRequest !== requestVersion) return;
        if (response.error) throw response.error;

        const result = response.data as unknown as RpcGetMyRole | null;
        const role = typeof result?.role === 'string' ? result.role as RoleCompte : 'INCONNU';
        setState({
          role,
          etablissement_id: typeof result?.etablissement_id === 'string' ? result.etablissement_id : null,
          loading: false,
          resolved: true,
          error: null,
        });
      } catch (error) {
        if (cancelled || currentRequest !== requestVersion) return;
        setState({
          role: 'INCONNU',
          etablissement_id: null,
          loading: false,
          resolved: false,
          error: normaliserErreur(error, 'Impossible de vérifier votre accès.'),
        });
      }
    };

    void fetchRole();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (cancelled) return;
      if (session) {
        void fetchRole();
      } else {
        requestVersion += 1;
        for (const controller of controllers) controller.abort();
        setState({
          role: 'INCONNU',
          etablissement_id: null,
          loading: false,
          resolved: true,
          error: null,
        });
      }
    });

    return () => {
      cancelled = true;
      requestVersion += 1;
      for (const controller of controllers) controller.abort();
      subscription.unsubscribe();
    };
  }, [retryVersion]);

  return { ...state, retry };
}

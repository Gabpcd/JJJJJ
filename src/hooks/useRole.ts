import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { UserRole } from '@/lib/types';
import type { RpcGetMyRole } from '@/lib/supabase-rpc-types';

export const ROLE_RESOLUTION_TIMEOUT_MS = 8_000;
export const ROLE_CACHE_TTL_MS = 5 * 60_000;

type RoleCompte = UserRole | 'INCONNU';

function normaliserRole(role: unknown): RoleCompte | null {
  if (role === 'SOIGNANT') return 'SOIGNANT';
  if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT') return 'ADMIN_ETABLISSEMENT';
  if (role === 'ADMIN_GROUPE') return 'ADMIN_GROUPE';
  if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') return 'ADMIN_PLATEFORME';
  return null;
}

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

let roleCache: { userId: string; state: RoleState; expireAt: number } | null = null;

/** Utilisé par les tests et lors d'un changement explicite de compte. */
export function reinitialiserCacheRole(): void {
  roleCache = null;
}

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

    const fetchRole = async (force = false) => {
      const currentRequest = ++requestVersion;
      let roleSigneSecours: RoleState | null = null;
      setState(ETAT_INITIAL);

      try {
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) throw sessionError;
        if (cancelled || currentRequest !== requestVersion) return;

        if (!sessionData.session) {
          reinitialiserCacheRole();
          setState({
            role: 'INCONNU',
            etablissement_id: null,
            loading: false,
            resolved: true,
            error: null,
          });
          return;
        }

        const sessionUserId = sessionData.session.user.id;
        if (
          !force
          && roleCache?.userId === sessionUserId
          && roleCache.expireAt > Date.now()
        ) {
          setState(roleCache.state);
          return;
        }

        // app_metadata est signé par Supabase Auth. Il permet d'ouvrir la
        // bonne interface sans rendre une session valide dépendante d'une RPC
        // supplémentaire (incident reproduit pendant l'App Review iPad).
        // Les autorisations de données restent contrôlées côté serveur.
        const roleSigne = normaliserRole(sessionData.session.user.app_metadata?.role);
        if (roleSigne) {
          const etablissementMetadata = sessionData.session.user.app_metadata?.etablissement_id;
          roleSigneSecours = {
            role: roleSigne,
            etablissement_id: typeof etablissementMetadata === 'string' ? etablissementMetadata : null,
            loading: false,
            resolved: true,
            error: null,
          };
          setState(roleSigneSecours);
        }

        // Revalidation serveur en arrière-plan : elle révoque proprement une
        // session suspendue, mais son indisponibilité ne bloque plus un rôle
        // signé valide. Pour les anciens comptes, cette RPC reste obligatoire.
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
        const role = normaliserRole(result?.role) ?? 'INCONNU';
        const roleState: RoleState = {
          role,
          etablissement_id: typeof result?.etablissement_id === 'string' ? result.etablissement_id : null,
          loading: false,
          resolved: true,
          error: null,
        };
        roleCache = {
          userId: sessionUserId,
          state: roleState,
          expireAt: Date.now() + ROLE_CACHE_TTL_MS,
        };
        setState(roleState);
      } catch (error) {
        if (cancelled || currentRequest !== requestVersion) return;
        if (roleSigneSecours) {
          const sessionResult = await supabase.auth.getSession().catch(() => null);
          const sessionUserId = sessionResult?.data?.session?.user?.id;
          if (sessionUserId) {
            roleCache = {
              userId: sessionUserId,
              state: roleSigneSecours,
              // Une revalidation indisponible est retentée rapidement, sans
              // faire patienter chaque onglet entre-temps.
              expireAt: Date.now() + 30_000,
            };
          }
          setState(roleSigneSecours);
          return;
        }
        setState({
          role: 'INCONNU',
          etablissement_id: null,
          loading: false,
          resolved: false,
          error: normaliserErreur(error, 'Impossible de vérifier votre accès.'),
        });
      }
    };

    void fetchRole(retryVersion > 0);

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (cancelled) return;
      if (session) {
        if (event === 'SIGNED_IN' || event === 'USER_UPDATED') {
          reinitialiserCacheRole();
          void fetchRole(true);
        }
      } else {
        reinitialiserCacheRole();
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

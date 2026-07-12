import { supabase } from '@/integrations/supabase/client';
import { isNative } from './platform';

const STORAGE_KEY = 'jolene.push.current-device-token.v1';

export function memoriserTokenPushAppareil(token: string): void {
  if (!token) return;
  try {
    window.localStorage.setItem(STORAGE_KEY, token);
  } catch {
    // Le token reste en base; le fallback transport du logout protege quand
    // meme l'appareil si le stockage local est indisponible.
  }
}

export function oublierTokenPushAppareil(): void {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch { /* stockage prive/indisponible */ }
}

function lireTokenMemorise(): string | null {
  try {
    const token = window.localStorage.getItem(STORAGE_KEY)?.trim();
    return token || null;
  } catch {
    return null;
  }
}

async function avecDelai<T>(promise: PromiseLike<T>, timeoutMs: number): Promise<T> {
  let timer: number | undefined;
  try {
    return await Promise.race([
      Promise.resolve(promise),
      new Promise<never>((_, reject) => {
        timer = window.setTimeout(() => reject(new Error('Délai de désactivation push dépassé')), timeoutMs);
      }),
    ]);
  } finally {
    if (timer !== undefined) window.clearTimeout(timer);
  }
}

async function lireAbonnementWebCourant(): Promise<{ token: string | null; subscription: PushSubscription | null }> {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) {
    return { token: null, subscription: null };
  }
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    const subscription = await registration?.pushManager.getSubscription() ?? null;
    return {
      token: subscription ? JSON.stringify(subscription) : null,
      subscription,
    };
  } catch {
    return { token: null, subscription: null };
  }
}

/**
 * Retire uniquement l'installation courante avant logout.
 *
 * Jamais de fallback « supprimer tous les tokens du compte » : si le token
 * local est absent, le transport local est desinscrit et les autres appareils
 * restent intacts. La RPC recroise toujours auth.uid() côté serveur.
 */
export async function desactiverPushAppareilCourant(): Promise<{
  success: boolean;
  skipped: boolean;
  tokens_desactives: number;
}> {
  const native = isNative();
  let token = lireTokenMemorise();
  let webSubscription: PushSubscription | null = null;

  if (!native && !token) {
    const web = await lireAbonnementWebCourant();
    token = web.token;
    webSubscription = web.subscription;
  } else if (!native) {
    // Garder la subscription pour la desinscrire localement apres la RPC.
    webSubscription = (await lireAbonnementWebCourant()).subscription;
  }

  let tokensDesactives = 0;
  let rpcError: unknown = null;
  if (token) {
    try {
      const { data, error } = await avecDelai(supabase.rpc('fn_desactiver_mon_token_push', {
        p_token: token,
      }), 2_500);
      if (error) {
        rpcError = error;
      } else {
        const result = (data || {}) as { success?: boolean; tokens_desactives?: number; error?: string };
        if (result.success !== true) {
          rpcError = new Error(result.error || 'Désactivation du token push impossible');
        } else {
          tokensDesactives = Number(result.tokens_desactives || 0);
        }
      }
    } catch (error) {
      rpcError = error;
    }
  }

  // Protection locale même si la RPC est indisponible : l'appareil cesse de
  // recevoir. Aucune ligne appartenant à un autre appareil n'est touchée.
  try {
    if (native) {
      const { PushNotifications } = await import('@capacitor/push-notifications');
      await avecDelai(PushNotifications.unregister(), 2_500);
      await PushNotifications.removeAllListeners();
    } else if (webSubscription) {
      await avecDelai(webSubscription.unsubscribe(), 2_500);
    }
  } finally {
    oublierTokenPushAppareil();
  }

  if (rpcError) throw rpcError;
  return { success: true, skipped: !token, tokens_desactives: tokensDesactives };
}

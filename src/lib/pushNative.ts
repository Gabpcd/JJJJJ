import { isNative } from './platform';
import { supabase } from '@/integrations/supabase/client';
import { logger } from './logger';

/**
 * Initialize native push notifications via Capacitor.
 * - Requests permission
 * - Stores FCM token in Supabase
 * - Handles notification tap → navigate to linked page
 */
export async function initNativePush(userId: string): Promise<void> {
  if (!isNative()) return;

  try {
    const { PushNotifications } = await import('@capacitor/push-notifications');
    const { Capacitor } = await import('@capacitor/core');

    // Check / request permission
    let permStatus = await PushNotifications.checkPermissions();
    if (permStatus.receive === 'prompt') {
      permStatus = await PushNotifications.requestPermissions();
    }
    if (permStatus.receive !== 'granted') {
      logger.debug('[PUSH] Permission not granted');
      return;
    }

    // Register for push
    await PushNotifications.register();

    // Get token
    PushNotifications.addListener('registration', async (token) => {
      logger.debug('[PUSH] Registered with token');
      const plateforme = Capacitor.getPlatform() === 'ios' ? 'IOS' : 'ANDROID';
      try {
        await supabase.rpc('fn_upsert_token_push' as any, {
          p_token: token.value,
          p_plateforme: plateforme,
        });
      } catch (e) {
        logger.error('[PUSH] Failed to save token:', e);
      }
    });

    PushNotifications.addListener('registrationError', (err) => {
      logger.error('[PUSH] Registration error:', err);
    });

    // Handle notification tap → navigate to the linked page
    PushNotifications.addListener('pushNotificationActionPerformed', (notification) => {
      const data = notification.notification.data;
      const lien = data?.lien || data?.link || data?.url;
      if (lien && typeof lien === 'string') {
        // Validate internal link
        if (lien.startsWith('/') || lien.startsWith('https://jolene.app')) {
          const path = lien.startsWith('/') ? lien : new URL(lien).pathname;
          window.history.pushState(null, '', path);
          window.dispatchEvent(new PopStateEvent('popstate'));
        }
      }
    });
  } catch (e) {
    logger.error('[PUSH] Init failed:', e);
  }
}

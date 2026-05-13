import { isNative } from './platform';
import { supabase } from '@/integrations/supabase/client';
import { logger } from './logger';

/**
 * Initialize native push notifications via Capacitor.
 * - Requests permission
 * - Stores FCM token in Supabase tokens_push (plateforme = IOS/ANDROID)
 * - Handles notification tap → smart navigation per type_evenement
 *
 * Sprint 4 PR 7 : navigation in-app améliorée avec routing par type_evenement
 * en fallback du lien direct + event foreground dispatché pour toast UI.
 */
export async function initNativePush(_userId: string): Promise<void> {
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

    // Notification reçue alors que l'app est en foreground :
    // dispatch custom event pour toast UI, ne pas naviguer automatiquement
    PushNotifications.addListener('pushNotificationReceived', (notification) => {
      logger.debug('[PUSH] Foreground notification:', notification.title);
      window.dispatchEvent(new CustomEvent('jolene:push-foreground', {
        detail: {
          title: notification.title,
          body: notification.body,
          data: notification.data,
        },
      }));
    });

    // Tap sur notification (app fermée ou background) → smart navigation
    PushNotifications.addListener('pushNotificationActionPerformed', (notification) => {
      const data = notification.notification.data || {};
      const path = navigationPathForEvent(data);
      if (path) {
        logger.debug('[PUSH] Navigation tap →', path);
        window.history.pushState(null, '', path);
        window.dispatchEvent(new PopStateEvent('popstate'));
      }
    });
  } catch (e) {
    logger.error('[PUSH] Init failed:', e);
  }
}

/**
 * Détermine le chemin de navigation cible selon le data payload reçu.
 * Préférence :
 *  1. data.lien si présent (path absolu ou URL jolene.app)
 *  2. Fallback selon type_evenement + IDs contextuels
 */
function navigationPathForEvent(data: Record<string, any>): string | null {
  // 1. Lien direct prioritaire
  const lien = data.lien || data.link || data.url;
  if (lien && typeof lien === 'string') {
    if (lien.startsWith('/')) return lien;
    if (lien.startsWith('https://jolene.app') || lien.startsWith('https://app.jolene.app')) {
      try { return new URL(lien).pathname; } catch { /* fall through */ }
    }
  }

  // 2. Fallback routing par type_evenement
  const type = data.type_evenement;
  const missionId = data.mission_id;
  const contratId = data.contrat_id;
  const factureId = data.facture_id;
  const litigeId = data.litige_id;

  switch (type) {
    case 'CONTRAT_A_SIGNER':
    case 'CONTRAT_SIGNE':
    case 'CONTRAT_REJETE':
      return contratId ? `/contrat/${contratId}` : '/contrats';
    case 'CANDIDATURE_RECUE':
    case 'CANDIDATURE_ACCEPTEE':
    case 'CANDIDATURE_REFUSEE':
      return missionId ? `/etablissement/missions/${missionId}` : '/etablissement/missions';
    case 'MISSION_ASSIGNEE':
    case 'MISSION_RAPPEL_J1':
    case 'POINTAGE_MANQUANT':
      return missionId ? `/soignant/missions/${missionId}` : '/soignant/missions';
    case 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES':
    case 'URGENCE':
    case 'POOL_URGENCE':
      return missionId ? `/soignant/missions/${missionId}` : '/soignant/missions';
    case 'FACTURE_EMISE':
    case 'PAIEMENT_RECU':
    case 'PAIEMENT_RECLAME':
      return factureId ? `/facture/${factureId}` : '/factures';
    case 'LITIGE_OUVERT':
    case 'LITIGE_RESOLU':
    case 'NOUVEAU_MESSAGE_LITIGE':
      return litigeId ? `/litiges#${litigeId}` : '/litiges';
    case 'DPAE_RAPPEL':
    case 'DPAE_ANNULATION_RAPPEL':
      return contratId ? `/contrat/${contratId}` : '/contrats';
    case 'RECLAMATION_SCORE_DECISION':
      return '/mes-reclamations';
    case 'ALERTE_ADMIN':
      return '/admin/reclamations-score';
    default:
      return null; // Pas de navigation auto → ouvre l'app sur sa dernière route
  }
}

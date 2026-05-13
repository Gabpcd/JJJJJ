// Wrapper background geolocation (Sprint 4.5 PR 10).
//
// Ping GPS périodique pendant la durée d'une mission, opt-in RGPD strict.
// Buffer local en mémoire + flush batch toutes les N pings ou à l'arrêt.
//
// Routing :
//   - Capacitor native (iOS/Android) → @capacitor-community/background-geolocation
//     + foreground service Android + background mode iOS
//   - Web → silencieusement no-op (le navigateur ne peut pas pinger en background)

import { registerPlugin } from '@capacitor/core';
import type { BackgroundGeolocationPlugin } from '@capacitor-community/background-geolocation';
import { isNative } from './platform';
import { supabase } from '@/integrations/supabase/client';
import { logger } from './logger';
import { detecterMockGps } from './mock-detection';
import { genererIdTerminal } from './terminal';

// Le plugin community n'exporte pas de runtime JS — il s'enregistre via le bridge Capacitor.
// On le résout paresseusement pour éviter une init sur web.
let bgPluginCache: BackgroundGeolocationPlugin | null = null;
function getBgPlugin(): BackgroundGeolocationPlugin {
  if (bgPluginCache) return bgPluginCache;
  bgPluginCache = registerPlugin<BackgroundGeolocationPlugin>('BackgroundGeolocation');
  return bgPluginCache;
}

export interface PingGpsLocal {
  lat: number;
  lng: number;
  precision_m?: number | null;
  vitesse_ms?: number | null;
  cap_deg?: number | null;
  altitude_m?: number | null;
  source: 'BACKGROUND' | 'FOREGROUND';
  mock_detected?: boolean;
  horodatage: string; // ISO
}

interface SessionPingGps {
  missionId: string;
  watcherId: string | null;
  buffer: PingGpsLocal[];
  flushTimer: any;
}

const BATCH_SIZE = 20;
const FLUSH_INTERVAL_MS = 60_000;

let session: SessionPingGps | null = null;

/**
 * Vérifie le consentement RGPD côté serveur.
 */
export async function aConsenti(): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from('consentements_ping_gps' as any)
      .select('consenti')
      .maybeSingle();
    if (error) {
      logger.debug('[ping-gps] aConsenti error', error);
      return false;
    }
    return Boolean((data as any)?.consenti);
  } catch {
    return false;
  }
}

/**
 * Donne ou retire le consentement (audit RGPD côté serveur).
 */
export async function setConsentement(consent: boolean): Promise<{ success: boolean; error?: string }> {
  try {
    const { data, error } = await supabase.rpc('fn_donner_consentement_ping_gps' as any, {
      p_consent: consent,
    });
    if (error) return { success: false, error: error.message };
    const result = data as any;
    if (!result?.success) return { success: false, error: result?.error_code || 'Erreur' };
    return { success: true };
  } catch (err: any) {
    return { success: false, error: err?.message || 'Erreur réseau' };
  }
}

/**
 * Démarre les pings background pour une mission.
 * No-op silencieux sur web et si consentement absent.
 *
 * @param missionId Mission active
 * @param freqSec Fréquence ping en secondes (défaut 60)
 */
export async function demarrerPingGpsBackground(missionId: string, freqSec = 60): Promise<{
  success: boolean;
  reason?: 'WEB_NON_SUPPORTE' | 'CONSENTEMENT_MANQUANT' | 'PERMISSION_REFUSEE' | 'PLUGIN_INDISPONIBLE' | 'DEJA_DEMARRE' | 'ERREUR';
}> {
  if (!isNative()) {
    return { success: false, reason: 'WEB_NON_SUPPORTE' };
  }
  if (session && session.missionId === missionId) {
    return { success: false, reason: 'DEJA_DEMARRE' };
  }
  if (session) {
    await arreterPingGpsBackground();
  }

  const consenti = await aConsenti();
  if (!consenti) {
    return { success: false, reason: 'CONSENTEMENT_MANQUANT' };
  }

  let BgGeolocation: BackgroundGeolocationPlugin;
  try {
    BgGeolocation = getBgPlugin();
  } catch (err) {
    logger.error('[ping-gps] plugin indisponible', err);
    return { success: false, reason: 'PLUGIN_INDISPONIBLE' };
  }

  session = {
    missionId,
    watcherId: null,
    buffer: [],
    flushTimer: null,
  };

  try {
    const watcherId = await BgGeolocation.addWatcher(
      {
        backgroundMessage: 'Jolene suit votre position pendant la mission',
        backgroundTitle: 'Mission en cours',
        requestPermissions: true,
        stale: false,
        distanceFilter: 30,
      },
      (location: any, error: any) => {
        if (error) {
          logger.debug('[ping-gps] watcher error', error);
          if (error.code === 'NOT_AUTHORIZED') {
            // Permission refusée — fermer la session proprement
            arreterPingGpsBackground().catch(() => {});
          }
          return;
        }
        if (!location) return;

        const mockResult = detecterMockGps({
          coords: {
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy ?? 0,
          },
        } as any);
        const isSuspect = mockResult.niveau !== 'AUCUN';

        const ping: PingGpsLocal = {
          lat: location.latitude,
          lng: location.longitude,
          precision_m: location.accuracy ?? null,
          vitesse_ms: location.speed ?? null,
          cap_deg: location.bearing ?? null,
          altitude_m: location.altitude ?? null,
          source: 'BACKGROUND',
          mock_detected: isSuspect,
          horodatage: new Date(location.time ?? Date.now()).toISOString(),
        };
        if (!session) return;
        session.buffer.push(ping);
        if (session.buffer.length >= BATCH_SIZE) {
          flush().catch((e) => logger.error('[ping-gps] flush failed', e));
        }
      },
    );
    session.watcherId = watcherId;
  } catch (err: any) {
    logger.error('[ping-gps] addWatcher failed', err);
    session = null;
    const message = (err?.message || '').toLowerCase();
    if (message.includes('permission') || message.includes('denied')) {
      return { success: false, reason: 'PERMISSION_REFUSEE' };
    }
    return { success: false, reason: 'ERREUR' };
  }

  // Flush périodique (filet de sécurité pour batchs partiels)
  session.flushTimer = setInterval(() => {
    flush().catch((e) => logger.error('[ping-gps] periodic flush failed', e));
  }, FLUSH_INTERVAL_MS);

  // Note : freqSec n'est pas directement supporté par addWatcher
  // (distance-based). Si besoin d'un timing strict, scheduler externe.
  void freqSec;

  return { success: true };
}

/**
 * Arrête les pings, flush le buffer restant et libère les ressources.
 */
export async function arreterPingGpsBackground(): Promise<void> {
  if (!session) return;
  const current = session;
  session = null;

  if (current.flushTimer) {
    clearInterval(current.flushTimer);
  }

  if (current.watcherId && isNative()) {
    try {
      await getBgPlugin().removeWatcher({ id: current.watcherId });
    } catch (err) {
      logger.debug('[ping-gps] removeWatcher error', err);
    }
  }

  // Flush ultime du buffer restant
  if (current.buffer.length > 0) {
    await flushBuffer(current.missionId, current.buffer);
  }
}

async function flush(): Promise<void> {
  if (!session || session.buffer.length === 0) return;
  const missionId = session.missionId;
  const toSend = session.buffer.splice(0, session.buffer.length);
  await flushBuffer(missionId, toSend);
}

async function flushBuffer(missionId: string, pings: PingGpsLocal[]): Promise<void> {
  if (pings.length === 0) return;
  try {
    const { data, error } = await supabase.rpc('fn_enregistrer_pings_gps' as any, {
      p_mission_id: missionId,
      p_pings: pings as any,
      p_terminal_id: genererIdTerminal(),
    });
    if (error) {
      logger.error('[ping-gps] flush rpc error', error);
      // En cas d'échec, on relogue dans le buffer si une session existe encore
      if (session && session.missionId === missionId) {
        session.buffer.unshift(...pings);
      }
      return;
    }
    const result = data as any;
    if (!result?.success) {
      logger.error('[ping-gps] flush rejected', result?.error_code);
      // Erreurs définitives (consentement retiré, mission terminée) → on n'essaie plus
      return;
    }
    logger.debug(`[ping-gps] flushed ${result.inserts} pings (${result.ignores} ignorés)`);
  } catch (err) {
    logger.error('[ping-gps] flush exception', err);
    if (session && session.missionId === missionId) {
      session.buffer.unshift(...pings);
    }
  }
}

/**
 * Indique si une session de pings est actuellement active.
 */
export function pingGpsActif(): boolean {
  return session !== null;
}

/**
 * Retourne la mission en cours de tracking, ou null.
 */
export function missionEnPingGps(): string | null {
  return session?.missionId ?? null;
}

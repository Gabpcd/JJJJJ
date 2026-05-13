// Queue offline scan QR (Sprint 4.5 PR 7).
//
// Si le réseau est coupé au moment du scan, le token + coords + timestamp
// sont stockés en queue locale. Au retour online, dépile et appelle
// fn_valider_scan_qr en série.

import { supabase } from '@/integrations/supabase/client';
import { logger } from './logger';

const STORAGE_KEY = 'jolene_qr_offline_queue';

export interface QrScanEnAttente {
  token: string;
  mission_id: string;
  lat?: number;
  lng?: number;
  precision?: number;
  terminal_id?: string;
  scan_timestamp: string;  // ISO date du scan (côté device)
  retry_count?: number;
}

/** Stocke un scan en queue locale (à appeler quand network = offline). */
export function ajouterAQueueQr(scan: QrScanEnAttente): void {
  try {
    const queue = lireQueue();
    queue.push({ ...scan, retry_count: 0 });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
    logger.debug('[qr-offline] ajouté à la queue, total:', queue.length);
  } catch (err) {
    logger.error('[qr-offline] stockage queue échoué', err);
  }
}

function lireQueue(): QrScanEnAttente[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function ecrireQueue(queue: QrScanEnAttente[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
}

/**
 * Dépile la queue : appelle fn_valider_scan_qr pour chaque entrée.
 * Retourne un récap { ok, expired, errors }.
 *
 * À appeler depuis un listener 'online' ou Capacitor networkStatusChange.
 */
export async function depilerQueueQr(): Promise<{
  ok: number;
  expired: number;
  errors: number;
  details: Array<{ token: string; statut: 'OK' | 'EXPIRED' | 'ERROR'; message?: string }>;
}> {
  const queue = lireQueue();
  if (queue.length === 0) {
    return { ok: 0, expired: 0, errors: 0, details: [] };
  }

  const restants: QrScanEnAttente[] = [];
  const details: Array<{ token: string; statut: 'OK' | 'EXPIRED' | 'ERROR'; message?: string }> = [];
  let ok = 0, expired = 0, errors = 0;

  for (const scan of queue) {
    try {
      const { data, error } = await supabase.rpc('fn_valider_scan_qr' as any, {
        p_token: scan.token,
        p_lat: scan.lat ?? null,
        p_lng: scan.lng ?? null,
        p_precision: scan.precision ?? null,
        p_terminal_id: scan.terminal_id ?? null,
      });
      if (error) throw error;
      const result = data as any;
      if (result?.success) {
        ok++;
        details.push({ token: scan.token, statut: 'OK' });
      } else if (result?.error_code === 'QR_EXPIRE') {
        expired++;
        details.push({ token: scan.token, statut: 'EXPIRED', message: result.error });
        // Pas de re-queue : QR expiré ne peut plus être validé
      } else {
        // Autre erreur : si retry < 3, garder en queue
        const retryCount = (scan.retry_count || 0) + 1;
        if (retryCount < 3) {
          restants.push({ ...scan, retry_count: retryCount });
        } else {
          errors++;
          details.push({ token: scan.token, statut: 'ERROR', message: result?.error || 'Erreur après 3 retries' });
        }
      }
    } catch (err: any) {
      // Erreur réseau : garder en queue pour le prochain online
      restants.push(scan);
    }
  }

  ecrireQueue(restants);
  logger.debug(`[qr-offline] dépilé : ${ok} ok, ${expired} expired, ${errors} errors, ${restants.length} restants`);
  return { ok, expired, errors, details };
}

/** Taille actuelle de la queue. */
export function tailleQueueQr(): number {
  return lireQueue().length;
}

/** Vide la queue (utile en cas de cleanup utilisateur ou logout). */
export function viderQueueQr(): void {
  localStorage.removeItem(STORAGE_KEY);
}

/**
 * Initialise le listener online + Capacitor network pour sync auto.
 * À appeler une fois au démarrage de l'app (depuis App.tsx ou un hook).
 */
export async function initSyncQrOfflineQueue(onSync?: (summary: { ok: number; expired: number; errors: number }) => void): Promise<void> {
  // Listener web 'online'
  window.addEventListener('online', async () => {
    if (tailleQueueQr() > 0) {
      const summary = await depilerQueueQr();
      onSync?.(summary);
    }
  });

  // Listener Capacitor Network (native)
  try {
    const { Network } = await import('@capacitor/network');
    Network.addListener('networkStatusChange', async (status) => {
      if (status.connected && tailleQueueQr() > 0) {
        const summary = await depilerQueueQr();
        onSync?.(summary);
      }
    });
  } catch { /* @capacitor/network non disponible (web pur), ignore */ }

  // Tentative initiale au démarrage (au cas où network était coupé puis revenu)
  if (typeof navigator !== 'undefined' && navigator.onLine && tailleQueueQr() > 0) {
    const summary = await depilerQueueQr();
    onSync?.(summary);
  }
}

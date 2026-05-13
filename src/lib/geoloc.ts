// Wrapper unifié géolocalisation Capacitor / Web (Sprint 4 PR 5).
//
// Routing automatique :
//   - Capacitor native (iOS/Android) → @capacitor/geolocation
//   - Browser web → navigator.geolocation
//
// Avantages natif Capacitor :
//   - Demande permission gérée par OS (modale système plutôt que web)
//   - Précision GPS améliorée
//   - Fonctionne dans wrapper même si navigator.geolocation buggé
//   - Permission peut être demandée à la volée (au clic "Pointer") vs
//     à l'ouverture app

import { isNative } from './platform';
import { logger } from './logger';

export interface JoleneGeolocResult {
  /** Source réelle utilisée */
  source: 'capacitor' | 'web' | 'mock';
  coords: {
    latitude: number;
    longitude: number;
    accuracy: number;  // mètres
    altitude?: number | null;
    speed?: number | null;
    heading?: number | null;
  };
  timestamp: number;
}

export interface JoleneGeolocOptions {
  /** Précision haute (GPS) vs basse (réseau). Default true */
  enableHighAccuracy?: boolean;
  /** Timeout ms avant erreur. Default 30000 (30s pour pointage). */
  timeout?: number;
  /** Age max position cached (ms). Default 0 (toujours fraîche). */
  maximumAge?: number;
}

export class JoleneGeolocError extends Error {
  readonly code: 'PERMISSION_DENIED' | 'POSITION_UNAVAILABLE' | 'TIMEOUT' | 'UNSUPPORTED' | 'UNKNOWN';
  constructor(code: JoleneGeolocError['code'], message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Récupère la position GPS actuelle.
 *
 * Sur Capacitor native : demande permission via OS, utilise GPS natif.
 * Sur web : utilise navigator.geolocation HTML5.
 *
 * @throws JoleneGeolocError selon le code (PERMISSION_DENIED, TIMEOUT, etc.)
 */
export async function getCurrentPosition(
  options: JoleneGeolocOptions = {},
): Promise<JoleneGeolocResult> {
  const opts = {
    enableHighAccuracy: options.enableHighAccuracy !== false,
    timeout: options.timeout ?? 30000,
    maximumAge: options.maximumAge ?? 0,
  };

  if (isNative()) {
    return getViaCapacitor(opts);
  }
  return getViaWebApi(opts);
}

async function getViaCapacitor(opts: Required<JoleneGeolocOptions>): Promise<JoleneGeolocResult> {
  try {
    const { Geolocation } = await import('@capacitor/geolocation');

    // Check + request permission
    let perm = await Geolocation.checkPermissions();
    if (perm.location !== 'granted' && perm.coarseLocation !== 'granted') {
      perm = await Geolocation.requestPermissions({ permissions: ['location'] });
    }
    if (perm.location === 'denied') {
      throw new JoleneGeolocError('PERMISSION_DENIED', 'Permission GPS refusée');
    }

    const pos = await Geolocation.getCurrentPosition({
      enableHighAccuracy: opts.enableHighAccuracy,
      timeout: opts.timeout,
      maximumAge: opts.maximumAge,
    });

    return {
      source: 'capacitor',
      timestamp: pos.timestamp,
      coords: {
        latitude: pos.coords.latitude,
        longitude: pos.coords.longitude,
        accuracy: pos.coords.accuracy,
        altitude: pos.coords.altitude,
        speed: pos.coords.speed,
        heading: pos.coords.heading,
      },
    };
  } catch (err) {
    logger.error('[geoloc] capacitor error', err);
    if (err instanceof JoleneGeolocError) throw err;
    const message = (err as Error)?.message?.toLowerCase() || '';
    if (message.includes('denied') || message.includes('permission')) {
      throw new JoleneGeolocError('PERMISSION_DENIED', 'Permission GPS refusée');
    }
    if (message.includes('timeout')) {
      throw new JoleneGeolocError('TIMEOUT', `Pas de signal GPS après ${opts.timeout / 1000}s`);
    }
    if (message.includes('unavailable')) {
      throw new JoleneGeolocError('POSITION_UNAVAILABLE', 'Position indisponible');
    }
    throw new JoleneGeolocError('UNKNOWN', (err as Error)?.message || 'Erreur GPS');
  }
}

function getViaWebApi(opts: Required<JoleneGeolocOptions>): Promise<JoleneGeolocResult> {
  return new Promise((resolve, reject) => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      reject(new JoleneGeolocError('UNSUPPORTED', 'Navigator.geolocation indisponible'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({
        source: 'web',
        timestamp: pos.timestamp,
        coords: {
          latitude: pos.coords.latitude,
          longitude: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
          altitude: pos.coords.altitude ?? null,
          speed: pos.coords.speed ?? null,
          heading: pos.coords.heading ?? null,
        },
      }),
      (err) => {
        const code: JoleneGeolocError['code'] =
          err.code === 1 ? 'PERMISSION_DENIED'
          : err.code === 2 ? 'POSITION_UNAVAILABLE'
          : err.code === 3 ? 'TIMEOUT'
          : 'UNKNOWN';
        reject(new JoleneGeolocError(code, err.message || 'Erreur GPS'));
      },
      opts,
    );
  });
}

/**
 * Vérifie si la permission GPS est accordée sans la demander.
 * Retourne null si la plateforme ne supporte pas la query (vieux web).
 */
export async function checkGeolocPermission(): Promise<'granted' | 'denied' | 'prompt' | null> {
  if (isNative()) {
    try {
      const { Geolocation } = await import('@capacitor/geolocation');
      const perm = await Geolocation.checkPermissions();
      if (perm.location === 'granted' || perm.coarseLocation === 'granted') return 'granted';
      if (perm.location === 'denied') return 'denied';
      return 'prompt';
    } catch { return null; }
  }
  if (typeof navigator !== 'undefined' && navigator.permissions) {
    try {
      const result = await navigator.permissions.query({ name: 'geolocation' as PermissionName });
      return result.state as 'granted' | 'denied' | 'prompt';
    } catch { return null; }
  }
  return null;
}

/**
 * Demande explicitement la permission GPS (sur Capacitor uniquement —
 * sur web, c'est getCurrentPosition qui demande implicitement au 1er appel).
 */
export async function requestGeolocPermission(): Promise<boolean> {
  if (!isNative()) {
    // Sur web : navigator.geolocation demande lors du 1er getCurrentPosition.
    // On retourne true par défaut (l'utilisateur verra le dialogue navigateur).
    return true;
  }
  try {
    const { Geolocation } = await import('@capacitor/geolocation');
    const perm = await Geolocation.requestPermissions({ permissions: ['location'] });
    return perm.location === 'granted' || perm.coarseLocation === 'granted';
  } catch {
    return false;
  }
}

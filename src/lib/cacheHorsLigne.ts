import { isNative } from './platform';
import { logger } from './logger';

const CACHE_KEY_PREFIX = 'jolene_cache_';
const CACHE_TIMESTAMP_KEY = 'jolene_cache_ts';

interface CachedData {
  profil: any | null;
  missions: any[] | null;
  contrats: any[] | null;
}

/**
 * Save essential data to local storage for offline use (native only).
 */
export async function sauvegarderCacheHorsLigne(data: Partial<CachedData>): Promise<void> {
  if (!isNative()) return;

  try {
    const { Preferences } = await import('@capacitor/preferences');

    if (data.profil !== undefined) {
      await Preferences.set({ key: `${CACHE_KEY_PREFIX}profil`, value: JSON.stringify(data.profil) });
    }
    if (data.missions !== undefined) {
      await Preferences.set({ key: `${CACHE_KEY_PREFIX}missions`, value: JSON.stringify(data.missions) });
    }
    if (data.contrats !== undefined) {
      await Preferences.set({ key: `${CACHE_KEY_PREFIX}contrats`, value: JSON.stringify(data.contrats) });
    }

    await Preferences.set({ key: CACHE_TIMESTAMP_KEY, value: new Date().toISOString() });
  } catch (e) {
    logger.error('[CACHE] Failed to save offline cache:', e);
  }
}

/**
 * Load cached data from local storage (native only).
 * Returns null on web or if no cache exists.
 */
export async function chargerCacheHorsLigne(): Promise<(CachedData & { timestamp: string | null }) | null> {
  if (!isNative()) return null;

  try {
    const { Preferences } = await import('@capacitor/preferences');

    const [profil, missions, contrats, ts] = await Promise.all([
      Preferences.get({ key: `${CACHE_KEY_PREFIX}profil` }),
      Preferences.get({ key: `${CACHE_KEY_PREFIX}missions` }),
      Preferences.get({ key: `${CACHE_KEY_PREFIX}contrats` }),
      Preferences.get({ key: CACHE_TIMESTAMP_KEY }),
    ]);

    const hasData = profil.value !== null || missions.value !== null || contrats.value !== null;
    if (!hasData) return null;

    return {
      profil: profil.value ? JSON.parse(profil.value) : null,
      missions: missions.value ? JSON.parse(missions.value) : null,
      contrats: contrats.value ? JSON.parse(contrats.value) : null,
      timestamp: ts.value,
    };
  } catch (e) {
    logger.error('[CACHE] Failed to load offline cache:', e);
    return null;
  }
}

/**
 * Clear all cached data (e.g., on logout).
 */
export async function viderCacheHorsLigne(): Promise<void> {
  if (!isNative()) return;

  try {
    const { Preferences } = await import('@capacitor/preferences');
    await Promise.all([
      Preferences.remove({ key: `${CACHE_KEY_PREFIX}profil` }),
      Preferences.remove({ key: `${CACHE_KEY_PREFIX}missions` }),
      Preferences.remove({ key: `${CACHE_KEY_PREFIX}contrats` }),
      Preferences.remove({ key: CACHE_TIMESTAMP_KEY }),
    ]);
  } catch (e) {
    logger.error('[CACHE] Failed to clear offline cache:', e);
  }
}

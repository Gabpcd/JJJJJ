// Détection heuristique de mock GPS (Sprint 4.5 PR 2).
//
// Sur Android : @capacitor/geolocation v8 n'expose pas isFromMockProvider().
// Un plugin natif custom serait nécessaire pour la détection autoritative.
// En attendant, heuristiques basées sur les patterns observés :
//   - accuracy = 0 ou très petite (< 1m) — irréaliste sur device réel
//   - coordonnées parfaitement rondes (lat/lng entiers ou .5)
//   - speed = 0 alors qu'on devrait bouger (cas pointage debout)
//
// Sur iOS : aucune API publique pour détecter location simulator/jailbreak.
// On rely sur la couche serveur (cron téléportation + cohérence temporelle).

import type { JoleneGeolocResult } from './geoloc';
import { logger } from './logger';

export interface MockDetectionResult {
  detected: boolean;
  raisons: string[];
  niveau: 'AUCUN' | 'SUSPECT' | 'FORT';
}

/**
 * Analyse une position GPS et retourne les signaux de mock détectés.
 * Retourne 'FORT' uniquement si plusieurs signaux concordants —
 * limite les faux positifs.
 */
export function detecterMockGps(position: JoleneGeolocResult): MockDetectionResult {
  const raisons: string[] = [];

  // 1. Accuracy irréaliste (0 ou < 1m sur device mobile, c'est anormal)
  if (position.coords.accuracy <= 0) {
    raisons.push('ACCURACY_ZERO');
  } else if (position.coords.accuracy < 1) {
    raisons.push('ACCURACY_TROP_PRECISE');
  }

  // 2. Coordonnées parfaitement rondes (lat/lng entiers ou .5)
  // Pattern typique des apps de fake GPS qui posent (48.0, 2.0) etc.
  const latFrac = Math.abs(position.coords.latitude - Math.round(position.coords.latitude));
  const lngFrac = Math.abs(position.coords.longitude - Math.round(position.coords.longitude));
  if (latFrac < 0.0001 && lngFrac < 0.0001) {
    raisons.push('COORDS_PARFAITEMENT_RONDES');
  }
  if (Math.abs(latFrac - 0.5) < 0.0001 && Math.abs(lngFrac - 0.5) < 0.0001) {
    raisons.push('COORDS_DEMIES_RONDES');
  }

  // 3. Speed = 0 alors qu'on attend pointage en cours de marche
  // Heuristique faible — désactivée par défaut (utile uniquement pour ping background)

  // 4. Vue très "datacenter-like" (lat/lng tropicaux mais user en France)
  // → trop heuristique, on ne fait pas

  // Niveau de confiance
  let niveau: MockDetectionResult['niveau'] = 'AUCUN';
  if (raisons.length === 1) niveau = 'SUSPECT';
  if (raisons.length >= 2) niveau = 'FORT';

  if (raisons.length > 0) {
    logger.debug('[mock-detection] signaux:', raisons);
  }

  return {
    detected: raisons.length > 0,
    raisons,
    niveau,
  };
}

/**
 * Détecte les signaux indirects de jailbreak iOS via canOpenURL.
 * Le wrapper Capacitor n'expose pas directement cette API ; à compléter
 * par un plugin custom Sprint 5+ si besoin. Pour l'instant : check
 * minimal côté JS via présence d'URL schemes jailbreak typiques.
 */
export function detecterJailbreakIos(): { detected: boolean; raisons: string[] } {
  const raisons: string[] = [];

  // Sur Capacitor web wrapper, on n'a pas accès à canOpenURL.
  // Mais on peut vérifier des indices comme la présence de classes JS
  // injectées par jailbreak tweaks.
  if (typeof navigator === 'undefined') {
    return { detected: false, raisons };
  }

  // Présence d'extension de Cydia (peu fiable mais c'est tout ce qu'on a)
  // @ts-expect-error — APIs jailbreak non typées
  if (typeof window.cydia !== 'undefined' || typeof window.Cydia !== 'undefined') {
    raisons.push('CYDIA_DETECTED');
  }

  return { detected: raisons.length > 0, raisons };
}

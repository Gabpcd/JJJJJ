import { Camera } from 'expo-camera';
import * as Location from 'expo-location';
import { createPresenceQrController } from './qrController';
import { createPresenceGpsController } from './gpsController';
import type { ManagedPresenceSensors, PresenceSensorGuard } from './types';
import { PRESENCE_ID } from '../../workflows/presence/business';

/** One instance per verified userId + epoch; no permission or device access during construction. */
export function createExpoPresenceSensors(guard: PresenceSensorGuard): ManagedPresenceSensors {
  if (!PRESENCE_ID.test(guard.scope.userId) || !Number.isSafeInteger(guard.scope.epoch) || guard.scope.epoch < 0)
    throw new Error('Contexte capteurs invalide');
  const scope = Object.freeze({ ...guard.scope });
  const scoped = { ...guard, scope };
  const qr = createPresenceQrController(scoped, {
    read: () => Camera.getCameraPermissionsAsync(),
    request: () => Camera.requestCameraPermissionsAsync(),
  });
  const gps = createPresenceGpsController(scoped, {
    readPermission: () => Location.getForegroundPermissionsAsync(),
    requestPermission: () => Location.requestForegroundPermissionsAsync(),
    servicesEnabled: () => Location.hasServicesEnabledAsync(),
    watch: (receive, failure) => Location.watchPositionAsync({ accuracy: Location.Accuracy.Balanced,
      distanceInterval: 0, timeInterval: 1_000, mayShowUserSettingsDialog: false }, receive, () => failure()),
  });
  return { scope, qr, gps, cancel: () => { qr.cancel(); gps.cancel(); }, dispose: () => { qr.dispose(); gps.dispose(); } };
}

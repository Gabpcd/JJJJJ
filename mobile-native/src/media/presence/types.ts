import type { GpsObservation, PresenceGpsPort, PresenceQrPort } from '../../workflows/presence/types';

export interface PresenceSensorScope { userId: string; epoch: number }
export interface PresenceSensorGuard {
  scope: PresenceSensorScope;
  isCurrent(scope: PresenceSensorScope): boolean;
  isForeground(): boolean;
}
export interface SensorPermission { granted: boolean; canAskAgain: boolean }
export interface CameraPermissionPort {
  read(): Promise<SensorPermission>;
  request(): Promise<SensorPermission>;
}
export interface PositionSample {
  timestamp: number; mocked?: boolean;
  coords: { latitude: number; longitude: number; accuracy: number | null };
}
export interface PositionSubscription { remove(): void }
export interface LocationNativePort {
  readPermission(): Promise<SensorPermission>;
  requestPermission(): Promise<SensorPermission>;
  servicesEnabled(): Promise<boolean>;
  watch(onPosition: (sample: PositionSample) => void, onError: () => void): Promise<PositionSubscription>;
}
export interface QrViewState { phase: 'closed' | 'permission' | 'scanning'; requestId: number }
export interface ManagedPresenceQr extends PresenceQrPort {
  snapshot(): QrViewState;
  subscribe(listener: () => void): () => void;
  barcode(requestId: number, type: string, data: string): void;
  unavailable(requestId: number): void;
  cancel(): void;
  dispose(): void;
}
export type GpsChoice = 'off' | 'permission' | 'ready' | 'denied' | 'unavailable';
export interface ManagedPresenceGps extends PresenceGpsPort {
  snapshot(): GpsChoice;
  subscribe(listener: () => void): () => void;
  /** Only call from a visible user click. Does not acquire coordinates or persist server consent. */
  choose(include: boolean, signal?: AbortSignal): Promise<GpsChoice>;
  /** One explicit UI submission; always release in finally. No permission prompt during locate. */
  arm(): () => void;
  cancel(): void;
  dispose(): void;
}
export interface ManagedPresenceSensors {
  scope: PresenceSensorScope;
  qr: ManagedPresenceQr;
  gps: ManagedPresenceGps;
  cancel(): void;
  dispose(): void;
}
export type { GpsObservation };

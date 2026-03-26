import { Capacitor } from '@capacitor/core';

/** True when running inside a Capacitor native shell (iOS / Android). */
export function isNative(): boolean {
  return Capacitor.isNativePlatform();
}

export function isIOS(): boolean {
  return isNative() && Capacitor.getPlatform() === 'ios';
}

export function isAndroid(): boolean {
  return isNative() && Capacitor.getPlatform() === 'android';
}

/**
 * Opens a URL in the appropriate way:
 * - Native: uses @capacitor/browser (in-app browser)
 * - Web: uses window.open
 */
export async function ouvrirLienExterne(url: string): Promise<void> {
  if (isNative()) {
    const { Browser } = await import('@capacitor/browser');
    await Browser.open({ url });
  } else {
    window.open(url, '_blank', 'noopener');
  }
}

/**
 * Gets current GPS position using native plugin or web API.
 */
export async function obtenirPosition(): Promise<{ lat: number; lng: number; precisionM: number }> {
  if (isNative()) {
    const { Geolocation } = await import('@capacitor/geolocation');
    await Geolocation.requestPermissions();
    const pos = await Geolocation.getCurrentPosition({ enableHighAccuracy: true, timeout: 15000 });
    return {
      lat: pos.coords.latitude,
      lng: pos.coords.longitude,
      precisionM: pos.coords.accuracy,
    };
  }

  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('Géolocalisation non supportée'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        resolve({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          precisionM: pos.coords.accuracy,
        }),
      (err) => reject(err),
      { enableHighAccuracy: true, timeout: 15000 }
    );
  });
}

/**
 * Pick a photo from camera or gallery.
 * Native: uses @capacitor/camera. Web: falls back to file input.
 */
export async function prendrePhoto(): Promise<{ dataUrl: string } | null> {
  if (isNative()) {
    const { Camera, CameraResultType, CameraSource } = await import('@capacitor/camera');
    const photo = await Camera.getPhoto({
      resultType: CameraResultType.DataUrl,
      source: CameraSource.Prompt, // Ask: camera or gallery
      quality: 80,
    });
    return photo.dataUrl ? { dataUrl: photo.dataUrl } : null;
  }
  // Web fallback — caller should use <input type="file"> instead
  return null;
}

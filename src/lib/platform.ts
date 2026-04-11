import { Capacitor } from '@capacitor/core';
import { toast } from 'sonner';

export type Platform = 'web' | 'ios' | 'android';

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

export function getPlatform(): Platform {
  if (!Capacitor.isNativePlatform()) return 'web';
  return Capacitor.getPlatform() as 'ios' | 'android';
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
 * Share content using native share sheet or web fallback.
 */
export async function partagerContenu(options: {
  title: string;
  text?: string;
  url: string;
}): Promise<void> {
  if (isNative()) {
    try {
      const { Share } = await import('@capacitor/share');
      await Share.share({
        title: options.title,
        text: options.text,
        url: options.url,
        dialogTitle: options.title,
      });
    } catch {
      // User cancelled — ignore
    }
    return;
  }

  // Web: navigator.share or clipboard fallback
  if (navigator.share) {
    try {
      await navigator.share({
        title: options.title,
        text: options.text,
        url: options.url,
      });
    } catch {
      // User cancelled
    }
  } else {
    try {
      await navigator.clipboard.writeText(options.url);
      toast.success('Lien copié dans le presse-papiers');
    } catch {
      toast.error('Impossible de copier le lien');
    }
  }
}

/**
 * Open a location in Maps app (iOS), Google Maps, or Waze.
 * Falls back to Google Maps web on desktop.
 */
export function ouvrirNavigation(lat: number, lng: number, label?: string) {
  const encodedLabel = encodeURIComponent(label || 'Destination');
  const platform = getPlatform();

  return {
    plans: () => {
      const url = platform === 'ios'
        ? `maps:?q=${encodedLabel}&ll=${lat},${lng}`
        : `https://maps.google.com/maps?q=${lat},${lng}&label=${encodedLabel}`;
      if (isNative()) {
        import('@capacitor/browser').then(({ Browser }) => Browser.open({ url }));
      } else {
        window.open(url, '_blank');
      }
    },
    googleMaps: () => {
      const url = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
      if (isNative()) {
        import('@capacitor/browser').then(({ Browser }) => Browser.open({ url }));
      } else {
        window.open(url, '_blank');
      }
    },
    waze: () => {
      const url = `https://waze.com/ul?ll=${lat},${lng}&navigate=yes`;
      if (isNative()) {
        import('@capacitor/browser').then(({ Browser }) => Browser.open({ url }));
      } else {
        window.open(url, '_blank');
      }
    },
  };
}

/**
 * Configure keyboard behavior per-platform.
 * Call once at app startup on native.
 */
export async function configurerClavier(): Promise<void> {
  if (!isNative()) return;

  try {
    const { Keyboard } = await import('@capacitor/keyboard');
    const platform = Capacitor.getPlatform();

    if (platform === 'ios') {
      await Keyboard.setResizeMode({ mode: 'body' as any });
    } else if (platform === 'android') {
      await Keyboard.setResizeMode({ mode: 'native' as any });
    }

    // Scroll active element into view when keyboard shows
    Keyboard.addListener('keyboardWillShow', () => {
      setTimeout(() => {
        const el = document.activeElement as HTMLElement | null;
        el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 100);
    });
  } catch {
    // Keyboard plugin not available
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
      source: CameraSource.Prompt,
      quality: 80,
    });
    return photo.dataUrl ? { dataUrl: photo.dataUrl } : null;
  }
  return null;
}

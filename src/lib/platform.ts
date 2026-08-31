import { Capacitor } from '@capacitor/core';
import { toast } from 'sonner';
import { activeEditableField, keepNativeFieldVisible } from './nativeKeyboardViewport';

export type Platform = 'web' | 'ios' | 'android';

/** True when running inside a Capacitor native shell (iOS / Android). */
export function isNative(): boolean {
  return Capacitor.isNativePlatform();
}

/** True on iPhone/iPad Safari (web), not just Capacitor. */
export function isIOSBrowser(): boolean {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent;
  return /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

/** True on Android Chrome/Firefox/etc. (web), not just Capacitor. */
export function isAndroidBrowser(): boolean {
  if (typeof navigator === 'undefined') return false;
  return /Android/i.test(navigator.userAgent);
}

export function isIOS(): boolean {
  if (isNative() && Capacitor.getPlatform() === 'ios') return true;
  return isIOSBrowser();
}

export function isAndroid(): boolean {
  if (isNative() && Capacitor.getPlatform() === 'android') return true;
  return isAndroidBrowser();
}

/**
 * Detect the platform for UI-style purposes (transitions, safe-area, etc.).
 * Returns 'ios' or 'android' for BOTH Capacitor native AND mobile browsers,
 * so the Safari iOS web experience matches the Capacitor iOS app visually.
 * Desktop browsers still return 'web'.
 */
export function getPlatform(): Platform {
  if (Capacitor.isNativePlatform()) {
    return Capacitor.getPlatform() as 'ios' | 'android';
  }
  if (isIOSBrowser()) return 'ios';
  if (isAndroidBrowser()) return 'android';
  return 'web';
}

/** True when the PWA is installed / running in standalone mode. */
export function isStandalonePWA(): boolean {
  if (typeof window === 'undefined') return false;
  return window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as any).standalone === true;
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

    // 'native' sur les 2 plateformes : la WebView redimensionne son viewport
    // au lieu de rétrécir le body (mode 'body' créait un grand vide en haut
    // au focus d'un champ sur iOS — le header sticky restait, le contenu
    // remontait). 'native' garde le layout stable.
    await Keyboard.setResizeMode({ mode: 'native' as any });

    let viewportSansClavier = window.innerHeight;
    let hauteurVisibleAvecClavier: number | undefined;

    const revealFocusedField = (viewportHeight = hauteurVisibleAvecClavier) => {
      // Attendre que le resize natif et les safe areas aient leur taille
      // finale. On ne déplace la zone scrollable que si le champ reste masqué.
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          const field = activeEditableField();
          if (field) keepNativeFieldVisible(field, viewportHeight);
        });
      });
    };

    await Keyboard.addListener('keyboardDidShow', ({ keyboardHeight }) => {
      // En resize Native, WKWebView ne reflète pas toujours la nouvelle
      // hauteur dans visualViewport (notamment Simulator/Safari 18). La
      // hauteur du plugin est la source fiable ; Math.min évite de retrancher
      // deux fois si innerHeight a déjà été réduit par iOS.
      const calculee = viewportSansClavier - keyboardHeight;
      hauteurVisibleAvecClavier = Math.min(
        window.innerHeight,
        window.visualViewport?.height ?? Number.POSITIVE_INFINITY,
        calculee > 0 ? calculee : Number.POSITIVE_INFINITY,
      );
      revealFocusedField(hauteurVisibleAvecClavier);
    });
    await Keyboard.addListener('keyboardDidHide', () => {
      hauteurVisibleAvecClavier = undefined;
      window.requestAnimationFrame(() => {
        viewportSansClavier = window.innerHeight;
      });
    });
    document.addEventListener('focusin', () => {
      if (!document.body.classList.contains('keyboard-is-open')) return;
      window.setTimeout(() => revealFocusedField(), 60);
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

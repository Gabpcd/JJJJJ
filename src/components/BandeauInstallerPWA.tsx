import { useEffect, useState } from 'react';
import { X, Share, Plus } from 'lucide-react';
import { isIOSBrowser, isStandalonePWA, isNative } from '@/lib/platform';

const DISMISS_KEY = 'pwa_install_dismissed';
const DISMISS_DURATION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

/**
 * Discreet banner suggesting iPhone Safari users to "Add to Home Screen"
 * for a full-screen app experience. Only appears on:
 * - iOS Safari web (not Capacitor native, not standalone PWA, not desktop)
 * - After 30 seconds of page load (not intrusive)
 * - Only once every 7 days after dismissal
 */
export function BandeauInstallerPWA() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    // Skip if not iOS Safari web, if Capacitor native, or if already installed
    if (isNative() || isStandalonePWA() || !isIOSBrowser()) return;

    // Skip if recently dismissed
    const dismissedAt = localStorage.getItem(DISMISS_KEY);
    if (dismissedAt) {
      const elapsed = Date.now() - parseInt(dismissedAt, 10);
      if (elapsed < DISMISS_DURATION_MS) return;
    }

    // Show after 30s delay
    const timer = setTimeout(() => setVisible(true), 30_000);
    return () => clearTimeout(timer);
  }, []);

  const dismiss = () => {
    localStorage.setItem(DISMISS_KEY, Date.now().toString());
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div
      className="fixed left-0 right-0 z-[55] md:hidden pointer-events-none"
      style={{
        bottom: 'calc(4rem + env(safe-area-inset-bottom) + 0.75rem)',
      }}
    >
      <div className="pointer-events-auto mx-4 bg-gradient-to-r from-primary to-primary/90 text-primary-foreground rounded-2xl shadow-2xl p-4 flex items-start gap-3 animate-in slide-in-from-bottom-4 duration-300">
        <div className="flex-1">
          <p className="text-sm font-bold mb-1">Installer Jolene sur votre iPhone</p>
          <p className="text-xs opacity-90 leading-snug">
            Tapez <Share className="inline h-3.5 w-3.5 mx-0.5" /> puis{' '}
            <span className="inline-flex items-center bg-white/20 rounded px-1.5 py-0.5 text-[11px] font-semibold">
              <Plus className="h-3 w-3 mr-0.5" />Sur l'écran d'accueil
            </span>{' '}
            pour une expérience plein écran.
          </p>
        </div>
        <button
          onClick={dismiss}
          aria-label="Fermer"
          className="p-1 rounded-lg hover:bg-white/10 flex-shrink-0"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { X, Share, Plus, Download } from 'lucide-react';
import { isIOSBrowser, isAndroidBrowser, isStandalonePWA, isNative } from '@/lib/platform';
import { estSessionRecurrente } from '@/lib/session-count';

const DISMISS_KEY = 'pwa_install_dismissed';
const DISMISS_DURATION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  prompt(): Promise<void>;
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

/**
 * Cross-browser "install as app" suggestion banner.
 * - iOS Safari: shows instructions (Share → Sur l'écran d'accueil)
 * - Android Chrome/Edge: shows an "Installer" button (native beforeinstallprompt)
 * - Desktop browsers / standalone PWA / Capacitor native: hidden
 * - Dismissible for 7 days
 */
export function BandeauInstallerPWA() {
  const { pathname } = useLocation();
  const [visible, setVisible] = useState(false);
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [mode, setMode] = useState<'ios' | 'android-native' | null>(null);

  useEffect(() => {
    // Skip if already running as app or on desktop
    if (isNative() || isStandalonePWA()) return;

    // Session G5 — ne pas proposer l'installation dès la 1re visite : on attend
    // la 2e session (intention d'usage avérée).
    if (!estSessionRecurrente()) return;

    // Skip if recently dismissed
    const dismissedAt = localStorage.getItem(DISMISS_KEY);
    if (dismissedAt) {
      const elapsed = Date.now() - parseInt(dismissedAt, 10);
      if (elapsed < DISMISS_DURATION_MS) return;
    }

    // iOS Safari → show manual instructions after 30s
    if (isIOSBrowser()) {
      const timer = setTimeout(() => {
        setMode('ios');
        setVisible(true);
      }, 30_000);
      return () => clearTimeout(timer);
    }

    // Android Chrome / Edge / Samsung Internet → intercept the native install prompt
    if (isAndroidBrowser()) {
      const handler = (e: Event) => {
        e.preventDefault();
        setDeferredPrompt(e as BeforeInstallPromptEvent);
        setTimeout(() => {
          setMode('android-native');
          setVisible(true);
        }, 15_000);
      };
      window.addEventListener('beforeinstallprompt', handler);
      return () => window.removeEventListener('beforeinstallprompt', handler);
    }
  }, []);

  const dismiss = () => {
    localStorage.setItem(DISMISS_KEY, Date.now().toString());
    setVisible(false);
  };

  const handleInstallClick = async () => {
    if (!deferredPrompt) return;
    try {
      await deferredPrompt.prompt();
      const choice = await deferredPrompt.userChoice;
      if (choice.outcome === 'accepted') {
        setVisible(false);
        setDeferredPrompt(null);
      }
    } catch {
      // ignore errors
    }
  };

  // Lot 11 : jamais couvrante sur les écrans où les CTA vivent en bas de page
  // (RGPD / Se déconnecter / Enregistrer) — la bannière fixed les recouvrait.
  if (/compte|parametres|profil/.test(pathname)) return null;

  if (!visible || !mode) return null;

  return (
    <div
      className="fixed left-0 right-0 z-[55] md:hidden pointer-events-none"
      style={{
        bottom: 'calc(4rem + env(safe-area-inset-bottom) + 0.75rem)',
      }}
    >
      <div className="pointer-events-auto mx-4 bg-gradient-to-r from-primary to-primary/90 text-primary-foreground rounded-2xl shadow-2xl p-4 flex items-start gap-3 animate-in slide-in-from-bottom-4 duration-300">
        <div className="flex-1">
          <p className="text-sm font-bold mb-1">Installer Jolene sur votre téléphone</p>
          {mode === 'ios' ? (
            <p className="text-xs opacity-90 leading-snug">
              Tapez <Share className="inline h-3.5 w-3.5 mx-0.5" /> puis{' '}
              <span className="inline-flex items-center bg-white/20 rounded px-1.5 py-0.5 text-[11px] font-semibold">
                <Plus className="h-3 w-3 mr-0.5" />Sur l'écran d'accueil
              </span>{' '}
              pour une expérience plein écran.
            </p>
          ) : (
            <>
              <p className="text-xs opacity-90 leading-snug mb-2">
                Installez Jolene comme une vraie application pour un accès rapide et plein écran.
              </p>
              <button
                onClick={handleInstallClick}
                className="inline-flex items-center gap-1.5 bg-white text-primary px-3 py-1.5 rounded-lg text-xs font-bold hover:bg-white/90 transition"
              >
                <Download className="h-3.5 w-3.5" /> Installer Jolene
              </button>
            </>
          )}
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

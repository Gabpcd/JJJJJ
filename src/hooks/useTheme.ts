import { useEffect, useState } from 'react';
import { logger } from '@/lib/logger';

type Theme = 'light' | 'dark';

function getInitialTheme(): Theme {
  const stored = localStorage.getItem('theme') as Theme | null;
  if (stored === 'light' || stored === 'dark') return stored;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function useTheme() {
  const [theme, setTheme] = useState<Theme>(getInitialTheme);

  useEffect(() => {
    const root = document.documentElement;
    const isDark = theme === 'dark';
    root.classList.toggle('dark', isDark);
    localStorage.setItem('theme', theme);

    // Update theme-color meta tag for browser chrome (Android Chrome, Safari)
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute('content', isDark ? '#6B3FA0' : '#E04590');
    }

    // Met à jour le contraste sur iOS et Android ; la couleur de fond n'est
    // configurable par le plugin que sur Android.
    import('@/lib/platform').then(({ isNative, isAndroid }) => {
      if (!isNative()) return;
      import('@capacitor/status-bar').then(({ StatusBar, Style }) => {
        StatusBar.setStyle({ style: isDark ? Style.Dark : Style.Light });
        if (isAndroid()) {
          StatusBar.setBackgroundColor({ color: isDark ? '#151B2B' : '#FFFFFF' });
        }
      }).catch((err) => { logger.warn('[useTheme] StatusBar update failed', err); });
    });
  }, [theme]);

  const toggleTheme = () => setTheme((t) => (t === 'dark' ? 'light' : 'dark'));

  return { theme, toggleTheme };
}

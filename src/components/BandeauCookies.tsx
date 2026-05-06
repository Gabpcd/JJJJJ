import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';

export function BandeauCookies() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const consent = localStorage.getItem('cookie-consent');
    if (!consent) {
      const timer = setTimeout(() => setVisible(true), 1500);
      return () => clearTimeout(timer);
    }
  }, []);

  const accepter = () => {
    localStorage.setItem('cookie-consent', 'accepted');
    localStorage.setItem('cookie-consent-date', new Date().toISOString());
    setVisible(false);
  };

  const refuser = () => {
    localStorage.setItem('cookie-consent', 'refused');
    localStorage.setItem('cookie-consent-date', new Date().toISOString());
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div
      className="fixed inset-0 z-[99999] flex items-end justify-center pointer-events-none"
      style={{ paddingBottom: 'calc(5rem + env(safe-area-inset-bottom, 0px) + 1rem)' }}
    >
      <div className="pointer-events-auto max-w-2xl w-full mx-4 bg-card border-2 border-primary/20 rounded-2xl shadow-2xl p-4 sm:p-5">
        <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
          <div className="flex-1">
            <p className="text-sm font-semibold text-foreground">Cookies et données personnelles</p>
            <p className="text-xs text-muted-foreground mt-1">
              Jolene utilise des cookies essentiels au fonctionnement (authentification, préférences).
              Aucun cookie publicitaire ni de tracking.{' '}
              <a href="/confidentialite" className="text-primary underline font-medium">En savoir plus</a>
            </p>
          </div>
          <div className="flex gap-2 shrink-0">
            <Button variant="outline" size="sm" onClick={refuser} className="text-xs">
              Refuser
            </Button>
            <Button size="sm" onClick={accepter} className="text-xs">
              Accepter
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

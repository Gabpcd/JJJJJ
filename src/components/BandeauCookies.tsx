import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Cookie } from 'lucide-react';

const COOKIE_KEY = 'sd_cookies_accepted';

export function BandeauCookies() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!localStorage.getItem(COOKIE_KEY)) {
      setVisible(true);
    }
  }, []);

  const accepter = () => {
    localStorage.setItem(COOKIE_KEY, 'true');
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div className="fixed bottom-0 left-0 right-0 z-50 bg-card border-t border-border shadow-lg px-4 py-3">
      <div className="max-w-4xl mx-auto flex flex-col sm:flex-row items-center gap-3">
        <Cookie className="h-5 w-5 text-primary shrink-0" aria-hidden="true" />
        <p className="text-sm text-muted-foreground text-center sm:text-left flex-1">
          Soin Direct utilise des cookies essentiels au fonctionnement de l'application. Aucun cookie publicitaire.
        </p>
        <Button
          onClick={accepter}
          size="sm"
          className="whitespace-nowrap"
        >
          Accepter
        </Button>
      </div>
    </div>
  );
}

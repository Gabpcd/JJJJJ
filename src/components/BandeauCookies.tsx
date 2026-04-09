import { useState, useEffect } from 'react';

export function BandeauCookies() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const consent = localStorage.getItem('cookie-consent');
    if (!consent) {
      // Délai pour ne pas bloquer le premier rendu
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
    <div className="fixed bottom-0 left-0 right-0 z-[9997] p-4 sm:p-6" style={{ paddingBottom: 'calc(1rem + env(safe-area-inset-bottom))' }}>
      <div className="max-w-2xl mx-auto bg-card border border-border rounded-2xl shadow-xl p-4 sm:p-5">
        <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
          <div className="flex-1">
            <p className="text-sm font-semibold text-foreground">Cookies et données personnelles</p>
            <p className="text-xs text-muted-foreground mt-1">
              Jolene utilise des cookies essentiels au fonctionnement de l'application (authentification, préférences).
              Aucun cookie publicitaire ni de tracking n'est utilisé.{' '}
              <a href="/confidentialite" className="text-primary hover:underline">En savoir plus</a>
            </p>
          </div>
          <div className="flex gap-2 shrink-0">
            <button onClick={refuser} className="btn-secondary text-xs px-3 py-2">
              Refuser
            </button>
            <button onClick={accepter} className="btn-primary text-xs px-3 py-2">
              Accepter
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

import { useState, useEffect } from 'react';

const COOKIE_CONSENT_KEY = 'jolene_cookie_consent';

export function BandeauCookies() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const consent = localStorage.getItem(COOKIE_CONSENT_KEY);
    if (!consent) setVisible(true);
  }, []);

  const accepter = () => {
    localStorage.setItem(COOKIE_CONSENT_KEY, JSON.stringify({ accepte: true, date: new Date().toISOString() }));
    setVisible(false);
  };

  const refuser = () => {
    localStorage.setItem(COOKIE_CONSENT_KEY, JSON.stringify({ accepte: false, date: new Date().toISOString() }));
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div className="fixed inset-0 z-[99999] pointer-events-none">
      <div className="pointer-events-auto fixed bottom-0 left-0 right-0 bg-card border-t border-border shadow-lg p-4 sm:p-6 safe-area-bottom">
        <div className="max-w-4xl mx-auto flex flex-col sm:flex-row items-start sm:items-center gap-4">
          <div className="flex-1 text-sm text-foreground">
            <p className="font-semibold mb-1">Cookies et confidentialite</p>
            <p className="text-muted-foreground text-xs">
              Jolene utilise des cookies strictement necessaires au fonctionnement du service (authentification, preferences).
              Aucun cookie publicitaire n'est utilise.{' '}
              <a href="/confidentialite" className="text-primary underline">Politique de confidentialite</a>
            </p>
          </div>
          <div className="flex gap-2 flex-shrink-0">
            <button onClick={refuser} className="btn-secondary text-sm px-4 py-2">
              Refuser
            </button>
            <button onClick={accepter} className="btn-primary text-sm px-4 py-2">
              Accepter
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

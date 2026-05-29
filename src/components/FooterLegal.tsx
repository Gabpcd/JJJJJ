import React from 'react';
import { Link } from 'react-router-dom';
import { isNative } from '@/lib/platform';

export function FooterLegal() {
  // Pas de footer légal (liens CGU/CGV web) dans l'app native : ces pages
  // sont accessibles via le menu/profil. Le footer reste sur le web.
  if (isNative()) return null;

  return (
    <footer className="border-t border-border py-6 text-center no-print">
      <div
        className="h-1 w-full mb-4"
        style={{ background: 'linear-gradient(90deg, hsl(330 85% 60%) 0%, hsl(270 60% 50%) 50%, hsl(215 80% 55%) 100%)' }}
      />
      <div className="max-w-6xl mx-auto px-4">
        <div className="flex flex-wrap items-center justify-center gap-3 text-xs text-muted-foreground">
          <Link to="/aide" className="hover:text-primary hover:underline transition-colors">❓ Centre d'aide</Link>
          <span className="text-primary/30">•</span>
          <Link to="/aide/pro-sante-connect" className="hover:text-primary hover:underline transition-colors">🩺 Aide Pro Santé Connect</Link>
          <span className="text-primary/30">•</span>
          <Link to="/cgu" className="hover:text-primary hover:underline transition-colors">📋 CGU</Link>
          <span className="text-primary/30">•</span>
          <Link to="/cgv" className="hover:text-primary hover:underline transition-colors">💰 CGV</Link>
          <span className="text-primary/30">•</span>
          <Link to="/confidentialite" className="hover:text-primary hover:underline transition-colors">🔒 Confidentialité</Link>
          <span className="text-primary/30">•</span>
          <Link to="/mentions-legales" className="hover:text-primary hover:underline transition-colors">📄 Mentions légales</Link>
          <span className="text-primary/30" aria-hidden="true">•</span>
          <Link to="/accessibilite" className="hover:text-primary hover:underline transition-colors">♿ Accessibilité</Link>
          <span className="text-primary/30" aria-hidden="true">•</span>
          <a href="mailto:contact@jolene.app" className="hover:text-primary hover:underline transition-colors">✉️ Contact</a>
        </div>
        <p className="text-xs text-muted-foreground mt-2">© {new Date().getFullYear()} Jolene SASU — Tous droits réservés 🩷</p>
      </div>
    </footer>
  );
}

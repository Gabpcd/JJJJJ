import React from 'react';
import { Link } from 'react-router-dom';

export function FooterLegal() {
  return (
    <footer className="bg-muted/50 border-t border-border py-4 text-center">
      <div className="max-w-6xl mx-auto px-4">
        <div className="flex flex-wrap items-center justify-center gap-3 text-xs text-muted-foreground">
          <Link to="/cgu" className="hover:text-primary hover:underline">CGU</Link>
          <span>|</span>
          <Link to="/cgv" className="hover:text-primary hover:underline">CGV</Link>
          <span>|</span>
          <Link to="/confidentialite" className="hover:text-primary hover:underline">Confidentialité</Link>
          <span>|</span>
          <Link to="/mentions-legales" className="hover:text-primary hover:underline">Mentions légales</Link>
          <span>|</span>
          <a href="mailto:contact@joleneapp.com" className="hover:text-primary hover:underline">Contact</a>
        </div>
        <p className="text-[10px] text-muted-foreground/60 mt-2">© {new Date().getFullYear()} Jolene SAS — Tous droits réservés</p>
      </div>
    </footer>
  );
}

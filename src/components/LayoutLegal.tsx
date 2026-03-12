import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { HeartPulse, ArrowUp } from 'lucide-react';
import { FooterLegal } from '@/components/FooterLegal';

interface TocItem {
  id: string;
  label: string;
}

interface LayoutLegalProps {
  titre: string;
  dateMaj: string;
  toc: TocItem[];
  children: React.ReactNode;
}

const PAGES_LEGALES = [
  { path: '/cgu', label: 'CGU' },
  { path: '/cgv', label: 'CGV' },
  { path: '/confidentialite', label: 'Confidentialité' },
  { path: '/mentions-legales', label: 'Mentions légales' },
];

export default function LayoutLegal({ titre, dateMaj, toc, children }: LayoutLegalProps) {
  const [showTop, setShowTop] = useState(false);

  useEffect(() => {
    const onScroll = () => setShowTop(window.scrollY > 400);
    window.addEventListener('scroll', onScroll);
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <div className="min-h-screen bg-card flex flex-col">
      {/* Header */}
      <header className="border-b border-border bg-card sticky top-0 z-40">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-4 flex items-center gap-2">
          <Link to="/" className="flex items-center gap-2">
            <HeartPulse className="h-6 w-6 text-primary" />
            <span className="text-lg font-bold text-foreground">Soin Direct</span>
          </Link>
        </div>
      </header>

      <main className="flex-1 max-w-4xl mx-auto w-full px-4 sm:px-6 py-8 sm:py-12">
        {/* Title */}
        <h1 className="text-2xl sm:text-3xl font-extrabold text-foreground mb-1">{titre}</h1>
        <p className="text-sm text-muted-foreground mb-8">Dernière mise à jour : {dateMaj}</p>

        {/* Table of contents */}
        <nav className="bg-muted/50 border border-border rounded-2xl p-5 mb-10">
          <p className="text-sm font-semibold text-foreground mb-3">Sommaire</p>
          <ol className="space-y-1.5">
            {toc.map((item, i) => (
              <li key={item.id}>
                <a
                  href={`#${item.id}`}
                  className="text-sm text-primary hover:underline hover:text-primary/80 transition-colors"
                >
                  {item.label}
                </a>
              </li>
            ))}
          </ol>
        </nav>

        {/* Content */}
        <div className="legal-content space-y-10 text-sm leading-relaxed text-foreground text-justify">
          {children}
        </div>

        {/* Cross-nav */}
        <div className="mt-16 pt-6 border-t border-border">
          <p className="text-xs text-muted-foreground mb-3">Autres pages légales</p>
          <div className="flex flex-wrap gap-3">
            {PAGES_LEGALES.map((p) => (
              <Link
                key={p.path}
                to={p.path}
                className="text-sm text-primary hover:underline font-medium"
              >
                {p.label}
              </Link>
            ))}
          </div>
        </div>
      </main>

      <FooterLegal />

      {/* Back to top */}
      {showTop && (
        <button
          onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
          className="fixed bottom-6 right-6 z-50 bg-primary text-primary-foreground rounded-full p-3 shadow-lg hover:bg-primary/90 transition-all"
          aria-label="Retour en haut"
        >
          <ArrowUp className="h-5 w-5" />
        </button>
      )}
    </div>
  );
}

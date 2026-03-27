import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { HeartPulse, ArrowUp, Printer, ChevronDown } from 'lucide-react';
import { FooterLegal } from '@/components/FooterLegal';
import { SEOHead } from '@/components/SEOHead';
import { useIsMobile } from '@/hooks/use-mobile';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';

interface TocItem {
  id: string;
  label: string;
}

interface LayoutLegalProps {
  titre: string;
  dateMaj: string;
  toc: TocItem[];
  children: React.ReactNode;
  seoDescription?: string;
}

const PAGES_LEGALES = [
  { path: '/cgu', label: 'CGU' },
  { path: '/cgv', label: 'CGV' },
  { path: '/confidentialite', label: 'Confidentialité' },
  { path: '/mentions-legales', label: 'Mentions légales' },
];

export default function LayoutLegal({ titre, dateMaj, toc, children, seoDescription }: LayoutLegalProps) {
  const [showTop, setShowTop] = useState(false);
  const isMobile = useIsMobile();

  useEffect(() => {
    const onScroll = () => setShowTop(window.scrollY > 400);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const tocList = (
    <ol className="space-y-1.5">
      {toc.map((item) => (
        <li key={item.id}>
          <a
            href={`#${item.id}`}
            className="text-base sm:text-sm text-primary underline hover:text-primary/80 transition-colors"
          >
            {item.label}
          </a>
        </li>
      ))}
    </ol>
  );

  return (
    <div className="min-h-screen bg-card flex flex-col">
      <SEOHead
        title={`${titre} — Jolene`}
        description={seoDescription || `${titre} de la plateforme Jolene — Staffing médical simplifié.`}
        url={`https://jolene.app${window.location.pathname}`}
      />

      {/* Header — hidden in print */}
      <header className="border-b border-border bg-card sticky top-0 z-40 no-print">
        <div className="max-w-3xl mx-auto px-4 sm:px-8 py-4 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2">
            <HeartPulse className="h-6 w-6 text-primary" />
            <span className="text-lg font-bold text-foreground">Jolene</span>
          </Link>
          <button
            onClick={() => window.print()}
            className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
            aria-label="Imprimer ou télécharger en PDF"
          >
            <Printer className="h-4 w-4" />
            <span className="hidden sm:inline">Imprimer</span>
          </button>
        </div>
      </header>

      <main className="flex-1 max-w-3xl mx-auto w-full px-4 sm:px-8 py-8 sm:py-12">
        {/* Title */}
        <h1 className="text-2xl sm:text-3xl font-extrabold text-foreground mb-1">{titre}</h1>
        <p className="text-sm text-muted-foreground mb-8">Dernière mise à jour : {dateMaj}</p>

        {/* Table of contents — accordion on mobile, open on desktop */}
        <nav className="bg-muted/50 border border-border rounded-2xl p-5 mb-10 no-print" aria-label="Sommaire">
          {isMobile ? (
            <Collapsible>
              <CollapsibleTrigger className="flex items-center justify-between w-full text-sm font-semibold text-foreground">
                Sommaire
                <ChevronDown className="h-4 w-4 text-muted-foreground" />
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-3">
                {tocList}
              </CollapsibleContent>
            </Collapsible>
          ) : (
            <>
              <p className="text-sm font-semibold text-foreground mb-3">Sommaire</p>
              {tocList}
            </>
          )}
        </nav>

        {/* Content */}
        <div className="legal-content space-y-10 text-base leading-[1.7] text-foreground text-justify">
          {children}
        </div>

        {/* Cross-nav — hidden in print */}
        <div className="mt-16 pt-6 border-t border-border no-print">
          <p className="text-xs text-muted-foreground mb-3">Autres pages légales</p>
          <div className="flex flex-wrap gap-3">
            {PAGES_LEGALES.map((p) => (
              <Link
                key={p.path}
                to={p.path}
                className="text-sm text-primary underline font-medium"
              >
                {p.label}
              </Link>
            ))}
          </div>
        </div>
      </main>

      <FooterLegal />

      {/* Back to top — hidden in print */}
      {showTop && (
        <button
          onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
          className="fixed bottom-6 right-6 z-50 bg-primary text-primary-foreground rounded-full p-3 shadow-lg hover:bg-primary/90 transition-all no-print"
          aria-label="Retour en haut"
        >
          <ArrowUp className="h-5 w-5" />
        </button>
      )}
    </div>
  );
}

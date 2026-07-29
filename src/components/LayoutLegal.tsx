import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowUp, Printer, ChevronDown } from 'lucide-react';
import { FooterLegal } from '@/components/FooterLegal';
import { SEOHead } from '@/components/SEOHead';
import { useIsMobile } from '@/hooks/use-mobile';
import { LogoJolene } from '@/components/LogoJolene';
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
  { path: '/cgu', label: '📋 CGU' },
  { path: '/cgv', label: '💰 CGV' },
  { path: '/confidentialite', label: '🔒 Confidentialité' },
  { path: '/mentions-legales', label: '📄 Mentions légales' },
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
            className="text-base sm:text-sm font-medium text-primary hover:text-primary/70 transition-colors"
          >
            {item.label}
          </a>
        </li>
      ))}
    </ol>
  );

  return (
    <div className="min-h-[100dvh] bg-background flex flex-col">
      <SEOHead
        title={`${titre} — Jolene`}
        description={seoDescription || `${titre} de la plateforme Jolene — Staffing médical simplifié.`}
        url={`https://jolene.app${window.location.pathname}`}
      />

      {/* Header with gradient accent */}
      <header className="border-b border-border bg-card sticky top-0 z-40 no-print">
        <div
          className="h-1 w-full"
          style={{ background: 'linear-gradient(90deg, hsl(330 85% 60%) 0%, hsl(270 60% 50%) 50%, hsl(215 80% 55%) 100%)' }}
        />
        <div className="max-w-3xl mx-auto px-4 sm:px-8 py-4 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2">
            <LogoJolene
              imageClassName="h-6 w-6"
              nomClassName="text-lg"
            />
          </Link>
          <button
            onClick={() => window.print()}
            className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-primary transition-colors"
            aria-label="Imprimer ou télécharger en PDF"
          >
            <Printer className="h-4 w-4" />
            <span className="hidden sm:inline">Imprimer</span>
          </button>
        </div>
      </header>

      <main className="flex-1 max-w-3xl mx-auto w-full px-4 sm:px-8 py-8 sm:py-12">
        {/* Title with gradient */}
        <h1
          className="text-2xl sm:text-3xl font-extrabold mb-1 bg-clip-text text-transparent"
          style={{ backgroundImage: 'linear-gradient(135deg, hsl(330 85% 60%) 0%, hsl(270 60% 50%) 100%)' }}
        >
          {titre}
        </h1>
        <p className="text-sm text-muted-foreground mb-8">📅 Dernière mise à jour : {dateMaj}</p>

        {/* Table of contents */}
        <nav
          className="rounded-2xl p-5 mb-10 no-print border border-primary/10"
          style={{ background: 'linear-gradient(135deg, hsl(330 85% 60% / 0.05) 0%, hsl(270 60% 50% / 0.08) 100%)' }}
          aria-label="Sommaire"
        >
          {isMobile ? (
            <Collapsible>
              <CollapsibleTrigger className="flex items-center justify-between w-full text-sm font-semibold text-foreground">
                📑 Sommaire
                <ChevronDown className="h-4 w-4 text-muted-foreground" />
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-3">
                {tocList}
              </CollapsibleContent>
            </Collapsible>
          ) : (
            <>
              <p className="text-sm font-semibold text-foreground mb-3">📑 Sommaire</p>
              {tocList}
            </>
          )}
        </nav>

        {/* Content */}
        <div className="legal-content space-y-10 text-base leading-[1.7] text-foreground text-justify">
          {children}
        </div>

        {/* Cross-nav */}
        <div className="mt-16 pt-6 border-t border-border no-print">
          <p className="text-xs text-muted-foreground mb-3">Autres pages légales</p>
          <div className="flex flex-wrap gap-3">
            {PAGES_LEGALES.map((p) => (
              <Link
                key={p.path}
                to={p.path}
                className="text-sm text-primary font-medium hover:text-primary/70 transition-colors px-3 py-1.5 rounded-full border border-primary/20 hover:bg-primary/5"
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
          className="fixed bottom-6 right-6 z-50 rounded-full p-3 shadow-lg hover:shadow-xl transition-all no-print text-white"
          style={{ background: 'linear-gradient(135deg, hsl(330 85% 60%) 0%, hsl(270 60% 50%) 100%)' }}
          aria-label="Retour en haut"
        >
          <ArrowUp className="h-5 w-5" />
        </button>
      )}
    </div>
  );
}

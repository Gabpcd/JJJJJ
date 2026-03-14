import React from 'react';
import { useNavigate } from 'react-router-dom';
import { HeartPulse, ArrowRight } from 'lucide-react';
import { FooterLegal } from '@/components/FooterLegal';

interface SEOPageLayoutProps {
  children: React.ReactNode;
  heroTitle: string;
  heroSubtitle: string;
  ctaText: string;
  ctaHref: string;
}

export function SEOPageLayout({ children, heroTitle, heroSubtitle, ctaText, ctaHref }: SEOPageLayoutProps) {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-background text-foreground">
      {/* Header */}
      <header className="sticky top-0 z-50 bg-card/80 backdrop-blur-lg border-b border-border">
        <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
          <a href="/" className="flex items-center gap-2">
            <HeartPulse className="h-7 w-7 text-primary" />
            <span className="text-xl font-bold text-foreground">Soin Direct</span>
          </a>
          <div className="flex items-center gap-4">
            <a href="/blog" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">Blog</a>
            <a href="/a-propos" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">À propos</a>
            <a href="/tarifs" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors hidden sm:inline">Tarifs</a>
            <button onClick={() => navigate('/connexion')} className="text-sm font-semibold text-primary hover:text-primary/80 transition-colors">
              Se connecter
            </button>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="relative bg-gradient-to-br from-primary/10 via-background to-primary/5 py-16 md:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center">
          <h1 className="text-3xl md:text-5xl font-extrabold text-foreground leading-tight mb-4">{heroTitle}</h1>
          <p className="text-lg md:text-xl text-muted-foreground max-w-2xl mx-auto">{heroSubtitle}</p>
        </div>
      </section>

      {/* Content */}
      <main>{children}</main>

      {/* CTA final */}
      <section className="py-16 md:py-20 bg-gradient-to-r from-primary to-primary-dark text-primary-foreground">
        <div className="max-w-3xl mx-auto px-4 text-center">
          <h2 className="text-2xl md:text-3xl font-bold mb-4">Prêt à commencer ?</h2>
          <button
            onClick={() => navigate(ctaHref)}
            className="inline-flex items-center gap-2 bg-primary-foreground text-primary font-semibold px-8 py-3 rounded-lg hover:bg-primary-foreground/90 transition-colors text-base"
          >
            {ctaText} <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border bg-card py-12">
        <div className="max-w-6xl mx-auto px-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            <div className="col-span-2 md:col-span-1">
              <div className="flex items-center gap-2 mb-3">
                <HeartPulse className="h-5 w-5 text-primary" />
                <span className="font-bold text-foreground">Soin Direct</span>
              </div>
              <p className="text-sm text-muted-foreground leading-relaxed">La plateforme de confiance pour le remplacement et le staffing en santé.</p>
            </div>
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Plateforme</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/inscription/soignant" className="hover:text-foreground transition-colors">Soignants</a></li>
                <li><a href="/inscription/etablissement" className="hover:text-foreground transition-colors">Établissements</a></li>
                <li><a href="/tarifs" className="hover:text-foreground transition-colors">Tarifs</a></li>
                <li><a href="/a-propos" className="hover:text-foreground transition-colors">À propos</a></li>
                <li><a href="/telecharger" className="hover:text-foreground transition-colors">Télécharger</a></li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Ressources</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/devenir-soignant" className="hover:text-foreground transition-colors">Devenir soignant</a></li>
                <li><a href="/recruter-soignants" className="hover:text-foreground transition-colors">Recruter des soignants</a></li>
                <li><a href="/infirmiere-liberale" className="hover:text-foreground transition-colors">Passer en libéral</a></li>
                <li><a href="/pharmacie-remplacement" className="hover:text-foreground transition-colors">Remplacement pharmacie</a></li>
                <li><a href="/blog" className="hover:text-foreground transition-colors">Blog</a></li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold text-foreground text-sm mb-3">Légal</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="/cgu" className="hover:text-foreground transition-colors">CGU</a></li>
                <li><a href="/cgv" className="hover:text-foreground transition-colors">CGV</a></li>
                <li><a href="/confidentialite" className="hover:text-foreground transition-colors">Confidentialité</a></li>
                <li><a href="/mentions-legales" className="hover:text-foreground transition-colors">Mentions légales</a></li>
              </ul>
            </div>
          </div>
          <div className="border-t border-border mt-10 pt-6 text-center">
            <p className="text-xs text-muted-foreground">© 2026 Soin Direct SAS — Tous droits réservés</p>
          </div>
        </div>
      </footer>
    </div>
  );
}

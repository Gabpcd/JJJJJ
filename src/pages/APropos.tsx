import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Linkedin, Download, ShieldCheck, Stethoscope, Scale, DatabaseZap, Building2 } from 'lucide-react';
import { Button } from '@/components/ui/button';

const chiffres = [
  { icon: Stethoscope, label: '15+ professions', sub: 'de santé couvertes' },
  { icon: ShieldCheck, label: 'Marque déposée INPI', sub: 'N°5186614' },
  { icon: Scale, label: 'Code du travail', sub: 'Conformité intégrée' },
  { icon: DatabaseZap, label: '0 donnée de santé', sub: 'stockée sur la plateforme' },
];

export default function APropos() {
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="À propos de Jolene | Staffing médical digital"
        description="Découvrez la mission de Jolene : simplifier le staffing médical en connectant établissements de santé et soignants qualifiés, en toute conformité."
        url="https://app.jolene.app/a-propos"
      />
      <SEOPageLayout
        heroTitle="Simplifier le staffing médical. Pour de bon."
        heroSubtitle="Jolene est née d'un constat simple : trouver un soignant remplaçant ne devrait pas prendre des heures d'appels téléphoniques."
        ctaText="Rejoindre Jolene"
        ctaHref="/inscription/soignant"
      >
        {/* Mission */}
        <section className="py-16 md:py-20">
          <div className="max-w-3xl mx-auto px-4 text-center">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-6">Notre mission</h2>
            <p className="text-muted-foreground leading-relaxed text-lg">
              Nous connectons les établissements de santé avec des soignants qualifiés et vérifiés, en automatisant tout ce qui peut l'être : contrats, conformité, pointage, facturation. Notre objectif : que chaque établissement trouve le bon soignant en moins d'une heure.
            </p>
          </div>
        </section>

        {/* Fondatrice */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">La fondatrice</h2>
            <div className="flex flex-col md:flex-row items-center gap-4 md:gap-8">
              {/* Avatar placeholder */}
              <div className="w-28 h-28 rounded-full bg-primary flex items-center justify-center shrink-0">
                <span className="text-3xl font-bold text-primary-foreground">GP</span>
              </div>
              <div>
                <h3 className="font-bold text-foreground text-xl mb-1">Gabrielle Picard</h3>
                <p className="text-sm text-muted-foreground mb-4">Fondatrice & CEO</p>
                <p className="text-muted-foreground leading-relaxed mb-4">
                  Passionnée par l'innovation dans la santé, Gabrielle a fondé Jolene pour répondre à la pénurie de soignants qui touche des milliers d'établissements en France. Son ambition : devenir la référence du staffing médical digital.
                </p>
                <a
                  href="https://linkedin.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 text-sm text-primary hover:text-primary/80 transition-colors font-medium"
                >
                  <Linkedin className="h-4 w-4" /> LinkedIn
                </a>
              </div>
            </div>
          </div>
        </section>

        {/* Partenaires */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Nos partenaires</h2>
            <div className="grid md:grid-cols-2 gap-6">
              <div className="bg-card border border-border rounded-xl p-6">
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                    <Building2 className="h-5 w-5 text-primary" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">Groupe Leader Santé</h3>
                    <p className="text-xs text-muted-foreground">Partenaire pilote</p>
                  </div>
                </div>
                <p className="text-sm text-muted-foreground">Réseau de 600+ pharmacies d'officine en France. Premier partenaire de Jolene pour le déploiement du remplacement en pharmacie.</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-6">
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                    <Building2 className="h-5 w-5 text-primary" />
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground">Clinique des Bluets</h3>
                    <p className="text-xs text-muted-foreground">Lettre d'intention signée</p>
                  </div>
                </div>
                <p className="text-sm text-muted-foreground">Maternité et chirurgie — Paris. Établissement pilote pour le staffing infirmier et aide-soignant via Jolene.</p>
              </div>
            </div>
          </div>
        </section>

        {/* Chiffres clés */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Chiffres clés</h2>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-6">
              {chiffres.map((c) => (
                <div key={c.label} className="text-center">
                  <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mx-auto mb-3">
                    <c.icon className="h-6 w-6 text-primary" />
                  </div>
                  <p className="font-bold text-foreground">{c.label}</p>
                  <p className="text-xs text-muted-foreground mt-1">{c.sub}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Presse & Contact */}
        <section className="py-16 md:py-20">
          <div className="max-w-3xl mx-auto px-4 text-center">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-4">Presse & Contact</h2>
            <p className="text-muted-foreground mb-8">
              Vous êtes journaliste ou partenaire potentiel ? Contactez-nous à{' '}
              <a href="mailto:contact@jolene.app" className="text-primary hover:underline font-medium">contact@jolene.app</a>.
            </p>
            <Button variant="outline" disabled className="gap-2">
              <Download className="h-4 w-4" /> Télécharger le dossier de presse
            </Button>
            <p className="text-xs text-muted-foreground mt-2">Bientôt disponible</p>
          </div>
        </section>

        {/* Investisseurs */}
        <section className="py-12 md:py-16">
          <div className="max-w-2xl mx-auto px-4 text-center">
            <p className="text-sm text-muted-foreground">
              Jolene prépare sa levée de fonds seed. Si vous êtes investisseur, contactez-nous à{' '}
              <a href="mailto:contact@jolene.app" className="text-primary hover:underline font-medium">contact@jolene.app</a>.
            </p>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}

import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Download, ShieldCheck, Stethoscope, Scale, DatabaseZap } from 'lucide-react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

const chiffres = [
  { icon: Stethoscope, label: '15+ professions', sub: 'de santé couvertes' },
  { icon: ShieldCheck, label: 'Marque déposée INPI', sub: 'N°5186614' },
  { icon: Scale, label: 'Code du travail', sub: 'Conformité intégrée' },
  { icon: DatabaseZap, label: 'Données sensibles limitées', sub: 'déclarations professionnelles protégées' },
];

export default function APropos() {
  usePageTitle('À propos');
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="À propos de Jolene | Staffing médical digital"
        description="Découvrez la mission de Jolene : simplifier le staffing médical en connectant établissements de santé et soignants qualifiés, en toute conformité."
        url="https://jolene.app/a-propos"
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
              Nous connectons les établissements de santé avec des soignants qualifiés et vérifiés, en automatisant tout ce qui peut l'être : contrats, conformité, pointage, facturation. Notre objectif : que chaque établissement trouve le bon soignant, sans passer des heures au téléphone.
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
                <p className="text-muted-foreground leading-relaxed">
                  Passionnée par l'innovation dans la santé, Gabrielle a fondé Jolene pour répondre à la pénurie de soignants qui touche des milliers d'établissements en France. Son ambition : devenir la référence du staffing médical digital.
                </p>
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
              Vous êtes journaliste ou partenaire potentiel ? Écrivez directement à Gabrielle à{' '}
              <a href="mailto:gabrielle@jolene.app" className="text-primary hover:underline font-medium">gabrielle@jolene.app</a>.
            </p>
            <BoutonY2K variant="secondary" disabled iconeGauche={<Download className="h-4 w-4" />}>
              Télécharger le dossier de presse
            </BoutonY2K>
            <p className="text-xs text-muted-foreground mt-2">Bientôt disponible</p>
          </div>
        </section>

        {/* Investisseurs */}
        <section className="py-12 md:py-16">
          <div className="max-w-2xl mx-auto px-4 text-center">
            <p className="text-sm text-muted-foreground">
              Jolene prépare sa levée de fonds seed. Si vous êtes investisseur, écrivez directement à Gabrielle à{' '}
              <a href="mailto:gabrielle@jolene.app" className="text-primary hover:underline font-medium">gabrielle@jolene.app</a>.
            </p>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}

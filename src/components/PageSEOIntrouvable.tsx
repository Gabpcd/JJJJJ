import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { MapPin } from 'lucide-react';

interface Props {
  titre: string;
  liens: { href: string; label: string }[];
}

/**
 * Slug SEO inconnu : la SPA ne peut pas renvoyer de HTTP 404, la page est donc
 * explicitement `noindex` (pas de soft-404 indexable) et renvoie vers les pages connues.
 */
export function PageSEOIntrouvable({ titre, liens }: Props) {
  return (
    <>
      <SEOHead
        title="Page introuvable | Jolene Santé"
        description="Cette page n’existe pas ou n’est plus disponible."
        noIndex
      />
      <SEOPageLayout
        heroTitle={titre}
        heroSubtitle="Cette page n’existe pas. Voici des pages disponibles."
        ctaText="Voir les missions"
        ctaHref="/devenir-soignant"
      >
        <section className="py-12 md:py-16">
          <div className="max-w-5xl mx-auto px-4">
            <div className="flex flex-wrap justify-center gap-3">
              {liens.map((l) => (
                <a
                  key={l.href}
                  href={l.href}
                  className="inline-flex items-center gap-1.5 bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors"
                >
                  <MapPin className="h-3.5 w-3.5" />
                  {l.label}
                </a>
              ))}
            </div>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}

import { useParams } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ContenuSEO } from '@/components/ContenuSEO';
import { PageSEOIntrouvable } from '@/components/PageSEOIntrouvable';
import { TYPES_ETABLISSEMENT_SEO } from '@/lib/seo-contenu/etablissements';
import { cheminEtablissement, jsonLdPage, metaEtablissement, resoudreEtablissement, urlAbsolue } from '@/lib/seo-routes';

/**
 * /recruter-soignants/:type — une page par type d'établissement (EHPAD, clinique, hôpital
 * public, soins à domicile, handicap). Tout le texte vient de `seo-routes` : le HTML
 * statique et la page rendue sont identiques par construction.
 */
export default function RecruterTypeLanding() {
  const { type } = useParams<{ type: string }>();
  const etablissement = resoudreEtablissement(type);

  // Slug inconnu : page noindex et liens vers les types connus (pas de soft-404 indexable).
  if (!etablissement) {
    return (
      <PageSEOIntrouvable
        titre="Page non référencée"
        liens={[
          { href: '/recruter-soignants', label: 'Recruter des soignants' },
          ...TYPES_ETABLISSEMENT_SEO.map((t) => ({ href: cheminEtablissement(t.slug), label: t.nom })),
        ]}
      />
    );
  }

  const meta = metaEtablissement(etablissement);
  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout heroTitle={meta.h1} heroSubtitle={meta.intro[0]} ctaText="Créer mon espace établissement" ctaHref="/inscription/etablissement">
        <ContenuSEO page={meta} />
      </SEOPageLayout>
    </>
  );
}

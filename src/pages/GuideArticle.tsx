import { useParams } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ContenuSEO } from '@/components/ContenuSEO';
import { PageSEOIntrouvable } from '@/components/PageSEOIntrouvable';
import { GUIDES_SEO } from '@/lib/seo-contenu/guides';
import { CHEMIN_GUIDES, cheminGuide, jsonLdPage, metaGuide, resoudreGuide, urlAbsolue } from '@/lib/seo-routes';

/** /guides/:slug — un guide éditorial. Tout le texte vient de `seo-routes` (identique au HTML statique). */
export default function GuideArticle() {
  const { slug } = useParams<{ slug: string }>();
  const guide = resoudreGuide(slug);

  if (!guide) {
    return (
      <PageSEOIntrouvable
        titre="Guide introuvable"
        liens={[{ href: CHEMIN_GUIDES, label: 'Tous les guides' }, ...GUIDES_SEO.map((g) => ({ href: cheminGuide(g.slug), label: g.titre }))]}
      />
    );
  }

  const meta = metaGuide(guide);
  const soignant = guide.public === 'soignant';
  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout
        heroTitle={meta.h1}
        heroSubtitle={meta.intro[0]}
        ctaText={soignant ? 'Créer mon compte gratuitement' : 'Créer mon espace établissement'}
        ctaHref={soignant ? '/inscription/soignant' : '/inscription/etablissement'}
      >
        <ContenuSEO page={meta} />
      </SEOPageLayout>
    </>
  );
}

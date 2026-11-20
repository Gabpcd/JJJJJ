import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ContenuSEO } from '@/components/ContenuSEO';
import { jsonLdPage, metaGuides, urlAbsolue } from '@/lib/seo-routes';

const meta = metaGuides();

/** /guides — sommaire des guides, par public. */
export default function GuidesIndex() {
  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout heroTitle={meta.h1} heroSubtitle={meta.intro[0]} ctaText="Créer mon compte gratuitement" ctaHref="/inscription/soignant">
        <ContenuSEO page={meta} />
      </SEOPageLayout>
    </>
  );
}

import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ContenuSEO } from '@/components/ContenuSEO';
import { jsonLdPage, metaBarometre, urlAbsolue } from '@/lib/seo-routes';

const meta = metaBarometre();

/** /barometre-recrutement-soignants-2026 — tableau par département (enquête BMO + répertoire FINESS). */
export default function BarometreRecrutement() {
  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout heroTitle={meta.h1} heroSubtitle={meta.intro[0]} ctaText="Publier une mission" ctaHref="/inscription/etablissement">
        <ContenuSEO page={meta} />
      </SEOPageLayout>
    </>
  );
}

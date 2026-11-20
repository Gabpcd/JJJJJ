import { useParams } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { MissionsPubliquesSEO } from '@/components/MissionsPubliquesSEO';
import { PageSEOIntrouvable } from '@/components/PageSEOIntrouvable';
import { getVilleBySlug } from '@/lib/seo-data';
import { lienInscriptionRecherche } from '@/lib/recherchePubliqueInscription';
import {
  metaVilleMetier,
  resoudreVilleMetier,
  urlAbsolue,
  cheminVille,
  cheminMetier,
  contenuUtmVilleMetier,
  UTM_VILLE_METIER,
  phraseBmo,
  PROFESSIONS_SEO_VILLE_METIER,
  VILLES_VILLE_METIER,
  cheminVilleMetier,
  estVilleVilleMetier,
  jsonLdPage,
  phraseFiness,
  aVille,
  SOURCES_LOCALES,
} from '@/lib/seo-routes';
import { Sources } from '@/components/ContenuSEO';

/**
 * /emploi-soignant/:ville/:profession — périmètre restreint (grandes villes ×
 * métiers à forte demande). Hors périmètre : page noindex + liens vers les pages connues.
 */
export default function VilleProfessionLanding() {
  const { ville: villeSlug, profession: professionSlug } = useParams<{ ville: string; profession: string }>();
  const resolu = resoudreVilleMetier(villeSlug, professionSlug);

  if (!resolu) {
    const villeConnue = villeSlug ? getVilleBySlug(villeSlug) : undefined;
    // Une ville connue hors périmètre ville × métier n'a que sa page ville : on renvoie
    // vers elle et vers les pages métier, jamais vers d'autres pages non référencées.
    const liens = villeConnue
      ? [
          { href: cheminVille(villeConnue.slug), label: `Missions soignants ${aVille(villeConnue)}` },
          ...PROFESSIONS_SEO_VILLE_METIER.map((p) => (estVilleVilleMetier(villeConnue.slug)
            ? { href: cheminVilleMetier(villeConnue.slug, p.slug), label: `${p.label} ${aVille(villeConnue)}` }
            : { href: cheminMetier(p.slug), label: `Missions ${p.label}` })),
        ]
      : VILLES_VILLE_METIER.map((v) => ({ href: cheminVille(v.slug), label: v.nom }));
    return <PageSEOIntrouvable titre="Page non référencée" liens={liens} />;
  }

  const { ville, profession } = resolu;
  const meta = metaVilleMetier(ville, profession);
  const bmo = phraseBmo(ville.departement, profession.valeur);
  const finess = phraseFiness(ville, profession.valeur);
  const reperes = [bmo, finess].filter((p): p is string => !!p);
  const utm = { ...UTM_VILLE_METIER, content: contenuUtmVilleMetier(ville.slug, profession.slug) };
  const lienInscription = lienInscriptionRecherche({ profession: profession.valeur, ville: ville.nom }, utm);
  // Paragraphes d'intro hors repères chiffrés (affichés à part, avec leurs sources).
  const paragraphes = meta.intro.filter((p) => !reperes.includes(p));

  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} noIndex={!meta.indexable} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout
        heroTitle={meta.h1}
        heroSubtitle={paragraphes[0]}
        ctaText="M'inscrire gratuitement"
        ctaHref={lienInscription}
      >
        <section className="py-12 md:py-16">
          <div className="max-w-3xl mx-auto px-4 space-y-4">
            {paragraphes.slice(1).map((p) => (
              <p key={p} className="text-muted-foreground leading-relaxed">{p}</p>
            ))}
            {reperes.length > 0 && (
              <aside className="rounded-xl border border-border bg-card p-4 space-y-3" aria-label={`Repères locaux ${aVille(ville)}`}>
                {reperes.map((p) => <p key={p} className="text-foreground leading-relaxed">{p}</p>)}
                <Sources sources={[...(bmo ? [SOURCES_LOCALES[0]] : []), ...(finess ? [SOURCES_LOCALES[1]] : [])]} />
              </aside>
            )}
          </div>
        </section>

        <MissionsPubliquesSEO
          profession={profession.valeur}
          ville={ville.nom}
          campagne={UTM_VILLE_METIER.campaign}
          utm={utm}
        />

        <section className="py-12 md:py-16 bg-muted/50">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-6">Pour aller plus loin</h2>
            <ul className="flex flex-wrap justify-center gap-3">
              {meta.liens.map((l) => (
                <li key={l.href}>
                  <a
                    href={l.href}
                    className="inline-flex items-center bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors"
                  >
                    {l.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}

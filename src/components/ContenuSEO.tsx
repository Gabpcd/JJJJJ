import type { PageSEO } from '@/lib/seo-routes';
import type { SectionSEO, SourceSEO } from '@/lib/seo-contenu/types';

/**
 * Rend le contenu d'une page décrite dans `src/lib/seo-routes.ts` : paragraphes d'ouverture,
 * sections (paragraphes, points titrés, liste, tableau, liens, sources), questions fréquentes et
 * liens internes. Le HTML statique (`contenuRacine` du générateur) rend la même structure à
 * partir du même objet : la page lue par un robot sans JavaScript et la page affichée
 * portent donc le même texte, par construction.
 *
 * Le premier paragraphe d'introduction est porté par le hero de `SEOPageLayout`
 * (`heroSubtitle`) ; ce composant affiche les suivants.
 */
export function ContenuSEO({ page }: { page: PageSEO }) {
  const suite = page.intro.slice(1);
  return (
    <>
      {suite.length > 0 && (
        <section className="py-12 md:py-16">
          <div className="max-w-3xl mx-auto px-4 space-y-4">
            {suite.map((p) => (
              <p key={p} className="text-muted-foreground leading-relaxed text-base md:text-lg">{p}</p>
            ))}
          </div>
        </section>
      )}

      {(page.sections ?? []).map((section, i) => (
        <SectionContenu key={section.titre} section={section} alterne={i % 2 === 0} />
      ))}

      {!!page.faq?.length && (
        <section className="py-12 md:py-16 bg-card">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">Questions fréquentes</h2>
            <div className="space-y-4">
              {page.faq.map((item) => (
                <details key={item.q} className="group rounded-xl border border-border bg-background p-5">
                  <summary className="cursor-pointer list-none font-semibold text-foreground flex items-center justify-between gap-2 min-h-[44px]">
                    {item.q}
                    <span aria-hidden="true" className="text-primary transition-transform group-open:rotate-45 text-xl leading-none">+</span>
                  </summary>
                  <p className="mt-3 text-muted-foreground leading-relaxed">{item.r}</p>
                </details>
              ))}
            </div>
          </div>
        </section>
      )}

      {page.liens.length > 0 && (
        <section className="py-12 md:py-16 bg-muted/50">
          <nav className="max-w-5xl mx-auto px-4" aria-label="Pages liées">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-6">Pour aller plus loin</h2>
            <ul className="flex flex-wrap justify-center gap-3">
              {page.liens.map((l) => (
                <li key={l.href}>
                  <a
                    href={l.href}
                    className="inline-flex items-center min-h-[44px] bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors"
                  >
                    {l.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </section>
      )}
    </>
  );
}

function SectionContenu({ section, alterne }: { section: SectionSEO; alterne: boolean }) {
  const large = !!section.tableau || (section.points?.length ?? 0) > 2;
  return (
    <section className={`py-12 md:py-16 ${alterne ? 'bg-muted/50' : ''}`}>
      <div className={`${large ? 'max-w-5xl' : 'max-w-3xl'} mx-auto px-4`}>
        <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-6">{section.titre}</h2>

        {section.paragraphes?.map((p) => (
          <p key={p} className="text-muted-foreground leading-relaxed mb-4">{p}</p>
        ))}

        {!!section.points?.length && (
          <div className={`grid gap-4 ${large ? 'md:grid-cols-2' : ''} mb-4`}>
            {section.points.map((point) => (
              <div key={point.titre} className="rounded-xl border border-border bg-card p-5">
                <h3 className="font-semibold text-foreground mb-2">
                  {point.href
                    ? <a href={point.href} className="inline-flex items-center min-h-[44px] text-primary underline underline-offset-4 hover:text-primary/80">{point.titre}</a>
                    : point.titre}
                </h3>
                <p className="text-sm text-muted-foreground leading-relaxed">{point.texte}</p>
              </div>
            ))}
          </div>
        )}

        {!!section.liste?.length && (section.ordonnee
          ? (
            <ol className="list-decimal pl-6 space-y-2 text-muted-foreground leading-relaxed mb-4 marker:font-semibold marker:text-foreground">
              {section.liste.map((e) => <li key={e}>{e}</li>)}
            </ol>
          )
          : (
            <ul className="list-disc pl-6 space-y-2 text-muted-foreground leading-relaxed mb-4">
              {section.liste.map((e) => <li key={e}>{e}</li>)}
            </ul>
          ))}

        {section.tableau && (
          // Zone défilante au clavier : un tableau large ne doit jamais élargir la page sur mobile.
          <div role="region" aria-label={section.tableau.legende} tabIndex={0} className="overflow-x-auto rounded-xl border border-border bg-card mb-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary">
            <table className="w-full text-sm text-left">
              <caption className="sr-only">{section.tableau.legende}</caption>
              <thead className="bg-muted/60 text-foreground">
                <tr>
                  {section.tableau.entetes.map((e, i) => (
                    <th
                      key={`${e}-${i}`}
                      scope="col"
                      // Première colonne figée : sur téléphone, on garde le nom de la ligne en faisant défiler les chiffres.
                      className={`px-3 py-3 font-semibold align-bottom whitespace-normal ${i === 0 ? 'sticky left-0 z-10 bg-muted min-w-[8.5rem] max-w-[10rem]' : 'min-w-[6.5rem]'}`}
                    >
                      {e}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {section.tableau.lignes.map((ligne) => (
                  <tr key={ligne[0]} className="border-t border-border">
                    {ligne.map((cellule, i) => (i === 0
                      ? <th key={i} scope="row" className="sticky left-0 bg-card px-3 py-2 font-medium text-foreground whitespace-normal min-w-[8.5rem] max-w-[10rem] border-r border-border">{cellule}</th>
                      : <td key={i} className="px-3 py-2 text-muted-foreground tabular-nums">{cellule}</td>))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!!section.liens?.length && (
          <ul className="flex flex-wrap gap-3 mb-4">
            {section.liens.map((l) => (
              <li key={l.href}>
                <a href={l.href} className="inline-flex items-center min-h-[44px] bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors">
                  {l.label}
                </a>
              </li>
            ))}
          </ul>
        )}

        {!!section.sources?.length && <Sources sources={section.sources} />}
      </div>
    </section>
  );
}

export function Sources({ sources }: { sources: SourceSEO[] }) {
  return (
    <p className="text-sm text-muted-foreground">
      {sources.length > 1 ? 'Sources : ' : 'Source : '}
      {sources.map((s, i) => (
        <span key={s.href}>
          {i > 0 && ' ; '}
          <a href={s.href} target="_blank" rel="noopener noreferrer" className="underline underline-offset-4 hover:text-foreground">{s.label}</a>
        </span>
      ))}
      .
    </p>
  );
}

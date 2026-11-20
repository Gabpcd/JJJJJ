import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Check } from 'lucide-react';
import { SEOHead } from '@/components/SEOHead';
import { INCLUS_TARIFS, TAUX_HT, TAUX_TTC, TITRE_COMMISSION } from '@/lib/seo-contenu/tarifs';
import { jsonLdPage, metaInstitutionnelle, urlAbsolue } from '@/lib/seo-routes';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

/** Titre, description, H1 et accroche : mêmes valeurs que le HTML statique (`seo-routes`). */
const meta = metaInstitutionnelle('tarifs');

export default function Tarifs() {
  const navigate = useNavigate();

  return (
    <>
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <div className="min-h-[100dvh] bg-background flex flex-col">
        <header className="py-4 px-4 border-b border-border bg-card">
          <div className="max-w-6xl mx-auto flex items-center justify-between">
            <button onClick={() => navigate('/')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <ArrowLeft className="h-4 w-4" /> Retour
            </button>
            <button onClick={() => navigate('/inscription/etablissement')} className="btn-primary text-sm">
              S'inscrire gratuitement
            </button>
          </div>
        </header>

        <main className="flex-1 max-w-3xl mx-auto px-4 py-16 w-full">
          <div className="text-center mb-12">
            <h1 className="text-3xl md:text-4xl font-black text-foreground mb-3">
              {meta.h1}
            </h1>
            <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
              {meta.intro[0]}
            </p>
          </div>

          <div className="card-base text-center p-8 md:p-10">
            <p className="text-sm font-semibold uppercase tracking-widest text-muted-foreground mb-2">{TITRE_COMMISSION}</p>
            <p className="text-6xl font-black text-primary mb-1">{TAUX_HT}</p>
            <p className="text-base font-semibold text-foreground mb-2">{TAUX_TTC}</p>
            <p className="text-sm text-muted-foreground mb-8">
              Commission ajoutée aux honoraires HT d'une mission libérale ou à la rémunération brute contractuelle d'une mission salariée, et facturée à l'établissement ; elle ne réduit ni les honoraires ni la base salariale du soignant.
              <br />Taux HT négocié possible pour les groupes — <a href="mailto:support@jolene.app" className="text-primary underline">contactez-nous</a>.
            </p>
            <ul className="text-left max-w-md mx-auto space-y-2.5">
              {INCLUS_TARIFS.map((item) => (
                <li key={item} className="flex items-start gap-2.5 text-sm text-foreground">
                  <Check className="h-4 w-4 text-success shrink-0 mt-0.5" />
                  {item}
                </li>
              ))}
            </ul>

            {/* CTA en bas de carte : l'étab vient de lire toute la valeur,
                il peut agir immédiatement sans remonter au header */}
            <div className="mt-8 flex flex-col items-center gap-2">
              <BoutonY2K variant="primary" onClick={() => navigate('/inscription/etablissement')}>
                S'inscrire gratuitement
              </BoutonY2K>
              <p className="text-xs text-muted-foreground">Sans engagement · 2 minutes</p>
            </div>
          </div>

          <p className="text-center text-xs text-muted-foreground mt-6">
            {meta.intro[1]}
          </p>
        </main>

        <footer className="py-8 text-center text-sm text-muted-foreground border-t border-border bg-card">
          <p>© 2026 Jolene SAS — Protection des données · cadre contractuel traçable</p>
        </footer>
      </div>
    </>
  );
}

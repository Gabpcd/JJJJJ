import { Link } from 'react-router-dom';
import { Accessibility, ArrowLeft, Mail } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { FooterLegal } from '@/components/FooterLegal';

export default function PageAccessibilite() {
  usePageTitle('Engagement accessibilité');

  return (
    <div className="min-h-[100dvh] flex flex-col bg-background">
      <main id="main-content" tabIndex={-1} className="flex-1 max-w-3xl w-full mx-auto px-4 py-8">
        {/* a11y page-scoped : text-jolene-rose-800 (7,05:1 light / ~11,8:1 dark, var thème-aware)
            au lieu de text-primary (5,08:1) — marge AA confortable + underline permanent (lien
            distinguable autrement que par la couleur, WCAG 1.4.1). */}
        <Link to="/" className="inline-flex items-center gap-1.5 text-sm text-jolene-rose-800 underline mb-6">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Retour à l'accueil
        </Link>

        <header className="mb-8">
          <div className="flex items-center gap-3 mb-3">
            <Accessibility className="h-8 w-8 text-jolene-rose-800" aria-hidden="true" />
            <h1 className="text-2xl font-bold text-foreground">Engagement accessibilité</h1>
          </div>
          <p className="text-sm text-muted-foreground">
            Jolene SASU s'engage à rendre sa plateforme accessible au plus grand nombre et
            améliore l'accessibilité en continu.
          </p>
        </header>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">État de conformité</h2>
          <p className="text-sm text-foreground"><strong>Conformité non encore évaluée</strong> par un audit RGAA complet. Les améliorations ci-dessous sont déployées progressivement et ne valent pas déclaration de conformité.</p>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Mesures actuellement déployées</h2>
          <ul className="list-disc list-inside text-sm text-foreground space-y-1.5 ml-2">
            <li>Tests automatisés via <strong>axe-core</strong> sur les parcours critiques</li>
            <li>Indicateurs de focus visibles et corrections progressives de la navigation clavier</li>
            <li>Palette de contraste renforcée et taille minimale des principales zones tactiles</li>
            <li>Lien <em>« Aller au contenu principal »</em> global</li>
            <li>Attribut <code>lang="fr"</code> sur l'élément racine</li>
            <li>Étiquetage accessible des nouveaux formulaires et correction continue des écrans historiques</li>
            <li>Respect de <code>prefers-reduced-motion</code> pour les personnes sensibles aux animations</li>
          </ul>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Signaler un problème</h2>
          <p className="text-sm text-foreground">
            Si vous rencontrez une difficulté d'accessibilité, écrivez-nous :
          </p>
          <a
            href="mailto:support@jolene.app?subject=Signalement%20accessibilit%C3%A9"
            className="inline-flex items-center gap-2 text-jolene-rose-800 underline font-medium"
          >
            <Mail className="h-4 w-4" aria-hidden="true" />
            support@jolene.app
          </a>
        </section>
      </main>
      <FooterLegal />
    </div>
  );
}

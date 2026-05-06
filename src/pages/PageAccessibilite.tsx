import { Link } from 'react-router-dom';
import { Accessibility, ArrowLeft, Mail } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { FooterLegal } from '@/components/FooterLegal';

export default function PageAccessibilite() {
  usePageTitle('Déclaration d\'accessibilité');

  return (
    <div className="min-h-screen flex flex-col bg-background">
      <main id="main-content" tabIndex={-1} className="flex-1 max-w-3xl w-full mx-auto px-4 py-8">
        <Link to="/" className="inline-flex items-center gap-1.5 text-sm text-primary hover:underline mb-6">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Retour à l'accueil
        </Link>

        <header className="mb-8">
          <div className="flex items-center gap-3 mb-3">
            <Accessibility className="h-8 w-8 text-primary" aria-hidden="true" />
            <h1 className="text-2xl font-bold text-foreground">Déclaration d'accessibilité</h1>
          </div>
          <p className="text-sm text-muted-foreground">
            Jolene SASU s'engage à rendre son site internet accessible conformément à
            l'article 47 de la loi n° 2005-102 du 11 février 2005.
          </p>
        </header>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">État de conformité</h2>
          <p className="text-sm text-foreground">
            Le site <strong>jolene.app</strong> est <strong>partiellement conforme</strong> au
            référentiel général d'amélioration de l'accessibilité (RGAA) version 4.1, niveau AA.
          </p>
          <p className="text-sm text-muted-foreground">
            Cette déclaration s'applique aux pages publiques (accueil, inscription, connexion,
            centre d'aide, mentions légales, CGU/CGV, blog, tarifs) ainsi qu'aux interfaces
            soignant et établissement après authentification.
          </p>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Méthodologie</h2>
          <p className="text-sm text-foreground">L'évaluation a été réalisée selon les méthodes suivantes :</p>
          <ul className="list-disc list-inside text-sm text-foreground space-y-1.5 ml-2">
            <li>Audit automatisé via <strong>axe-core</strong> intégré dans la suite de tests Playwright (lancé à chaque déploiement)</li>
            <li>Tests manuels au clavier (navigation Tab, raccourcis, focus visible)</li>
            <li>Tests de lisibilité (contraste, taille de police, zoom 200 %)</li>
            <li>Audit manuel des composants critiques (formulaires, modales, notifications)</li>
          </ul>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Mesures mises en œuvre</h2>
          <ul className="list-disc list-inside text-sm text-foreground space-y-1.5 ml-2">
            <li>Lien <em>« Aller au contenu principal »</em> en haut de chaque page (visible au premier <kbd>Tab</kbd>)</li>
            <li>Attribut <code>lang="fr"</code> sur l'élément racine</li>
            <li>Étiquettes (labels) associées à tous les champs de formulaire (<code>htmlFor</code> ou enveloppement)</li>
            <li>Indicateurs de focus visibles (anneau de couleur primaire)</li>
            <li>Notifications avec <code>role="alert"</code> (erreurs) et <code>role="status"</code> (info/succès)</li>
            <li>Boutons icon-only avec <code>aria-label</code> explicite</li>
            <li>Touch targets minimum 44 × 44 pixels (mobile)</li>
            <li>Respect de <code>prefers-reduced-motion</code> pour utilisateurs sensibles aux animations</li>
            <li>Hiérarchie sémantique respectée (<code>&lt;header&gt;</code>, <code>&lt;main&gt;</code>, <code>&lt;footer&gt;</code>, hiérarchie <code>h1</code> → <code>h6</code>)</li>
            <li>Contraste texte/fond ≥ 4,5:1 pour le texte normal, ≥ 3:1 pour le texte large</li>
          </ul>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Non-conformités connues</h2>
          <p className="text-sm text-muted-foreground">
            À la date de cette déclaration, aucune non-conformité bloquante n'est connue.
            Si vous rencontrez une difficulté d'accessibilité, signalez-la (cf. ci-dessous).
          </p>
          <p className="text-xs text-muted-foreground italic">
            Limitations connues : certaines animations tierces (cartographie, graphiques) peuvent
            ne pas respecter intégralement <code>prefers-reduced-motion</code>. Les vidéos de
            tutoriel ne disposent pas encore de sous-titres ; nous travaillons à les ajouter.
          </p>
        </section>

        <section className="card-base mb-6 space-y-3">
          <h2 className="text-lg font-bold text-foreground">Voies de recours</h2>
          <p className="text-sm text-foreground">
            Si vous constatez un défaut d'accessibilité vous empêchant d'accéder à un contenu
            ou à une fonctionnalité, vous pouvez nous le signaler :
          </p>
          <a
            href="mailto:support@jolene.app?subject=Signalement%20accessibilit%C3%A9"
            className="inline-flex items-center gap-2 text-primary hover:underline font-medium"
          >
            <Mail className="h-4 w-4" aria-hidden="true" />
            support@jolene.app
          </a>
          <p className="text-sm text-foreground mt-3">
            Si vous n'obtenez pas de réponse rapide ou satisfaisante, vous pouvez :
          </p>
          <ul className="list-disc list-inside text-sm text-foreground space-y-1.5 ml-2">
            <li>
              Écrire au Défenseur des droits :
              <a href="https://www.defenseurdesdroits.fr/saisir/" target="_blank" rel="noopener noreferrer" className="text-primary underline ml-1 font-medium">
                defenseurdesdroits.fr/saisir
              </a>
            </li>
            <li>
              Contacter le délégué local du Défenseur des droits dans votre département
            </li>
            <li>
              Adresser un courrier postal :<br />
              Défenseur des droits<br />
              Libre réponse 71120<br />
              75342 Paris CEDEX 07
            </li>
          </ul>
        </section>

        <footer className="mt-8 text-xs text-muted-foreground">
          <p>Date d'établissement de la déclaration : 3 mai 2026</p>
          <p>Date de la dernière mise à jour : 3 mai 2026</p>
          <p className="mt-2">
            Liens utiles :
            <a href="https://accessibilite.numerique.gouv.fr/" target="_blank" rel="noopener noreferrer" className="text-primary underline ml-1 font-medium">
              référentiel RGAA
            </a>
            ·
            <a href="https://www.w3.org/Translations/WCAG21-fr/" target="_blank" rel="noopener noreferrer" className="text-primary underline ml-1 font-medium">
              WCAG 2.1
            </a>
          </p>
        </footer>
      </main>
      <FooterLegal />
    </div>
  );
}

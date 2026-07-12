import { usePageTitle } from '@/hooks/usePageTitle';
import LayoutLegal from '@/components/LayoutLegal';
import { ENTREPRISE } from '@/constantes/entreprise';

const TOC = [
  { id: 'intro', label: 'Suppression de votre compte Jolene' },
  { id: 'methode1', label: 'Méthode 1 — Depuis l’application' },
  { id: 'methode2', label: 'Méthode 2 — Par e-mail' },
  { id: 'donnees', label: 'Données supprimées et conservées' },
];

export default function PageSuppressionCompte() {
  usePageTitle('Supprimer mon compte');
  return (
    <LayoutLegal
      titre="Supprimer mon compte"
      dateMaj="12 juillet 2026"
      toc={TOC}
      seoDescription="Comment demander la suppression de votre compte Jolene et des données associées : procédure depuis l'application ou par e-mail, données supprimées et durées de conservation légales."
    >
      <section id="intro">
        <p className="mb-3">
          Cette page explique comment demander la suppression de votre compte <strong className="text-foreground">{ENTREPRISE.nom} (Jolene)</strong> et
          des données personnelles associées, conformément au RGPD.
        </p>
        <p className="mb-3">
          La suppression est <strong className="text-foreground">définitive et irréversible</strong>. Vos données personnelles sont
          anonymisées ; seules les données que la loi nous oblige à conserver sont archivées (voir plus bas).
        </p>
      </section>

      <section id="methode1">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Méthode 1 — Depuis l’application (immédiat)</h2>
        <ol className="list-decimal pl-6 space-y-2 mb-3">
          <li>Connectez-vous à votre compte Jolene.</li>
          <li>Soignant : ouvrez <strong className="text-foreground">Mon compte → Supprimer mon compte</strong>. Établissement : ouvrez <strong className="text-foreground">Mon établissement → Supprimer mon compte</strong>.</li>
          <li>Dans la section <strong className="text-foreground">« Suppression de compte »</strong>, cliquez sur <strong className="text-foreground">« Supprimer mon compte »</strong>.</li>
          <li>Saisissez <strong className="text-foreground">SUPPRIMER</strong> pour confirmer, puis validez.</li>
        </ol>
        <p className="mb-3">
          Votre compte est alors supprimé immédiatement et vous êtes déconnecté. Vous pouvez aussi, avant suppression,
          <strong className="text-foreground"> exporter l’intégralité de vos données</strong> (format JSON ou CSV) depuis cette même section.
        </p>
      </section>

      <section id="methode2">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Méthode 2 — Par e-mail</h2>
        <p className="mb-3">
          Si vous ne pouvez pas accéder à votre compte, adressez votre demande de suppression à&nbsp;:
        </p>
        <div className="bg-muted/50 border border-border rounded-xl p-4 mb-3">
          <p className="font-semibold text-foreground">{ENTREPRISE.nom}</p>
          <p className="text-muted-foreground">E-mail : <a href="mailto:support@jolene.app?subject=Demande%20de%20suppression%20de%20compte" className="text-primary underline">support@jolene.app</a></p>
        </div>
        <p className="mb-3">
          Indiquez l’adresse e-mail associée à votre compte. Après vérification de votre identité, votre compte et vos
          données personnelles sont supprimés sous <strong className="text-foreground">30 jours maximum</strong>.
        </p>
      </section>

      <section id="donnees">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Données supprimées et conservées</h2>
        <p className="mb-3"><strong className="text-foreground">Supprimées / anonymisées immédiatement :</strong></p>
        <ul className="list-disc pl-6 space-y-2 mb-4">
          <li>Données d’identification (nom, prénom, e-mail, téléphone, adresse)</li>
          <li>Identifiants professionnels (RPPS / ADELI), qui sont également libérés et réutilisables</li>
          <li>Photo de profil et préférences de compte</li>
          <li>Coordonnées bancaires (IBAN) et identifiants de connexion</li>
        </ul>
        <p className="mb-3">
          <strong className="text-foreground">Conservées (obligation légale, sous forme archivée / anonymisée lorsque possible) :</strong>
        </p>
        <ul className="list-disc pl-6 space-y-2 mb-4">
          <li>Documents comptables et factures : conservés <strong className="text-foreground">10 ans</strong> (article L123-22 du Code de commerce)</li>
          <li>Contrats et bulletins de paie : durées légales applicables</li>
          <li>Journaux d’audit concernés par la preuve ou la sécurité : jusqu’à <strong className="text-foreground">5 ans</strong> selon la catégorie</li>
          <li>Données d’identification archivées : jusqu’à <strong className="text-foreground">3 ans</strong> après la suppression</li>
        </ul>
        <p className="text-sm text-muted-foreground">
          Le détail complet des durées de conservation figure dans notre <a href="/confidentialite" className="text-primary underline">Politique de confidentialité</a>.
          Pour toute question relative à vos données, contactez notre référent confidentialité à <a href="mailto:support@jolene.app" className="text-primary underline">support@jolene.app</a>.
        </p>
      </section>
    </LayoutLegal>
  );
}

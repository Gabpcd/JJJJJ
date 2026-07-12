import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';
import { ENTREPRISE } from '@/constantes/entreprise';

const TOC = [
  { id: 'art1', label: 'Article 1 — Responsable du traitement' },
  { id: 'art2', label: 'Article 2 — Données collectées' },
  { id: 'art3', label: 'Article 3 — Hébergement sécurisé' },
  { id: 'art4', label: "Article 4 — Journaux d'audit" },
  { id: 'art5', label: 'Article 5 — Durées de conservation' },
  { id: 'art6', label: 'Article 6 — Droits des personnes' },
];

export default function PageConfidentialite() {
  usePageTitle('Confidentialité');
  return (
    <LayoutLegal
      titre="Politique de Confidentialité"
      dateMaj="12 juillet 2026"
      toc={TOC}
      seoDescription="Politique de confidentialité de Jolene : données collectées, sous-traitants, durées de conservation et exercice de vos droits RGPD."
    >
      {/* Article 1 */}
      <section id="art1">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 1 — Responsable du traitement</h2>
        <p className="mb-3">Le responsable du traitement des données à caractère personnel collectées via la Plateforme Jolene est :</p>
        <div className="bg-muted/50 border border-border rounded-xl p-4 mb-3">
          <p className="font-semibold text-foreground">{ENTREPRISE.nom}</p>
          <p className="text-muted-foreground">SIRET : {ENTREPRISE.siret}</p>
          <p className="text-muted-foreground">Siège social : {ENTREPRISE.adresse}</p>
          <p className="text-muted-foreground">E-mail : {ENTREPRISE.email}</p>
          <p className="text-muted-foreground mt-2">Contact protection des données : <a href="mailto:support@jolene.app" className="text-primary underline">support@jolene.app</a></p>
        </div>
        <p>Le traitement des données est réalisé conformément au Règlement (UE) 2016/679 du 27 avril 2016 (RGPD) et à la loi n° 78-17 du 6 janvier 1978 modifiée (loi Informatique et Libertés).</p>
      </section>

      {/* Article 2 */}
      <section id="art2">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 2 — Données collectées</h2>
        <p className="mb-4">La Plateforme collecte les catégories de données suivantes, selon le profil de l'utilisateur :</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.1 — Données d'identification</h3>
        <p className="mb-3">Nom, prénom, date de naissance, adresse e-mail, numéro de téléphone, adresse postale, photo de profil (facultative). Pour les Soignants : numéro RPPS, numéro ADELI, numéro de sécurité sociale, profession.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.2 — Données professionnelles</h3>
        <p className="mb-3">Diplômes, habilitations, attestation RCP, statut (salarié/libéral), numéro SIRET le cas échéant, historique des missions réalisées, score de fiabilité et heures cumulées. Les déclarations relatives aux vaccinations obligatoires et à la médecine du travail, ainsi que leur date de signature, sont également enregistrées. Elles peuvent révéler des informations liées à la santé et bénéficient d'un accès restreint.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.3 — Données de géolocalisation</h3>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p>Les coordonnées GPS ne sont demandées que lors d'une action explicite : <strong>au pointage d'arrivée ou de départ</strong>, ou lorsque l'utilisateur choisit « me localiser » pour renseigner son profil ou l'adresse de son établissement. Il n'y a <strong>aucun suivi continu ou en arrière-plan</strong>. Le refus n'empêche pas le pointage par QR code ou code fourni par l'établissement, ni la saisie manuelle d'une ville ou d'une adresse. Les métadonnées de pointage peuvent comprendre la latitude, la longitude, la précision du signal et un identifiant technique du terminal.</p>
        </div>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.4 — Données financières</h3>
        <p className="mb-3">Coordonnées bancaires (IBAN) des Soignants pour le versement des rémunérations. Données de facturation des Établissements. Les données de carte bancaire sont traitées exclusivement par Stripe (certifié PCI-DSS niveau 1) et ne sont jamais stockées sur nos serveurs.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.5 — Données de connexion</h3>
        <p>Adresse IP, type et version du navigateur, système d'exploitation, date et heure de connexion et contexte technique d'erreur. Selon les fonctionnalités utilisées, des événements de navigation limités peuvent également être produits à des fins de sécurité, de diagnostic et d'amélioration du service.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">2.6 — Finalités et bases juridiques</h3>
        <ul className="list-disc pl-6 space-y-2">
          <li>Création du compte, mise en relation, candidatures, missions, contrats et paiements : exécution du contrat ou mesures précontractuelles (article 6.1.b du RGPD).</li>
          <li>Facturation, obligations sociales, fiscales et demandes des autorités : obligation légale (article 6.1.c).</li>
          <li>Sécurité, prévention de la fraude, preuve des opérations, modération et amélioration du service : intérêt légitime de Jolene et des utilisateurs (article 6.1.f), mis en balance avec leurs droits.</li>
          <li>Géolocalisation au pointage, localisation volontaire du profil ou de l'adresse, et communications facultatives : consentement lorsque celui-ci est requis (article 6.1.a), retirable pour l'avenir depuis les réglages concernés.</li>
          <li>Les déclarations professionnelles susceptibles de révéler une information liée à la santé ne sont traitées que pour la conformité d'exercice et dans le cadre d'une exception applicable de l'article 9.2 du RGPD. Les justificatifs médicaux originaux ne sont pas téléversés sur Jolene.</li>
        </ul>
      </section>

      {/* Article 3 */}
      <section id="art3">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 3 — Hébergement sécurisé</h2>
        <p className="mb-3">La base de données et le stockage principal sont fournis par Supabase. Les données sont protégées en transit et au repos conformément à la configuration du projet et aux garanties contractuelles applicables.</p>
        <div className="bg-muted/50 border border-border rounded-xl p-4 mb-3">
          <p className="font-semibold text-foreground">Supabase Inc.</p>
          <p className="text-muted-foreground">Finalité : authentification, base de données, fonctions serveur et stockage de fichiers</p>
          <p className="text-muted-foreground">Localisation et garanties : précisées dans le registre des sous-traitants et les documents contractuels en vigueur</p>
        </div>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p><strong>Informations liées à la santé :</strong> Jolene ne demande pas le dossier médical des Soignants. La Plateforme conserve néanmoins leurs déclarations relatives aux vaccinations obligatoires et à la médecine du travail, ainsi que la date de signature. Ces informations sont traitées comme sensibles et limitées aux finalités de conformité professionnelle.</p>
        </div>
        <p className="mb-3">Les localisations, mécanismes de sauvegarde et mesures de sécurité applicables sont suivis dans le registre interne des sous-traitants et la documentation de continuité. Ils sont revus lors de tout changement de fournisseur ou de région.</p>
        <p className="mb-3">Les transferts de données hors UE, s'ils devaient avoir lieu dans le cadre de prestations techniques de sous-traitants, sont encadrés par des clauses contractuelles types approuvées par la Commission européenne (décision 2021/914).</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">3.2 — Sous-traitants et processeurs de données</h3>
        <p className="mb-3">Les données personnelles peuvent être transmises aux sous-traitants suivants, dans le strict cadre de leurs prestations :</p>
        <div className="overflow-x-auto mb-3">
          <table className="w-full text-sm border border-border rounded-xl overflow-hidden">
            <thead><tr className="bg-muted/50"><th className="px-4 py-2 text-left font-semibold text-foreground">Sous-traitant</th><th className="px-4 py-2 text-left font-semibold text-foreground">Finalité</th><th className="px-4 py-2 text-left font-semibold text-foreground">Données concernées</th><th className="px-4 py-2 text-left font-semibold text-foreground">Localisation</th></tr></thead>
            <tbody className="divide-y divide-border">
              <tr><td className="px-4 py-2 text-foreground">Supabase Inc.</td><td className="px-4 py-2 text-muted-foreground">Hébergement, base de données, stockage</td><td className="px-4 py-2 text-muted-foreground">Données du compte et du service</td><td className="px-4 py-2 text-muted-foreground">Région du projet et garanties consignées au registre des sous-traitants</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Stripe</td><td className="px-4 py-2 text-muted-foreground">Paiements, SEPA, Connect</td><td className="px-4 py-2 text-muted-foreground">IBAN, identité, facturation</td><td className="px-4 py-2 text-muted-foreground">EEE et pays tiers encadrés selon le service</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Anthropic PBC</td><td className="px-4 py-2 text-muted-foreground">Vérification IA de documents</td><td className="px-4 py-2 text-muted-foreground">Documents téléversés et données nécessaires à leur rapprochement</td><td className="px-4 py-2 text-muted-foreground">Selon configuration et garanties contractuelles en vigueur</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Twilio Inc.</td><td className="px-4 py-2 text-muted-foreground">Envoi de SMS</td><td className="px-4 py-2 text-muted-foreground">Numéro de téléphone, contenu SMS</td><td className="px-4 py-2 text-muted-foreground">Selon configuration et garanties contractuelles en vigueur</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Resend Inc.</td><td className="px-4 py-2 text-muted-foreground">Envoi d'emails transactionnels</td><td className="px-4 py-2 text-muted-foreground">Adresse email, contenu email</td><td className="px-4 py-2 text-muted-foreground">Selon configuration et garanties contractuelles en vigueur</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Sentry</td><td className="px-4 py-2 text-muted-foreground">Diagnostic d'erreurs et stabilité</td><td className="px-4 py-2 text-muted-foreground">Identifiant technique, contexte d'erreur et appareil</td><td className="px-4 py-2 text-muted-foreground">Selon configuration contractuelle</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Cloudflare</td><td className="px-4 py-2 text-muted-foreground">Protection anti-abus Turnstile</td><td className="px-4 py-2 text-muted-foreground">Données techniques de connexion et de navigateur</td><td className="px-4 py-2 text-muted-foreground">Réseau mondial</td></tr>
              <tr><td className="px-4 py-2 text-foreground">Apple Push Notification Service / Google Firebase Cloud Messaging</td><td className="px-4 py-2 text-muted-foreground">Notifications push mobiles</td><td className="px-4 py-2 text-muted-foreground">Jeton de l'appareil et contenu de notification</td><td className="px-4 py-2 text-muted-foreground">Selon le système mobile et les garanties du service</td></tr>
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted-foreground italic">SCC = Standard Contractual Clauses (clauses contractuelles types, décision 2021/914). Les conditions de traitement, de conservation et de transfert applicables sont celles du contrat et de la configuration en vigueur pour chaque prestataire ; le registre interne fait foi en cas d'évolution.</p>
      </section>

      {/* Article 4 */}
      <section id="art4">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 4 — Journaux d'audit</h2>
        <p className="mb-3">La Plateforme journalise les événements de sécurité et certaines opérations métier critiques, notamment :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>Connexion et déconnexion des utilisateurs (date, heure, IP, navigateur)</li>
          <li>Certaines consultations sensibles, créations, modifications et suppressions de données</li>
          <li>Téléversement et vérification de documents</li>
          <li>Signature électronique de contrats</li>
          <li>Opérations de pointage (avec coordonnées GPS lorsqu'elles ont été fournies)</li>
          <li>Opérations de facturation et de paiement</li>
        </ul>
        <p className="mb-3">Les journaux d'audit concernés par la preuve contractuelle ou la sécurité sont conservés jusqu'à 5 ans selon la catégorie. Leur accès est limité aux administrateurs habilités et ils peuvent être communiqués aux autorités sur demande légalement fondée.</p>
        <p>Les journaux ne contiennent pas de données de santé des patients. Seules les métadonnées administratives (qui a fait quoi, quand, depuis où) sont enregistrées.</p>
      </section>

      {/* Article 5 */}
      <section id="art5">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 5 — Durées de conservation</h2>
        <p className="mb-4">Les données personnelles sont conservées pendant les durées suivantes :</p>

        <div className="overflow-x-auto mb-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="bg-primary text-primary-foreground">
                <th scope="col" className="px-4 py-3 text-left font-semibold rounded-tl-xl">Catégorie de données</th>
                <th scope="col" className="px-4 py-3 text-left font-semibold">Durée active</th>
                <th scope="col" className="px-4 py-3 text-left font-semibold rounded-tr-xl">Archivage</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Données d'identification</td>
                <td className="px-4 py-3">Durée du compte</td>
                <td className="px-4 py-3">3 ans après suppression</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Documents professionnels</td>
                <td className="px-4 py-3">Durée de validité</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Données de géolocalisation (pointage)</td>
                <td className="px-4 py-3">Jusqu'à 90 jours après le pointage</td>
                <td className="px-4 py-3">Coordonnées supprimées ; la présence non géolocalisée peut être conservée comme preuve contractuelle</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Ville du profil / coordonnées de l'adresse d'établissement</td>
                <td className="px-4 py-3">Tant que le profil ou l'adresse est actif</td>
                <td className="px-4 py-3">Modifiables ou supprimées avec le profil, sous réserve des obligations légales applicables</td>
              </tr>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Contrats de mission</td>
                <td className="px-4 py-3">Durée de la mission</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Factures</td>
                <td className="px-4 py-3">Année fiscale</td>
                <td className="px-4 py-3">10 ans (obligation fiscale)</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Journaux d'audit</td>
                <td className="px-4 py-3">—</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="bg-card">
                <td className="px-4 py-3 rounded-bl-xl">Données de connexion</td>
                <td className="px-4 py-3">—</td>
                <td className="px-4 py-3 rounded-br-xl">1 an</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p>À l'expiration des durées de conservation, les données sont supprimées de manière irréversible ou anonymisées de façon à rendre toute identification impossible.</p>
      </section>

      {/* Article 6 */}
      <section id="art6">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 6 — Droits des personnes</h2>
        <p className="mb-4">Conformément au RGPD (articles 15 à 22), vous disposez des droits suivants sur vos données personnelles :</p>
        <ul className="list-disc pl-6 space-y-3 mb-4">
          <li><strong>Droit d'accès</strong> (article 15) : obtenir la confirmation que des données vous concernant sont traitées et en recevoir une copie.</li>
          <li><strong>Droit de rectification</strong> (article 16) : demander la correction de données inexactes ou incomplètes.</li>
          <li><strong>Droit à l'effacement</strong> (article 17) : demander la suppression de vos données, sous réserve des obligations légales de conservation. Le processus supprime ou anonymise le profil, révoque les accès et traite les fichiers associés. Les données comptables devant être conservées restent archivées avec un accès restreint pendant la durée légale.</li>
          <li><strong>Droit à la limitation du traitement</strong> (article 18) : demander la suspension du traitement de vos données dans certains cas.</li>
          <li><strong>Droit à la portabilité</strong> (article 20) : recevoir vos données dans un format structuré, couramment utilisé et lisible par machine (JSON ou CSV).</li>
          <li><strong>Droit d'opposition</strong> (article 21) : vous opposer au traitement de vos données pour des motifs légitimes.</li>
          <li><strong>Droit de ne pas faire l'objet d'une décision automatisée</strong> (article 22) : la vérification de documents par intelligence artificielle n'entraîne aucune décision automatisée sans possibilité de recours. En cas de rejet automatique d'un document, vous pouvez demander une revue manuelle à tout moment.</li>
        </ul>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">6.2 — Traitement par intelligence artificielle</h3>
        <p className="mb-3">Certains documents téléversés (pièce d'identité, diplômes, attestations RCP) sont analysés par un système d'intelligence artificielle (Anthropic Claude) pour vérifier leur lisibilité, leur cohérence et les indices d'authenticité. Ils sont transmis via une connexion chiffrée. Une voie de revue humaine est proposée lorsqu'un verdict automatique est contesté.</p>

        <p className="mb-3">Pour exercer vos droits, adressez votre demande à : <a href="mailto:support@jolene.app" className="text-primary underline font-medium">support@jolene.app</a></p>
        <p className="mb-3">L'Éditeur s'engage à répondre dans un délai d'un mois. Ce délai peut être prolongé de deux mois en cas de complexité ou de nombre élevé de demandes.</p>
        <p>En cas de difficulté dans l'exercice de vos droits, vous pouvez introduire une réclamation auprès de la Commission Nationale de l'Informatique et des Libertés (CNIL) : <a href="https://www.cnil.fr" target="_blank" rel="noopener noreferrer" className="text-primary underline font-medium">www.cnil.fr</a></p>
      </section>
    </LayoutLegal>
  );
}

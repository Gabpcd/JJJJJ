import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';

const TOC = [
  { id: 'art1', label: 'Article 1 — Définitions' },
  { id: 'art2', label: 'Article 2 — Objet' },
  { id: 'art3', label: 'Article 3 — Inscription et vérification' },
  { id: 'art4', label: 'Article 4 — Fonctionnement de la Plateforme' },
  { id: 'art5', label: 'Article 5 — Exclusion de responsabilité' },
  { id: 'art6', label: 'Article 6 — Propriété intellectuelle' },
  { id: 'art7', label: 'Article 7 — Score de fiabilité et parcours 3 200 heures' },
  { id: 'art8', label: 'Article 8 — Résiliation' },
  { id: 'art9', label: 'Article 9 — Droit applicable' },
];

export default function PageCGU() {
  usePageTitle('CGU');
  return (
    <LayoutLegal
      titre="Conditions Générales d'Utilisation"
      dateMaj="14 juillet 2026"
      toc={TOC}
      seoDescription="Conditions Générales d'Utilisation de Jolene, plateforme de staffing médical. Inscription, vérification, pointage, score de fiabilité et résiliation."
    >
      {/* Article 1 */}
      <section id="art1">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 1 — Définitions</h2>
        <p className="mb-3">Dans les présentes Conditions Générales d'Utilisation (ci-après « CGU »), les termes suivants ont la signification qui leur est attribuée ci-dessous :</p>
        <ul className="list-disc pl-6 space-y-2">
          <li><strong>« Plateforme »</strong> : le site web et l'application mobile Jolene, édités par Jolene SASU, permettant la mise en relation entre Établissements de santé et Soignants pour des missions de remplacement paramédical.</li>
          <li><strong>« Éditeur »</strong> : Jolene SASU, société par actions simplifiée, dont le siège social est situé à Paris (75006).</li>
          <li><strong>« Soignant »</strong> : tout professionnel de santé ou du secteur médico-social dont la profession est proposée sur la Plateforme, inscrit à titre personnel.</li>
          <li><strong>« Établissement »</strong> : tout établissement de santé public ou privé (hôpital, clinique, EHPAD, centre de soins) inscrit sur la Plateforme en vue de publier des missions.</li>
          <li><strong>« Mission »</strong> : une offre de travail temporaire publiée par un Établissement et pouvant être acceptée par un Soignant via la Plateforme.</li>
          <li><strong>« Contrat de mission »</strong> : le contrat auto-généré par la Plateforme, signé électroniquement par le Soignant et l'Établissement avant le début de la Mission.</li>
          <li><strong>« Score de fiabilité »</strong> : indicateur composite calculé par la Plateforme, reflétant la ponctualité, la complétude documentaire et la fiabilité globale d'un Soignant.</li>
        </ul>
      </section>

      {/* Article 2 */}
      <section id="art2">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 2 — Objet</h2>
        <p className="mb-3">Les présentes CGU ont pour objet de définir les conditions d'accès et d'utilisation de la Plateforme Jolene par les Soignants et les Établissements.</p>
        <p className="mb-3">La Plateforme constitue un outil technique de mise en relation facilitant la conclusion de contrats de mission entre Établissements et Soignants. Elle automatise la gestion administrative (contrats, pointage, facturation) pour le compte des parties.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground">Clause essentielle :</p>
          <p>L'Éditeur n'est en aucun cas employeur, co-employeur ou mandataire social des Soignants. La Plateforme n'est pas une agence de travail temporaire au sens des articles L.1251-1 et suivants du Code du travail. Jolene agit exclusivement en qualité d'intermédiaire technique de mise en relation.</p>
        </div>
        <p>Le contrat de travail ou de prestation est conclu directement entre l'Établissement et le Soignant. L'Éditeur ne participe ni à la subordination juridique, ni à la direction des soins, ni à l'évaluation clinique des Soignants.</p>
      </section>

      {/* Article 3 */}
      <section id="art3">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 3 — Inscription et vérification</h2>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">3.1 — Inscription</h3>
        <p className="mb-3">L'inscription sur la Plateforme est gratuite pour les Soignants. Elle requiert la fourniture d'informations exactes et à jour : nom, prénom, adresse e-mail, numéro de téléphone, profession, et numéro RPPS ou ADELI le cas échéant.</p>
        <p className="mb-3">Les Établissements s'inscrivent en renseignant leur raison sociale, numéro SIRET, numéro FINESS, adresse et coordonnées du contact principal.</p>
        <p>Toute inscription implique l'acceptation sans réserve des présentes CGU.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">3.2 — Vérification des Soignants</h3>
        <p className="mb-3">Avant toute première mission, chaque Soignant fait l'objet d'une vérification :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li><strong>Vérification RPPS automatique</strong> : le numéro RPPS est vérifié en temps réel via l'API officielle de l'Annuaire Santé (annuaire.sante.fr). La Plateforme compare le nom, le prénom et la profession déclarés avec les données du répertoire.</li>
          <li><strong>Documents obligatoires</strong> : le Soignant doit téléverser les documents requis pour sa profession et pour le contrat de la mission (pièce d'identité, diplôme, identifiant professionnel lorsqu'il existe et, pour le libéral, attestation d'assurance RCP). Les documents font l'objet d'une vérification manuelle ou automatisée avant l'attribution.</li>
          <li><strong>Vérification automatisée par intelligence artificielle</strong> : certains documents téléversés (pièce d'identité, diplômes, attestations) peuvent être analysés par un système d'intelligence artificielle (IA) fourni par un prestataire tiers (Anthropic Claude). Cette analyse vise à vérifier l'authenticité, la lisibilité et la concordance des informations avec les données déclarées. Aucune décision automatisée n'est prise sans possibilité de recours : en cas de rejet automatique, le Soignant peut demander une revue manuelle par l'équipe Jolene. Les documents sont transmis de manière chiffrée ; les conditions de traitement et de conservation applicables sont celles du contrat et de la configuration en vigueur avec le prestataire.</li>
          <li><strong>Vérification d'identité</strong> : l'Éditeur se réserve le droit de demander une vérification d'identité complémentaire (vidéo, selfie avec pièce d'identité) en cas de doute.</li>
        </ul>
        <p>Un dossier documentaire incomplet peut permettre au Soignant de candidater à certaines Missions salariées lorsque les informations minimales requises sont vérifiées. En revanche, aucune affectation définitive ni aucun démarrage de Mission ne sont possibles tant que toutes les preuves exigées pour la profession et le régime de la Mission ne sont pas vérifiées et en cours de validité.</p>
      </section>

      {/* Article 4 */}
      <section id="art4">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 4 — Fonctionnement de la Plateforme</h2>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.1 — Publication et acceptation de missions</h3>
        <p className="mb-3">L'Établissement publie des missions en précisant les dates, horaires, service, profession requise et taux horaire. Les missions peuvent être publiées unitairement ou en série (récurrence). Les Soignants éligibles reçoivent une notification et peuvent postuler. L'Établissement sélectionne le Soignant de son choix.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.2 — Contrat de mission</h3>
        <p className="mb-3">Une fois la mission acceptée par les deux parties, un contrat de mission est automatiquement généré par la Plateforme. Ce contrat reprend les éléments essentiels : identité des parties, dates, horaires, taux horaire, conditions de la mission.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p>La signature électronique du contrat par les deux parties est <strong>obligatoire avant tout pointage</strong>. Aucun soignant ne peut débuter une mission sans contrat signé.</p>
        </div>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.3 — Moteur de conformité au droit du travail</h3>
        <p className="mb-3">La Plateforme intègre un moteur de conformité automatique qui vérifie en temps réel le respect des dispositions légales suivantes :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li><strong>Repos quotidien de 11 heures</strong> (article L.3131-1 du Code du travail) : la Plateforme bloque toute mission qui ne respecterait pas un repos minimum de 11 heures consécutives entre deux missions.</li>
          <li><strong>Plafond hebdomadaire de 48 heures</strong> (article L.3121-20 du Code du travail) : la Plateforme empêche l'acceptation d'une mission qui porterait le total hebdomadaire au-delà de 48 heures de travail effectif.</li>
          <li><strong>Plafond Rist</strong> : pour les missions en établissement public, la Plateforme vérifie que le taux horaire proposé respecte les plafonds réglementaires applicables (décret n° 2017-1605 du 24 novembre 2017, modifié).</li>
        </ul>
        <p>L'Établissement et le Soignant sont informés par notification en cas de blocage. Des dérogations peuvent être accordées dans les cas prévus par la loi (urgence sanitaire, article L.3131-15 du CSP).</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.4 — Pointage et géolocalisation</h3>
        <p className="mb-3">Le pointage (arrivée et départ) s'effectue via l'application mobile. La Plateforme demande les coordonnées GPS au moment du pointage lorsque le Soignant l'autorise. Une localisation peut aussi être demandée si l'utilisateur choisit volontairement « me localiser » pour renseigner son profil ou l'adresse de son établissement. Il n'y a aucun suivi continu ni en arrière-plan.</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li><strong>Périmètre GPS</strong> : pour le pointage GPS, la distance maximale autour de l'adresse de l'Établissement est configurée selon le site (notamment 100, 200 ou 500 mètres). Le QR code ou le code de secours permet de pointer sans fournir de position.</li>
          <li><strong>Anti-téléportation</strong> : un algorithme détecte les incohérences de déplacement (distance physiquement impossible entre deux pointages successifs) et déclenche une alerte pour vérification manuelle.</li>
          <li><strong>Données GPS</strong> : les coordonnées brutes de pointage sont supprimées au plus tard 90 jours après le pointage. La présence, sans coordonnées, peut être conservée comme preuve contractuelle selon les durées applicables.</li>
        </ul>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.5 — Déclaration Préalable à l'Embauche (DPAE)</h3>
        <p className="mb-3">Pour toute mission salariée (CDD), la Déclaration Préalable à l'Embauche prévue aux articles L.1221-10 et R.1221-2 du Code du travail doit être effectuée auprès de l'URSSAF avant la prise de poste du Soignant.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground mb-2">Clause essentielle DPAE :</p>
          <p>L'Établissement, en sa qualité d'employeur légal du Soignant, demeure seul responsable de la déclaration de la DPAE auprès de l'URSSAF. Jolene n'est ni employeur, ni tiers-déclarant URSSAF agréé : la Plateforme ne transmet aucune DPAE pour le compte de l'Établissement.</p>
        </div>
        <p className="mb-3">À titre d'assistance technique, la Plateforme génère un brouillon de DPAE pré-rempli (identité du Soignant, SIRET de l'Établissement, dates et horaires de la mission) que l'Établissement peut copier sur le portail officiel <a href="https://www.net-entreprises.fr" target="_blank" rel="noopener noreferrer" className="underline text-primary">net-entreprises.fr</a>. L'Établissement reste libre de saisir directement sa DPAE par tout autre moyen autorisé.</p>
        <p>L'Établissement est invité à saisir, dans la Plateforme, le numéro de récépissé URSSAF retourné par Net-Entreprises afin de bénéficier d'une traçabilité interne. Le Soignant reçoit alors un email de confirmation contenant ce numéro. L'absence de saisie du numéro dans la Plateforme n'a aucun effet sur la validité juridique de la DPAE, qui relève exclusivement de l'Établissement.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">4.6 — Paiement rapide ⚡</h3>
        <p>Pour une mission affichée comme éligible au paiement rapide, le paiement est préparé via Stripe Connect avant son exécution. Après la fin prévue de la mission et la validation des présences, <strong>Jolene donne normalement l'instruction de versement des honoraires sous 24 à 72 heures</strong>. Ce délai concerne l'instruction donnée au prestataire de paiement et non l'arrivée bancaire effective. Il est suspendu en cas de litige, présence non validée, annulation, suspicion de fraude, contrôle réglementaire, échec ou remboursement du paiement de l'Établissement, compte de paiement incomplet ou indisponible, ou indisponibilité du prestataire de paiement. En l'absence de contestation, les présences peuvent être validées automatiquement après 72 heures. En cas d'annulation avant le début, les fonds débités sont restitués selon l'état réel du paiement.</p>
      </section>

      {/* Article 5 */}
      <section id="art5">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 5 — Exclusion de responsabilité</h2>
        <div className="bg-muted/50 border-l-4 border-destructive p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground mb-2">Clause limitative de responsabilité :</p>
          <p>Jolene agit exclusivement en qualité d'intermédiaire technique de mise en relation. L'Éditeur n'est pas responsable :</p>
        </div>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>De la qualité, de la sécurité ou de l'adéquation des soins prodigués par les Soignants au sein des Établissements.</li>
          <li>Des actes, omissions, négligences ou fautes commis par les Soignants dans l'exercice de leurs fonctions.</li>
          <li>Des conditions de travail, d'hygiène ou de sécurité au sein des Établissements.</li>
          <li>Des litiges nés de l'exécution du contrat de mission entre le Soignant et l'Établissement.</li>
          <li>Des dommages indirects, pertes de données, manques à gagner ou préjudices consécutifs liés à l'utilisation de la Plateforme.</li>
        </ul>
        <p className="mb-3">Conformément à l'article L.1142-1 du Code de la santé publique (CSP), la responsabilité des actes de soins incombe au professionnel de santé qui les dispense et à l'établissement au sein duquel ils sont pratiqués.</p>
        <p>L'Éditeur s'engage à mettre en œuvre les moyens techniques raisonnables pour assurer la disponibilité et la sécurité de la Plateforme, sans obligation de résultat.</p>
      </section>

      {/* Article 6 */}
      <section id="art6">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 6 — Propriété intellectuelle</h2>
        <p className="mb-3">L'ensemble des éléments constitutifs de la Plateforme (textes, graphismes, logiciels, bases de données, marques, logos, algorithmes) est la propriété exclusive de Jolene SASU ou de ses concédants de licence.</p>
        <p className="mb-3">La marque « Jolene » est déposée auprès de l'Institut National de la Propriété Industrielle (INPI) sous le numéro 5186614. Toute reproduction, représentation ou exploitation non autorisée constituerait une contrefaçon sanctionnée par les articles L.335-2 et suivants du Code de la propriété intellectuelle.</p>
        <p>Les utilisateurs s'interdisent de copier, extraire, décompiler ou procéder à toute ingénierie inverse de la Plateforme.</p>
      </section>

      {/* Article 7 */}
      <section id="art7">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 7 — Score de fiabilité et parcours 3 200 heures</h2>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">7.1 — Score de fiabilité</h3>
        <p className="mb-3">Chaque Soignant dispose d'un score de fiabilité (0 à 100) calculé automatiquement par la Plateforme selon les critères suivants :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>Ponctualité aux pointages (arrivée et départ)</li>
          <li>Complétude et validité des documents obligatoires</li>
          <li>Nombre de missions réalisées sans incident</li>
          <li>Absence d'annulations tardives (moins de 48 heures avant le début de la mission)</li>
        </ul>
        <p className="mb-3">Le score est indicatif et ne constitue pas une notation au sens du droit du travail. Il est visible par le Soignant et par les Établissements consultants son profil.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">7.2 — Parcours 3 200 heures et passage en libéral</h3>
        <p className="mb-3">Les Soignants ayant cumulé au moins 3 200 heures de missions (sur la Plateforme et/ou justifiées par des attestations d'employeurs antérieurs) peuvent initier une demande de passage en exercice libéral via le programme « Accompagnement vers l'exercice libéral ».</p>
        <p>Ce programme propose un accompagnement administratif (guide personnalisé, outils partenaires) et une prise en charge partielle des frais d'installation, selon les conditions définies dans les CGV.</p>
      </section>

      {/* Article 8 */}
      <section id="art8">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 8 — Résiliation</h2>
        <p className="mb-3">Tout utilisateur peut résilier son compte à tout moment depuis son espace personnel ou par demande adressée à support@jolene.app.</p>
        <p className="mb-3">La résiliation prend effet immédiatement, sous réserve de l'achèvement des missions en cours et du règlement des sommes dues.</p>
        <p className="mb-3">L'Éditeur se réserve le droit de suspendre ou supprimer un compte en cas de :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>Non-respect des présentes CGU</li>
          <li>Fourniture d'informations fausses ou frauduleuses</li>
          <li>Utilisation abusive de la Plateforme (fraude au pointage, usurpation d'identité)</li>
          <li>Score de fiabilité durablement inférieur à 30/100</li>
        </ul>
        <p>En cas de suppression pour motif légitime, le Soignant ou l'Établissement est informé par e-mail avec un préavis de 15 jours, sauf urgence (fraude avérée).</p>
      </section>

      {/* Article 9 */}
      <section id="art9">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 9 — Droit applicable</h2>
        <p className="mb-3">Les présentes CGU sont régies par le droit français.</p>
        <p className="mb-3">En cas de litige, les parties s'engagent à rechercher une solution amiable dans un délai de 30 jours. À défaut de résolution amiable, le litige sera porté devant les tribunaux compétents de Paris.</p>
        <p className="mb-3">Conformément aux articles L.611-1 et R.612-1 du Code de la consommation, les Soignants agissant en qualité de consommateurs peuvent recourir gratuitement au service de médiation de la consommation.</p>
        <p>Si une clause des présentes CGU est déclarée nulle ou inapplicable, les autres clauses demeurent en vigueur.</p>
      </section>
    </LayoutLegal>
  );
}

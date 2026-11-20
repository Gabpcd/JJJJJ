/**
 * Guides (`/guides/<slug>`) : contenus éditoriaux pour les soignants et les établissements.
 *
 * Règles de rédaction (docs/SEO_STRATEGIE_ACQUISITION.md §5) :
 *  - vouvoiement, ton sobre ;
 *  - aucune promesse de volume ni de délai ;
 *  - aucun chiffre sans source publique nommée (les chiffres BMO et FINESS sont ajoutés
 *    par `seo-routes` à partir des fichiers de données, avec leur source) ;
 *  - aucune règle de droit affirmée par Jolene : sur le cumul d'activités, l'intérim ou
 *    les formalités d'embauche, le guide renvoie vers la fiche officielle (`sources`) ;
 *  - les affirmations sur le produit sont celles déjà publiées sur le site ;
 *  - le mot « intérim » n'apparaît que dans les guides listés dans `GUIDES_CITANT_INTERIM`,
 *    qui rappellent tous que Jolene n'est pas une agence d'intérim.
 * Module pur (aucun import React/DOM).
 */
import type { QuestionSEO, SectionSEO, SourceSEO } from './types';

export type PublicGuide = 'soignant' | 'etablissement';

/** Chiffres publics qu'un guide demande à `seo-routes` d'insérer, avec leur source. */
export type ChiffreGuide = 'bmo-as-national' | 'finess-ehpad-national';

export interface GuideSEO {
  slug: string;
  public: PublicGuide;
  /** H1. */
  titre: string;
  title: string;
  description: string;
  /** Date de dernière révision (AAAA-MM-JJ) : affichée, et `lastmod` du sitemap. */
  maj: string;
  /** Paragraphes d'ouverture. */
  resume: string[];
  sections: SectionSEO[];
  /** Section « En chiffres » ajoutée après la première section. */
  chiffres?: ChiffreGuide[];
  faq: QuestionSEO[];
  /** Pages liées en fin de guide (chemins internes). */
  liens: { href: string; label: string }[];
}

const FICHE_CUMUL_PUBLIC: SourceSEO = { href: 'https://www.service-public.gouv.fr/particuliers/vosdroits/F1648', label: 'Service-Public.fr : un agent public peut-il cumuler son emploi avec une activité privée ?' };
const FICHE_CUMUL_PRIVE: SourceSEO = { href: 'https://www.service-public.gouv.fr/particuliers/vosdroits/F1945', label: 'Service-Public.fr : à quelles conditions un salarié peut-il cumuler plusieurs emplois ?' };
const FICHE_INTERIM: SourceSEO = { href: 'https://www.service-public.gouv.fr/particuliers/vosdroits/F11215', label: 'Service-Public.fr : contrat de travail temporaire (d’intérim)' };
const FICHE_EMBAUCHE: SourceSEO = { href: 'https://entreprendre.service-public.gouv.fr/vosdroits/F23107', label: 'Service-Public.fr : procédure et formalités d’embauche d’un salarié du secteur privé' };

/** Phrase commune : rappelle ce qu'est Jolene partout où l'intérim est cité. */
export const RAPPEL_PAS_INTERIM = 'Jolene n’est pas une agence d’intérim : le contrat est signé directement entre l’établissement et le soignant.';

export const GUIDES_SEO: GuideSEO[] = [
  {
    slug: 'vacations-etablissement-de-sante',
    public: 'soignant',
    titre: 'Vacations en établissement de santé : où en trouver et comment s’y préparer',
    title: 'Vacations en établissement de santé : où en trouver | Jolene',
    description: 'Où trouver des vacations quand on est infirmier ou aide-soignant, quelles questions poser avant d’accepter, quels documents préparer. Guide pratique.',
    maj: '2026-11-20',
    resume: [
      'Dans le langage courant des soignants, une vacation est une mission ponctuelle dans un établissement : une journée, une nuit ou quelques jours pour remplacer un collègue absent ou renforcer une équipe.',
      'Ce guide explique où trouver ces missions, ce qu’il faut vérifier avant d’accepter et comment préparer votre dossier.',
    ],
    sections: [
      {
        titre: 'Où trouver des vacations',
        liste: [
          'Les établissements eux-mêmes. Beaucoup tiennent une liste de soignants à appeler en cas d’absence : laissez vos coordonnées au cadre de santé ou à la direction des soins des établissements où vous aimeriez travailler.',
          'Vos anciens employeurs et lieux de stage. Un service qui vous connaît vous rappellera plus volontiers.',
          'Les plateformes de mise en relation, comme Jolene. Les établissements y publient leurs besoins et vous postulez aux missions qui vous conviennent.',
          'Les agences d’intérim. Vous signez alors votre contrat de mission avec l’agence, qui vous met à disposition de l’établissement.',
          'France Travail et les sites d’emploi, où les offres intitulées « vacation » ou « remplacement » sont nombreuses.',
        ],
        paragraphes: [RAPPEL_PAS_INTERIM],
        sources: [FICHE_INTERIM],
      },
      {
        titre: 'Les questions à poser avant d’accepter',
        paragraphes: ['Une mission courte ne laisse pas le temps de découvrir les mauvaises surprises sur place. Avant de vous engager, faites-vous préciser :'],
        liste: [
          'le type de contrat, et avec qui vous le signez ;',
          'le taux horaire, et ce qu’il comprend ;',
          'les horaires exacts, la durée de la pause et le temps prévu pour les transmissions ;',
          'le service, le nombre de patients ou de résidents et la composition de l’équipe ce jour-là ;',
          'les accès : badge, vestiaire, codes, logiciel de soins ;',
          'la personne qui vous accueille à votre arrivée ;',
          'le délai et le mode de paiement.',
        ],
      },
      {
        titre: 'Les documents à préparer',
        paragraphes: [
          'Tout établissement vérifie que vous avez le droit d’exercer. Gardez sous forme numérique, prêts à être envoyés : votre pièce d’identité, votre diplôme, votre numéro RPPS si votre profession en dispose, et votre attestation d’assurance de responsabilité civile professionnelle si vous intervenez en libéral.',
          'Sur Jolene, les documents demandés dépendent de votre profession et du type de contrat. Ils sont vérifiés et conservés dans votre profil.',
        ],
      },
      {
        titre: 'Vacations et emploi principal : ce qu’il faut vérifier',
        paragraphes: [
          'Si vous avez déjà un emploi, renseignez-vous avant d’accepter une mission ailleurs. Les règles ne sont pas les mêmes pour un agent public et pour un salarié du secteur privé, et votre contrat peut prévoir des obligations particulières. Jolene ne se prononce pas sur votre situation personnelle : les fiches officielles ci-dessous font le point, et votre employeur ou votre service des ressources humaines peut vous répondre.',
          'Pensez aussi à votre repos. Enchaîner une nuit de vacation et une journée dans votre service engage votre sécurité et celle des patients.',
        ],
        sources: [FICHE_CUMUL_PUBLIC, FICHE_CUMUL_PRIVE],
      },
      {
        titre: 'Comment cela se passe sur Jolene',
        liste: [
          'Vous créez votre compte gratuitement et vous déposez vos documents.',
          'Chaque annonce affiche le type de contrat et le taux horaire avant votre candidature.',
          'Le contrat est généré à partir de la mission et signé en ligne.',
          'Le jour venu, vous pointez votre arrivée et votre départ depuis l’application.',
        ],
        ordonnee: true,
      },
    ],
    faq: [
      { q: 'Les vacations sont-elles payantes pour le soignant sur Jolene ?', r: 'Non. L’inscription est gratuite et aucune commission n’est prélevée sur votre rémunération : la commission est facturée à l’établissement.' },
      { q: 'Peut-on choisir ses jours ?', r: 'Oui. Vous postulez uniquement aux missions dont les dates et les horaires vous conviennent, sans aucune obligation d’en accepter.' },
      { q: 'Quel contrat est proposé ?', r: 'Chaque annonce l’indique avant candidature : contrat salarié à durée déterminée ou mission libérale. Pour une mission libérale, une attestation d’assurance de responsabilité civile professionnelle vous est demandée.' },
    ],
    liens: [
      { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
      { href: '/guides/premiere-mission-de-remplacement', label: 'Première mission de remplacement : la check-list' },
      { href: '/metier/infirmier-ide', label: 'Missions Infirmier (IDE)' },
      { href: '/metier/aide-soignant', label: 'Missions Aide-soignant' },
    ],
  },
  {
    slug: 'premiere-mission-de-remplacement',
    public: 'soignant',
    titre: 'Première mission de remplacement : la check-list du soignant',
    title: 'Première mission de remplacement : la check-list | Jolene',
    description: 'Ce qu’il faut vérifier avant d’accepter, préparer la veille, demander à l’arrivée et noter à la fin d’une première mission dans un établissement inconnu.',
    maj: '2026-11-20',
    resume: [
      'Arriver dans un service que l’on ne connaît pas, pour quelques heures, demande une préparation que l’on n’a pas besoin de faire dans son poste habituel. Cette check-list reprend, dans l’ordre, ce qui évite les difficultés les plus fréquentes.',
    ],
    sections: [
      {
        titre: 'Avant d’accepter',
        liste: [
          'Relisez les horaires, le taux horaire et le type de contrat indiqués sur l’annonce.',
          'Vérifiez le trajet et l’heure réelle à laquelle vous devrez partir de chez vous.',
          'Assurez-vous que le poste correspond à ce que vous savez faire : type de service, public accueilli, gestes attendus.',
          'N’acceptez que si vos documents sont à jour : diplôme, pièce d’identité et, selon votre situation, assurance de responsabilité civile professionnelle.',
        ],
      },
      {
        titre: 'La veille',
        liste: [
          'Notez le nom et le numéro de la personne à contacter à votre arrivée.',
          'Préparez votre tenue si l’établissement ne la fournit pas, vos chaussures, un stylo, de quoi noter.',
          'Renseignez-vous sur le stationnement, l’accès au vestiaire et le repas.',
          'Si vous avez un empêchement, prévenez sans attendre : plus l’établissement le sait tôt, plus il a de chances de se réorganiser.',
        ],
      },
      {
        titre: 'À l’arrivée',
        liste: [
          'Présentez-vous à l’équipe et au responsable présent, et demandez qui est votre référent pour la journée.',
          'Demandez les transmissions, même brèves, et les points d’attention du jour.',
          'Faites-vous montrer le chariot d’urgence, les protocoles affichés, la pharmacie du service et le logiciel de soins.',
          'Demandez vos identifiants ou la marche à suivre si vous n’en avez pas.',
          'Pointez votre arrivée si la mission le prévoit.',
        ],
      },
      {
        titre: 'Pendant la mission',
        liste: [
          'En cas de doute sur une prescription, un protocole ou un matériel, demandez : personne n’attend d’un remplaçant qu’il devine les habitudes du service.',
          'Tracez vos actes au fur et à mesure, dans l’outil de l’établissement.',
          'Signalez sans attendre tout événement inhabituel au responsable présent.',
        ],
      },
      {
        titre: 'À la fin',
        liste: [
          'Faites des transmissions complètes à l’équipe suivante.',
          'Pointez votre départ et vérifiez les heures enregistrées.',
          'Rendez badge, clés et matériel.',
          'Notez pour vous-même ce qui s’est bien passé et ce qu’il faudra demander la prochaine fois.',
        ],
      },
    ],
    faq: [
      { q: 'Que faire si le poste ne correspond pas à l’annonce ?', r: 'Dites-le sur place au responsable présent, puis à la plateforme ou à l’intermédiaire par lequel vous avez trouvé la mission. Sur Jolene, vous pouvez signaler un désaccord depuis votre espace.' },
      { q: 'Que faire en cas d’empêchement ?', r: 'Prévenez l’établissement le plus tôt possible. Sur Jolene, déclarez votre empêchement depuis l’application pour que l’établissement puisse s’organiser.' },
      { q: 'Comment les heures sont-elles comptées sur Jolene ?', r: 'Vous pointez votre arrivée et votre départ depuis l’application, puis l’établissement valide les heures.' },
    ],
    liens: [
      { href: '/guides/vacations-etablissement-de-sante', label: 'Vacations en établissement de santé : où en trouver' },
      { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
      { href: '/telecharger', label: 'Télécharger l’application' },
    ],
  },
  {
    slug: 'remplacement-aide-soignant-ehpad',
    public: 'soignant',
    titre: 'Aide-soignant : trouver des remplacements en EHPAD',
    title: 'Aide-soignant : trouver des remplacements en EHPAD | Jolene',
    description: 'Ce que les EHPAD attendent d’un aide-soignant remplaçant, comment choisir une mission et où en trouver près de chez vous. Avec les chiffres 2026.',
    maj: '2026-11-20',
    resume: [
      'En EHPAD, les équipes sont comptées et chaque absence d’aide-soignant doit être couverte. Voici ce qu’il faut savoir pour choisir vos missions de remplacement et bien les préparer.',
    ],
    chiffres: ['bmo-as-national', 'finess-ehpad-national'],
    sections: [
      {
        titre: 'Ce que les EHPAD attendent d’un remplaçant',
        liste: [
          'De l’autonomie sur les soins d’hygiène et de confort, l’aide au repas et aux déplacements.',
          'Le respect des habitudes des résidents : demandez le plan de soins ou la fiche de chaque personne dont vous vous occupez.',
          'Des transmissions fiables, écrites dans l’outil de l’établissement.',
          'De la ponctualité : une arrivée tardive retarde toute la relève.',
        ],
      },
      {
        titre: 'Bien choisir sa mission',
        paragraphes: ['Toutes les missions ne se ressemblent pas. Avant de postuler, regardez :'],
        liste: [
          'le poste : matin, soir ou nuit, et les horaires exacts ;',
          'l’unité : hébergement classique ou unité de vie protégée ;',
          'le nombre de résidents dont vous aurez la charge et le nombre de collègues présents ;',
          'la durée : une journée isolée, ou plusieurs jours qui laissent le temps de connaître les résidents ;',
          'le taux horaire et le type de contrat, affichés sur l’annonce.',
        ],
      },
      {
        titre: 'Trouver des missions près de chez vous',
        paragraphes: [
          'Commencez par les établissements proches de votre domicile : un trajet court compte, surtout pour un poste du matin ou de nuit. Laissez vos coordonnées aux EHPAD de votre secteur, et inscrivez-vous sur une plateforme pour être prévenu des besoins publiés.',
          'Sur Jolene, vous créez votre compte gratuitement, vous indiquez votre profession et votre secteur, et vous postulez aux missions qui vous conviennent.',
        ],
      },
      {
        titre: 'Les justificatifs',
        paragraphes: ['Le numéro RPPS n’est demandé que si votre profession en dispose. Pour un aide-soignant, la vérification porte sur la pièce d’identité et le diplôme d’État.'],
      },
    ],
    faq: [
      { q: 'Faut-il un numéro RPPS pour s’inscrire comme aide-soignant ?', r: 'Non. Le numéro RPPS n’est demandé que si votre profession en dispose. Pour un aide-soignant, la vérification porte sur la pièce d’identité et le diplôme.' },
      { q: 'L’inscription est-elle gratuite ?', r: 'Oui. L’inscription est gratuite pour les soignants, sans aucune commission prélevée sur votre rémunération.' },
      { q: 'Peut-on faire des remplacements en plus de son poste ?', r: 'Renseignez-vous d’abord auprès de votre employeur : les règles diffèrent selon que vous êtes agent public ou salarié du secteur privé. Le guide sur les vacations renvoie vers les fiches officielles.' },
    ],
    liens: [
      { href: '/metier/aide-soignant', label: 'Missions Aide-soignant' },
      { href: '/guides/vacations-etablissement-de-sante', label: 'Vacations en établissement de santé : où en trouver' },
      { href: '/guides/premiere-mission-de-remplacement', label: 'Première mission de remplacement : la check-list' },
      { href: '/barometre-recrutement-soignants-2026', label: 'Baromètre 2026 par département' },
    ],
  },
  {
    slug: 'absence-derniere-minute-remplacer-soignant',
    public: 'etablissement',
    titre: 'Absence de dernière minute : comment remplacer un soignant',
    title: 'Absence de dernière minute : remplacer un soignant | Jolene',
    description: 'Dans quel ordre agir quand un soignant est absent le jour même, comment rédiger une annonce qui trouve preneur et comment accueillir le remplaçant.',
    maj: '2026-11-20',
    resume: [
      'Un appel à six heures du matin, un poste découvert à sept. La manière dont l’établissement s’est préparé compte plus que la solution choisie dans l’urgence. Ce guide propose un ordre d’action et les quelques éléments à tenir prêts.',
    ],
    sections: [
      {
        titre: 'Avant l’absence : ce qu’il faut tenir prêt',
        liste: [
          'Une fiche par poste : horaires réels, tâches, effectif, particularités de l’unité.',
          'La liste à jour des remplaçants que vous connaissez, avec leurs disponibilités habituelles.',
          'Les taux horaires que vous êtes autorisé à proposer, validés à l’avance.',
          'Des accès prêts à être attribués : badge, vestiaire, identifiants du logiciel de soins.',
          'Un compte déjà ouvert sur la plateforme que vous utiliserez : on ne crée pas un compte au moment où l’on en a besoin.',
        ],
      },
      {
        titre: 'Le jour même : dans quel ordre agir',
        liste: [
          'Voir en interne : échange de poste, collègue volontaire.',
          'Appeler vos remplaçants habituels.',
          'Publier le besoin sur une plateforme de mise en relation, pour toucher des soignants que vous ne connaissez pas encore.',
          'Solliciter une agence d’intérim si vous travaillez avec l’une d’elles.',
          'Si le poste reste découvert, réorganiser les soins de la journée avec l’équipe présente et le tracer.',
        ],
        ordonnee: true,
        paragraphes: ['Les trois premières étapes peuvent être lancées en même temps. ' + RAPPEL_PAS_INTERIM],
        sources: [FICHE_INTERIM],
      },
      {
        titre: 'Rédiger une annonce qui trouve preneur',
        paragraphes: ['Un soignant décide en quelques secondes. Donnez-lui ce qu’il cherche :'],
        liste: [
          'les horaires réels, pause comprise ;',
          'le taux horaire ;',
          'le service, le public accueilli et l’effectif présent ;',
          'le logiciel de soins utilisé ;',
          'les aspects pratiques : stationnement, repas, tenue fournie ou non.',
        ],
      },
      {
        titre: 'Accueillir le remplaçant',
        liste: [
          'Désignez un référent pour la journée.',
          'Prévoyez dix minutes de transmissions et de présentation des lieux.',
          'Remettez les accès dès l’arrivée.',
          'Dites clairement ce qui est attendu et ce qui ne l’est pas.',
        ],
      },
      {
        titre: 'Après : garder la trace',
        paragraphes: ['Un remplaçant bien accueilli revient. Notez ceux avec qui la mission s’est bien passée et proposez-leur vos prochains besoins en premier. Mettez à jour la fiche de poste avec ce que la journée a révélé.'],
      },
    ],
    faq: [
      { q: 'Comment publier une mission sur Jolene ?', r: 'L’inscription de l’établissement se fait avec son SIRET et son numéro FINESS. Une mission se publie ensuite en renseignant la profession, les dates, les horaires et le taux horaire ; elle est visible immédiatement.' },
      { q: 'Que se passe-t-il si le remplaçant ne vient pas ?', r: 'Un plan de secours est activé en cas de désistement ou de non-présentation.' },
      { q: 'Combien coûte une mission pourvue ?', r: 'Une commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur la base financière validée de la mission. Aucun abonnement.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/comparer-solutions-remplacement-soignants', label: 'Comparer les solutions de remplacement' },
      { href: '/recruter-soignants/ehpad', label: 'Remplacer un soignant en EHPAD' },
      { href: '/tarifs', label: 'Tarifs' },
    ],
  },
  {
    slug: 'comparer-solutions-remplacement-soignants',
    public: 'etablissement',
    titre: 'Vivier interne, agence d’intérim, plateforme : comparer les solutions de remplacement',
    title: 'Remplacement de soignants : comparer les solutions | Jolene',
    description: 'Vivier interne, agence d’intérim ou plateforme de mise en relation : qui signe le contrat, qui choisit le soignant, ce que vous payez et ce qui reste à votre charge.',
    maj: '2026-11-20',
    resume: [
      'Un établissement dispose de trois grandes solutions pour remplacer un soignant absent. Elles ne répondent pas au même besoin et ne se paient pas de la même façon. Ce guide les compare sur des critères simples, sans les opposer : beaucoup d’établissements les combinent.',
    ],
    sections: [
      {
        titre: 'Le vivier interne de remplaçants',
        paragraphes: [
          'L’établissement emploie directement des remplaçants qu’il connaît : anciens salariés, étudiants passés en stage, professionnels à temps partiel ailleurs. Ils connaissent les lieux et les équipes.',
          'La limite est la taille du vivier. Il s’épuise pendant les congés et ne répond pas toujours à une absence du jour même. Chaque remplacement demande aussi de préparer le contrat et les formalités d’embauche.',
        ],
        sources: [FICHE_EMBAUCHE],
      },
      {
        titre: 'L’agence d’intérim',
        paragraphes: [
          'Le soignant signe un contrat de mission avec l’agence, et l’agence conclut un contrat de mise à disposition avec votre établissement. Vous recevez une facture de l’agence.',
          'Les formalités ne sont pas à votre charge. En contrepartie, le prix comprend la rémunération de l’agence, et vous ne choisissez pas toujours la personne qui se présente.',
        ],
        sources: [FICHE_INTERIM],
      },
      {
        titre: 'La plateforme de mise en relation',
        paragraphes: [
          'L’établissement publie son besoin, choisit parmi les candidatures et signe directement avec le soignant. La plateforme vérifie les profils, produit le contrat, suit les présences et établit les documents de facturation.',
          RAPPEL_PAS_INTERIM + ' Pour une mission salariée, votre établissement transmet lui-même la déclaration préalable à l’embauche à l’URSSAF.',
        ],
      },
      {
        titre: 'Les trois solutions côte à côte',
        tableau: {
          legende: 'Comparaison des trois solutions de remplacement d’un soignant',
          entetes: ['Critère', 'Vivier interne', 'Agence d’intérim', 'Jolene'],
          lignes: [
            ['Avec qui le soignant signe son contrat', 'Votre établissement', 'L’agence', 'Votre établissement'],
            ['Qui choisit le soignant', 'Vous', 'L’agence, selon votre demande', 'Vous, parmi les candidatures'],
            ['Ce que vous payez', 'La rémunération et les cotisations', 'La facture de l’agence', 'La rémunération et les cotisations, plus une commission de 15 % HT'],
            ['Contrat et suivi des présences', 'À préparer par vos soins', 'Assurés par l’agence', 'Produits par la plateforme'],
          ],
        },
      },
      {
        titre: 'Comment choisir',
        liste: [
          'La fréquence de vos besoins : un vivier interne suffit rarement quand les absences se multiplient.',
          'Le délai : pour le jour même, lancez plusieurs solutions en parallèle.',
          'Le temps administratif dont vous disposez pour chaque remplacement.',
          'Le budget : comparez à périmètre égal, en demandant à chaque intermédiaire ce que son prix comprend.',
          'Votre souhait de choisir vous-même la personne et de la retrouver d’une mission à l’autre.',
        ],
      },
    ],
    faq: [
      { q: 'Jolene est-elle une agence d’intérim ?', r: 'Non. Jolene est une plateforme de mise en relation : le contrat est signé directement entre l’établissement et le soignant, et Jolene n’est pas l’employeur.' },
      { q: 'Peut-on utiliser plusieurs solutions en même temps ?', r: 'Oui. Rien n’empêche de solliciter votre vivier, de publier le besoin sur une plateforme et de contacter une agence pour la même absence. Retirez l’annonce dès que le poste est pourvu.' },
      { q: 'Que comprend la commission de Jolene ?', r: 'La publication de missions, la vérification des profils, les contrats générés et signés électroniquement, le pointage et le suivi des présences, et les documents de facturation par période. Aucun abonnement, aucun frais caché.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/cout-remplacement-soignant', label: 'Combien coûte le remplacement d’un soignant ?' },
      { href: '/guides/absence-derniere-minute-remplacer-soignant', label: 'Absence de dernière minute : comment remplacer un soignant' },
      { href: '/tarifs', label: 'Tarifs' },
    ],
  },
  {
    slug: 'cout-remplacement-soignant',
    public: 'etablissement',
    titre: 'Combien coûte le remplacement d’un soignant ? Les postes à compter',
    title: 'Combien coûte le remplacement d’un soignant ? | Jolene',
    description: 'Rémunération, cotisations, frais d’intermédiaire, temps passé : les postes à additionner pour comparer deux solutions de remplacement, avec un exemple chiffré.',
    maj: '2026-11-20',
    resume: [
      'Comparer deux solutions de remplacement n’a de sens qu’à périmètre égal. Le prix affiché par un intermédiaire ne dit pas ce qu’il comprend, et une partie du coût ne figure sur aucune facture. Voici les postes à additionner.',
    ],
    sections: [
      {
        titre: 'Les trois postes de coût',
        liste: [
          'La rémunération du soignant et les cotisations qui s’y rapportent.',
          'Les frais de l’intermédiaire, s’il y en a un : rémunération d’une agence, commission d’une plateforme.',
          'Le temps passé en interne : recherche du remplaçant, contrat, accueil, vérification des heures.',
        ],
      },
      {
        titre: 'Avec une agence d’intérim',
        paragraphes: [
          'L’agence vous adresse une facture qui couvre la rémunération du soignant, les cotisations et sa propre rémunération. Demandez par écrit le tarif horaire facturé pour le poste et ce qu’il comprend : c’est le seul chiffre qui permette de comparer.',
          RAPPEL_PAS_INTERIM,
        ],
        sources: [FICHE_INTERIM],
      },
      {
        titre: 'Avec Jolene : un exemple chiffré',
        paragraphes: ['Jolene facture à l’établissement une commission de 15 % HT sur la base financière validée de la mission. Pour une mission salariée de 7 heures à 20 € bruts de l’heure :'],
        liste: [
          'rémunération brute de la mission : 7 × 20 € = 140 € ;',
          'commission de Jolene : 15 % de 140 € = 21 € HT, soit 25,20 € TTC avec la TVA de 20 % ;',
          's’y ajoutent les cotisations de l’employeur sur la rémunération, que vous réglez comme pour tout salarié de l’établissement.',
        ],
      },
      {
        titre: 'Ce que l’exemple ne dit pas',
        paragraphes: ['L’exemple ne porte que sur la commission. La base exacte est la rémunération brute contractuelle de la mission, majorations et indemnités incluses lorsqu’elles entrent dans cette base, ou les honoraires hors taxes pour une mission libérale. Il n’y a ni abonnement ni frais d’inscription, et aucun frais pour le soignant.'],
      },
      {
        titre: 'Le coût qui ne figure sur aucune facture',
        liste: [
          'Les heures passées par le cadre de santé à chercher un remplaçant.',
          'Les heures supplémentaires de l’équipe quand le poste reste découvert.',
          'La désorganisation d’un service où les remplaçants changent à chaque absence.',
        ],
        paragraphes: ['Ces coûts ne se chiffrent pas au centime, mais ils pèsent dans la comparaison : une solution moins chère sur la facture peut coûter davantage si elle demande deux heures de recherche à chaque absence.'],
      },
    ],
    faq: [
      { q: 'La commission est-elle due si la mission n’est pas pourvue ?', r: 'Non. Il n’y a ni abonnement ni frais d’inscription : vous ne payez que lorsque vous recrutez.' },
      { q: 'Le soignant paie-t-il quelque chose ?', r: 'Non. Aucun frais pour les soignants, quel que soit le contrat.' },
      { q: 'Existe-t-il un tarif pour les groupes d’établissements ?', r: 'Un taux négocié est possible pour les groupes : écrivez à support@jolene.app.' },
    ],
    liens: [
      { href: '/tarifs', label: 'Tarifs' },
      { href: '/guides/comparer-solutions-remplacement-soignants', label: 'Comparer les solutions de remplacement' },
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
    ],
  },
];

/** Guides où le mot « intérim » est admis : chacun contient `RAPPEL_PAS_INTERIM` (garde de test). */
export const GUIDES_CITANT_INTERIM = [
  'vacations-etablissement-de-sante',
  'absence-derniere-minute-remplacer-soignant',
  'comparer-solutions-remplacement-soignants',
  'cout-remplacement-soignant',
];

export function getGuideBySlug(slug: string): GuideSEO | undefined {
  return GUIDES_SEO.find((g) => g.slug === slug);
}

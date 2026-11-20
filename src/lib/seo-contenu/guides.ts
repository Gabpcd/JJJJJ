/**
 * Guides (`/guides/<slug>`) : contenus éditoriaux pour les soignants et les établissements.
 *
 * Règles de rédaction (docs/SEO_STRATEGIE_ACQUISITION.md §5), gardées par `seo-contenus.test.ts` :
 *  - vouvoiement, ton sobre ;
 *  - des conseils, pas des constats sur le secteur : aucune généralité présentée comme un fait
 *    (« les besoins sont fréquents », « un soignant décide en quelques secondes ») ;
 *  - aucune promesse de volume ni de délai ;
 *  - aucun chiffre ni montant dans le texte, hors le tarif publié (15 % HT, 18 % TTC, TVA de
 *    20 %) : les seuls autres chiffres sont ceux que `seo-routes` insère depuis les fichiers
 *    BMO et FINESS, avec leur source ;
 *  - aucune règle de droit affirmée par Jolene : sur le cumul d'activités, le guide renvoie
 *    vers la fiche officielle (`sources`) ;
 *  - les affirmations sur le produit sont celles déjà publiées sur le site ;
 *  - aucun guide ne parle d'intérim, ne compare Jolene à un autre type de prestataire, ni ne
 *    donne d'exemple de prix : ces sujets touchent au droit du travail et à l'assiette de la
 *    commission, et attendent la validation de Gabrielle (HARD STOP n°4, revue B8 de #1170).
 * Module pur (aucun import React/DOM).
 */
import type { QuestionSEO, SectionSEO, SourceSEO } from './types';

export type PublicGuide = 'soignant' | 'etablissement';

/** Chiffres publics qu'un guide demande à `seo-routes` d'insérer, avec leur source. */
export type ChiffreGuide = 'bmo-as-national' | 'bmo-ide-national' | 'finess-ehpad-national';

export interface GuideSEO {
  slug: string;
  public: PublicGuide;
  /** H1. */
  titre: string;
  title: string;
  description: string;
  /** Date de première publication (AAAA-MM-JJ) : ne change plus ensuite. */
  publie: string;
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

export const GUIDES_SEO: GuideSEO[] = [
  {
    slug: 'vacations-etablissement-de-sante',
    public: 'soignant',
    titre: 'Vacations en établissement de santé : où en trouver et comment s’y préparer',
    title: 'Vacations en établissement de santé : où en trouver | Jolene',
    description: 'Où chercher des vacations quand on est infirmier ou aide-soignant, quelles questions poser avant d’accepter, quels documents préparer. Guide pratique.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Dans le langage courant des soignants, une vacation est une mission ponctuelle dans un établissement : une journée, une nuit ou quelques jours pour remplacer un collègue absent ou renforcer une équipe.',
      'Ce guide explique où chercher ces missions, ce qu’il faut vérifier avant d’accepter et comment préparer votre dossier.',
    ],
    sections: [
      {
        titre: 'Où chercher des vacations',
        liste: [
          'Auprès des établissements eux-mêmes : laissez vos coordonnées au cadre de santé ou à la direction des soins de ceux où vous aimeriez travailler, pour être appelé en cas d’absence.',
          'Auprès de vos anciens employeurs et de vos lieux de stage, qui vous connaissent déjà.',
          'Sur une plateforme de mise en relation, comme Jolene : les établissements y publient leurs besoins et vous postulez aux missions qui vous conviennent.',
          'Sur France Travail et les sites d’emploi, en cherchant les offres intitulées « vacation » ou « remplacement ».',
        ],
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
          'Un établissement vérifie que vous avez le droit d’exercer. Gardez sous forme numérique, prêts à être envoyés : votre pièce d’identité, votre diplôme, votre numéro RPPS si votre profession en dispose, et votre attestation d’assurance de responsabilité civile professionnelle si vous intervenez en libéral.',
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
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Arriver dans un service que l’on ne connaît pas, pour quelques heures, demande une préparation que l’on n’a pas besoin de faire dans son poste habituel. Cette check-list reprend, dans l’ordre, ce qu’il vaut mieux avoir vérifié.',
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
          'Si vous avez un empêchement, prévenez sans attendre, pour que l’établissement puisse se réorganiser.',
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
          'En cas de doute sur une prescription, un protocole ou un matériel, demandez : un remplaçant ne peut pas deviner les habitudes du service.',
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
    description: 'Ce qu’un EHPAD attend d’un aide-soignant remplaçant, comment choisir une mission et où en chercher près de chez vous. Avec les chiffres publics de 2026.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Ce guide s’adresse aux aides-soignants qui souhaitent faire des remplacements en EHPAD : ce qu’un établissement attend d’un remplaçant, comment choisir une mission et où en chercher.',
    ],
    chiffres: ['bmo-as-national', 'finess-ehpad-national'],
    sections: [
      {
        titre: 'Ce qu’un EHPAD attend d’un remplaçant',
        liste: [
          'De l’autonomie sur les soins d’hygiène et de confort, l’aide au repas et aux déplacements.',
          'Le respect des habitudes des résidents : demandez le plan de soins ou la fiche de chaque personne dont vous vous occupez.',
          'Des transmissions fiables, écrites dans l’outil de l’établissement.',
          'De la ponctualité, pour que la relève se fasse à l’heure.',
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
        titre: 'Chercher des missions près de chez vous',
        paragraphes: [
          'Commencez par les établissements proches de votre domicile : un trajet court compte, surtout pour un poste du matin ou de nuit. Laissez vos coordonnées aux EHPAD de votre secteur.',
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
    description: 'Dans quel ordre agir quand un soignant est absent le jour même, comment rédiger une annonce claire et comment accueillir le remplaçant. Guide pratique.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Un appel à six heures du matin, un poste découvert à sept. Ce guide propose un ordre d’action et la liste de ce qu’il vaut mieux avoir préparé avant que cela n’arrive.',
    ],
    sections: [
      {
        titre: 'Avant l’absence : ce qu’il faut tenir prêt',
        liste: [
          'Une fiche par poste : horaires réels, tâches, effectif, particularités de l’unité.',
          'La liste à jour des remplaçants que vous connaissez, avec leurs disponibilités habituelles.',
          'Les taux horaires que vous êtes autorisé à proposer, validés à l’avance.',
          'Des accès prêts à être attribués : badge, vestiaire, identifiants du logiciel de soins.',
          'Un compte déjà ouvert sur la plateforme que vous utiliserez, avec ses formalités d’ouverture terminées.',
        ],
      },
      {
        titre: 'Le jour même : dans quel ordre agir',
        liste: [
          'Voir en interne : échange de poste, collègue volontaire.',
          'Appeler vos remplaçants habituels.',
          'Publier le besoin sur une plateforme de mise en relation, pour toucher des soignants que vous ne connaissez pas encore.',
          'Solliciter vos autres prestataires habituels, si vous en avez.',
          'Si le poste reste découvert, réorganiser les soins de la journée avec l’équipe présente et le tracer.',
        ],
        ordonnee: true,
        paragraphes: ['Les trois premières étapes peuvent être lancées en même temps.'],
      },
      {
        titre: 'Rédiger une annonce claire',
        paragraphes: ['Donnez au soignant de quoi se décider sans avoir à vous appeler :'],
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
          'Prévoyez un temps de transmissions et de présentation des lieux.',
          'Remettez les accès dès l’arrivée.',
          'Dites clairement ce qui est attendu et ce qui ne l’est pas.',
        ],
      },
      {
        titre: 'Après : garder la trace',
        paragraphes: ['Notez les remplaçants avec qui la mission s’est bien passée et proposez-leur vos prochains besoins en premier. Mettez à jour la fiche de poste avec ce que la journée a révélé.'],
      },
    ],
    faq: [
      { q: 'Comment publier une mission sur Jolene ?', r: 'L’inscription de l’établissement se fait avec son SIRET et son numéro FINESS. Une mission se publie ensuite en renseignant la profession, les dates, les horaires et le taux horaire ; elle est visible immédiatement.' },
      { q: 'Que se passe-t-il si le remplaçant ne vient pas ?', r: 'Un plan de secours est activé en cas de désistement ou de non-présentation.' },
      { q: 'Combien coûte une mission pourvue ?', r: 'Une commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur la base financière validée de la mission. Aucun abonnement.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/rediger-annonce-remplacement-soignant', label: 'Annonce de remplacement : les informations à donner' },
      { href: '/guides/accueillir-soignant-remplacant', label: 'Accueillir un soignant remplaçant : la check-list' },
      { href: '/recruter-soignants/ehpad', label: 'Remplacer un soignant en EHPAD' },
      { href: '/tarifs', label: 'Tarifs' },
    ],
  },
  {
    slug: 'remplacement-infirmier-etablissement',
    public: 'soignant',
    titre: 'Infirmier : trouver des remplacements en établissement',
    title: 'Infirmier : trouver des remplacements en établissement | Jolene',
    description: 'Où chercher des remplacements quand on est infirmier, comment choisir un service et quels justificatifs préparer. Avec les chiffres publics de 2026.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Ce guide s’adresse aux infirmiers qui souhaitent faire des remplacements en clinique, à l’hôpital, en EHPAD ou dans une structure de soins à domicile : où chercher, comment choisir un service et quels justificatifs préparer.',
    ],
    chiffres: ['bmo-ide-national'],
    sections: [
      {
        titre: 'Où chercher',
        liste: [
          'Auprès des établissements où vous avez déjà travaillé ou fait un stage : ils connaissent votre pratique.',
          'Auprès du cadre de santé ou de la direction des soins des établissements proches de chez vous, en laissant vos coordonnées et vos disponibilités.',
          'Sur une plateforme de mise en relation, comme Jolene, où les établissements publient leurs besoins.',
          'Sur France Travail et les sites d’emploi, avec les mots « remplacement » ou « vacation ».',
        ],
      },
      {
        titre: 'Choisir un service que l’on peut tenir',
        paragraphes: ['Un remplacement se fait sans période d’adaptation. Avant de postuler, vérifiez que le poste correspond à votre expérience :'],
        liste: [
          'la spécialité du service et les gestes attendus ;',
          'le nombre de patients ou de résidents à votre charge, et la présence d’un autre infirmier ;',
          'le poste : jour, nuit ou week-end ;',
          'le logiciel de soins et le circuit du médicament ;',
          'les responsabilités particulières du poste, par exemple la nuit.',
        ],
      },
      {
        titre: 'Les questions à poser selon le lieu',
        liste: [
          'En clinique ou à l’hôpital : la spécialité du service et le déroulé d’une journée.',
          'En EHPAD : si vous serez le seul infirmier présent, et qui joindre en cas d’urgence.',
          'En soins à domicile : le secteur couvert, le véhicule et l’organisation de la tournée.',
          'Dans un établissement pour personnes en situation de handicap : le public accueilli et les soins techniques attendus.',
        ],
      },
      {
        titre: 'Les justificatifs à préparer',
        paragraphes: [
          'Gardez sous forme numérique votre pièce d’identité, votre diplôme d’État et votre numéro RPPS. Pour une mission proposée en libéral, une attestation d’assurance de responsabilité civile professionnelle est demandée.',
          'Sur Jolene, les documents demandés dépendent de votre profession et du type de contrat. Ils sont vérifiés et conservés dans votre profil.',
        ],
      },
      {
        titre: 'Remplacements et poste principal',
        paragraphes: [
          'Si vous occupez déjà un poste, renseignez-vous auprès de votre employeur avant d’accepter une mission ailleurs : les règles ne sont pas les mêmes pour un agent public et pour un salarié du secteur privé. Jolene ne se prononce pas sur votre situation personnelle : les fiches officielles ci-dessous font le point.',
        ],
        sources: [FICHE_CUMUL_PUBLIC, FICHE_CUMUL_PRIVE],
      },
    ],
    faq: [
      { q: 'Quel contrat pour un remplacement infirmier sur Jolene ?', r: 'Chaque annonce l’indique avant candidature : contrat salarié à durée déterminée, ou mission libérale lorsqu’elle est explicitement proposée.' },
      { q: 'Comment mes qualifications sont-elles vérifiées ?', r: 'L’identité et les qualifications professionnelles sont contrôlées pour tous les soignants, notamment via le RPPS lorsqu’il existe.' },
      { q: 'L’inscription est-elle payante ?', r: 'Non. L’inscription est gratuite pour les soignants, sans aucune commission prélevée sur votre rémunération.' },
    ],
    liens: [
      { href: '/metier/infirmier-ide', label: 'Missions Infirmier (IDE)' },
      { href: '/guides/vacations-etablissement-de-sante', label: 'Vacations en établissement de santé : où en trouver' },
      { href: '/guides/premiere-mission-de-remplacement', label: 'Première mission de remplacement : la check-list' },
      { href: '/barometre-recrutement-soignants-2026', label: 'Baromètre 2026 par département' },
    ],
  },
  {
    slug: 'rediger-annonce-remplacement-soignant',
    public: 'etablissement',
    titre: 'Annonce de remplacement : les informations qu’un soignant attend',
    title: 'Rédiger une annonce de remplacement soignant | Jolene',
    description: 'Horaires, taux horaire, service, équipe, aspects pratiques : ce qu’une annonce de remplacement doit contenir pour qu’un soignant se décide sans vous appeler.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Ce guide liste les informations à donner dans une annonce de remplacement pour qu’un soignant puisse juger s’il peut tenir le poste, connaître sa rémunération et se représenter la journée, sans avoir à vous appeler.',
    ],
    sections: [
      {
        titre: 'Le poste et le service',
        liste: [
          'La profession recherchée et, s’il y a lieu, l’expérience attendue : bloc opératoire, dialyse, unité de vie protégée, soins à domicile.',
          'Le service ou l’unité, et le public accueilli.',
          'Le nombre de patients ou de résidents dont le remplaçant aura la charge.',
          'L’équipe présente ce jour-là, par profession.',
          'Le logiciel de soins utilisé.',
        ],
      },
      {
        titre: 'Les dates et les horaires',
        liste: [
          'Les horaires de début et de fin tels qu’ils sont pratiqués dans le service.',
          'La durée de la pause, en précisant si elle est comprise dans les horaires annoncés.',
          'Le temps prévu pour les transmissions.',
          'Pour une mission de plusieurs jours, le détail jour par jour plutôt qu’une période globale.',
        ],
      },
      {
        titre: 'La rémunération et le contrat',
        paragraphes: [
          'Indiquez le taux horaire et le type de contrat dès l’annonce, pour que le soignant n’ait pas à les demander, et précisez ce que le taux comprend.',
          'Sur Jolene, chaque annonce affiche le type de contrat et le taux horaire avant la candidature.',
        ],
      },
      {
        titre: 'Les aspects pratiques',
        liste: [
          'L’adresse exacte et l’entrée à utiliser.',
          'Le stationnement et les transports à proximité.',
          'Le repas : fourni, à apporter ou possible sur place.',
          'La tenue : fournie ou non.',
          'La personne à demander en arrivant.',
        ],
      },
      {
        titre: 'Ce qu’il vaut mieux éviter',
        liste: [
          'Un intitulé qui ne dit ni la profession ni le service.',
          'Des horaires arrondis, différents de ceux du poste.',
          'Une charge de travail passée sous silence : mieux vaut qu’elle soit connue avant la candidature que découverte sur place.',
          'Attendre le dernier moment pour publier une absence connue à l’avance.',
        ],
      },
      {
        titre: 'Publier la mission sur Jolene',
        liste: [
          'Vous créez votre espace avec le SIRET et le numéro FINESS de l’établissement.',
          'Vous renseignez la profession, les dates, les horaires et le taux horaire. La mission est visible immédiatement.',
          'Les soignants vérifiés postulent. Vous validez une candidature, puis le contrat est généré et signé électroniquement.',
        ],
        ordonnee: true,
      },
    ],
    faq: [
      { q: 'Que faut-il renseigner pour publier une mission sur Jolene ?', r: 'La profession, les dates, les horaires et le taux horaire. La mission est visible immédiatement.' },
      { q: 'Le taux horaire est-il visible par les soignants ?', r: 'Oui. Chaque annonce affiche le type de contrat et le taux horaire avant la candidature.' },
      { q: 'Combien coûte la publication d’une mission ?', r: 'Il n’y a ni abonnement ni frais d’entrée : vous ne payez que lorsque vous recrutez. La commission est de 15 % HT, soit 18 % TTC avec la TVA de 20 %.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/accueillir-soignant-remplacant', label: 'Accueillir un soignant remplaçant : la check-list' },
      { href: '/guides/absence-derniere-minute-remplacer-soignant', label: 'Absence de dernière minute : remplacer un soignant' },
      { href: '/tarifs', label: 'Tarifs' },
    ],
  },
  {
    slug: 'accueillir-soignant-remplacant',
    public: 'etablissement',
    titre: 'Accueillir un soignant remplaçant : la check-list du cadre de santé',
    title: 'Accueillir un soignant remplaçant : la check-list | Jolene',
    description: 'Ce qu’il faut préparer avant l’arrivée d’un remplaçant, lui montrer à la prise de poste et vérifier à la fin. Une check-list pour les cadres de santé.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Cette check-list reprend ce qu’il vaut mieux avoir préparé avant l’arrivée d’un soignant remplaçant, ce qu’il faut lui montrer à la prise de poste et ce qu’il reste à faire à la fin.',
      'Elle s’adresse aux cadres de santé, aux infirmiers coordinateurs et à toute personne chargée d’accueillir un remplaçant dans un service ou une unité.',
    ],
    sections: [
      {
        titre: 'Avant son arrivée',
        liste: [
          'Désignez la personne qui l’accueillera et prévenez l’équipe de sa venue.',
          'Préparez ses accès : badge, clé de vestiaire, codes des portes, identifiants du logiciel de soins.',
          'Tenez prête la fiche du poste : horaires, tâches attendues, organisation de la journée, numéros utiles.',
          'Vérifiez que la tenue et le matériel sont disponibles, ou précisez dans l’annonce ce qu’il doit apporter.',
          'Envoyez-lui la veille l’adresse exacte, l’entrée à utiliser, le lieu de stationnement et le nom de la personne à demander.',
        ],
      },
      {
        titre: 'À la prise de poste',
        paragraphes: ['Réservez un temps d’accueil, même court, avant les soins.'],
        liste: [
          'Présentez l’équipe présente et le référent de la journée.',
          'Faites visiter les lieux : salle de soins, pharmacie, réserve, chariot d’urgence, issues de secours.',
          'Donnez les transmissions et les points d’attention du jour : personnes à surveiller, entrées et sorties prévues.',
          'Montrez le logiciel de soins et vérifiez que ses identifiants fonctionnent.',
          'Indiquez qui appeler en cas de doute, et comment joindre le médecin ou le cadre de garde.',
        ],
      },
      {
        titre: 'Ce qui doit être écrit',
        paragraphes: ['Un remplaçant ne peut pas retenir à l’oral l’organisation d’un service entier. Rassemblez dans un document court, affiché ou remis à l’arrivée :'],
        liste: [
          'le déroulé de la journée ;',
          'les protocoles propres au service et l’endroit où les consulter ;',
          'les habitudes des résidents ou des patients qui demandent une attention particulière ;',
          'les numéros internes utiles ;',
          'la conduite à tenir en cas d’urgence.',
        ],
      },
      {
        titre: 'Pendant le poste',
        liste: [
          'Passez le voir en cours de poste pour répondre à ses questions.',
          'Confiez-lui une charge adaptée à sa connaissance des lieux, en particulier le premier jour.',
          'Dites clairement ce qui est attendu de lui et ce qui reste à la charge de l’équipe en place.',
        ],
      },
      {
        titre: 'À la fin du poste',
        liste: [
          'Assurez-vous que les transmissions à l’équipe suivante sont faites.',
          'Récupérez le badge, les clés et le matériel prêté.',
          'Vérifiez les heures réalisées et validez-les.',
          'Demandez-lui ce qui lui a manqué : sa réponse sert à l’accueil du remplaçant suivant.',
          'Si la mission s’est bien passée, dites-le-lui et proposez-lui vos prochains besoins.',
        ],
      },
    ],
    faq: [
      { q: 'Comment les heures d’un remplaçant sont-elles suivies sur Jolene ?', r: 'Le soignant pointe son arrivée et son départ depuis l’application, puis l’établissement valide les heures.' },
      { q: 'Le remplaçant a-t-il été vérifié avant sa venue ?', r: 'L’identité et les qualifications professionnelles sont contrôlées pour tous les soignants, notamment via le RPPS lorsqu’il existe.' },
      { q: 'Que se passe-t-il si le remplaçant ne se présente pas ?', r: 'Un plan de secours est activé en cas de désistement ou de non-présentation.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/rediger-annonce-remplacement-soignant', label: 'Annonce de remplacement : les informations à donner' },
      { href: '/guides/absence-derniere-minute-remplacer-soignant', label: 'Absence de dernière minute : remplacer un soignant' },
      { href: '/recruter-soignants/ehpad', label: 'Remplacer un soignant en EHPAD' },
    ],
  },
  {
    slug: 'anticiper-remplacements-conges',
    public: 'etablissement',
    titre: 'Congés d’été et fêtes de fin d’année : anticiper les remplacements',
    title: 'Congés d’été, fêtes : anticiper les remplacements | Jolene',
    description: 'Recenser les absences prévisibles, classer les besoins, publier à l’avance et garder une marge pour l’imprévu : une méthode pour préparer les périodes de congés.',
    publie: '2026-11-20',
    maj: '2026-11-20',
    resume: [
      'Les congés d’été et les fêtes de fin d’année sont des absences connues à l’avance. Ce guide propose une méthode pour les préparer : recenser les besoins, les classer, les publier tôt et garder une marge pour les absences imprévues.',
    ],
    sections: [
      {
        titre: 'Recenser les absences prévisibles',
        liste: [
          'Arrêtez le planning des congés le plus tôt possible, avec une date limite pour les demandes.',
          'Ajoutez les absences déjà connues : formations, congés de maternité, départs annoncés.',
          'Reportez le tout sur un calendrier par service et par profession.',
          'Repérez les postes qui ne peuvent pas rester découverts : nuits, week-ends, postes isolés.',
        ],
      },
      {
        titre: 'Classer les besoins',
        paragraphes: ['Les postes à couvrir n’appellent pas tous la même réponse. Pour chacun, décidez :'],
        liste: [
          'ce qui peut être absorbé en interne par une réorganisation ;',
          'ce qui peut être proposé à vos remplaçants habituels ;',
          'ce qui doit être publié à l’extérieur.',
        ],
      },
      {
        titre: 'Publier tôt, et par blocs',
        liste: [
          'Publiez les besoins dès que le planning est arrêté, sans attendre l’approche de la période.',
          'Regroupez les jours qui se suivent dans une même mission quand c’est possible : plusieurs jours laissent au remplaçant le temps de connaître le service.',
          'Donnez pour chaque mission les horaires du poste, le taux horaire et le service.',
          'Proposez d’abord les périodes aux remplaçants qui connaissent déjà l’établissement.',
        ],
      },
      {
        titre: 'Préparer l’accueil une fois pour toutes',
        paragraphes: ['Une période de congés amène plusieurs remplaçants à la suite. Préparez un accueil qui ne dépende pas de la personne présente ce jour-là :'],
        liste: [
          'une fiche par poste, à jour ;',
          'des accès prêts à être attribués ;',
          'un référent désigné pour chaque jour, week-end compris.',
        ],
      },
      {
        titre: 'Garder une marge pour l’imprévu',
        paragraphes: ['Un planning de congés couvert ne protège pas d’un arrêt de dernière minute. Tenez à jour la liste des remplaçants disponibles sur la période, validez à l’avance les taux horaires que vous pouvez proposer et gardez sous la main la marche à suivre pour une absence le jour même.'],
      },
      {
        titre: 'Après la période',
        paragraphes: ['Notez ce qui a fonctionné : les postes pourvus tôt, ceux qui sont restés découverts, les remplaçants à recontacter. Ce relevé sert de point de départ à la préparation suivante.'],
      },
    ],
    faq: [
      { q: 'Quand publier les besoins de l’été sur Jolene ?', r: 'Dès que les dates sont connues. Une mission se publie en renseignant la profession, les dates, les horaires et le taux horaire ; elle est visible immédiatement.' },
      { q: 'Faut-il un abonnement pour publier pendant une seule période ?', r: 'Non. Il n’y a ni abonnement ni engagement : vous publiez un besoin uniquement lorsque vous en avez un.' },
      { q: 'Que se passe-t-il si un remplaçant se désiste pendant la période ?', r: 'Un plan de secours est activé en cas de désistement ou de non-présentation.' },
    ],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/guides/absence-derniere-minute-remplacer-soignant', label: 'Absence de dernière minute : remplacer un soignant' },
      { href: '/guides/rediger-annonce-remplacement-soignant', label: 'Annonce de remplacement : les informations à donner' },
      { href: '/barometre-recrutement-soignants-2026', label: 'Baromètre 2026 par département' },
    ],
  },
];

export function getGuideBySlug(slug: string): GuideSEO | undefined {
  return GUIDES_SEO.find((g) => g.slug === slug);
}

export interface ArticleBlog {
  slug: string;
  titre: string;
  extrait: string;
  date: string;
  tempsLecture: number;
  tag: 'Libéral' | 'Réglementation' | 'Guide' | 'Pharmacie';
  contenu: string;
}

export const articlesBlog: ArticleBlog[] = [
  {
    slug: 'comment-devenir-idel',
    titre: 'Comment devenir infirmière libérale en 2026 : le guide complet',
    extrait: 'De la validation des 3 200 heures à l\'inscription CPAM, découvrez toutes les étapes pour vous installer en libéral sereinement.',
    date: '2026-02-18',
    tempsLecture: 8,
    tag: 'Libéral',
    contenu: `## Pourquoi passer en libéral ?

L'exercice libéral attire de plus en plus d'infirmiers et d'infirmières diplômé(e)s d'État. Et pour cause : **autonomie professionnelle, flexibilité des horaires, revenus potentiellement supérieurs** et la satisfaction de construire sa propre patientèle. En 2026, on estime que plus de 120 000 IDEL exercent en France, et la demande ne cesse de croître, notamment en zones sous-dotées.

Mais avant de franchir le pas, il faut comprendre les étapes réglementaires et administratives. Ce guide vous accompagne de A à Z.

## Étape 1 : Valider les 3 200 heures d'exercice salarié

C'est la condition sine qua non. Pour exercer en libéral, vous devez justifier de **3 200 heures d'activité professionnelle en tant qu'infirmier(ère) salarié(e)** au cours des six dernières années. Ces heures peuvent être effectuées dans un ou plusieurs établissements : hôpitaux publics, cliniques privées, EHPAD, HAD, centres de soins…

**Comment les comptabiliser ?** Chaque heure travaillée compte, y compris les heures de nuit, les week-ends et les jours fériés. Les heures de formation continue ne sont en revanche pas incluses. Demandez des attestations d'heures à chaque employeur — elles seront indispensables pour votre dossier CPAM.

Avec Jolene, votre compteur d'heures est mis à jour automatiquement après chaque mission. Vous pouvez également déclarer vos heures effectuées en dehors de la plateforme en fournissant les justificatifs.

## Étape 2 : S'inscrire à l'Ordre National des Infirmiers

L'inscription à l'Ordre est **obligatoire** pour tout exercice libéral. Elle garantit que vous respectez les règles déontologiques de la profession. La procédure se fait auprès du Conseil Départemental de l'Ordre des Infirmiers (CDOI) de votre lieu d'exercice.

**Documents à fournir :** diplôme d'État, pièce d'identité, attestation de 3 200 heures, casier judiciaire (bulletin n°3), attestation d'assurance RCP. Le délai moyen d'inscription est de 2 à 4 semaines.

## Étape 3 : Obtenir son numéro CPAM

L'enregistrement auprès de la Caisse Primaire d'Assurance Maladie est indispensable pour facturer les actes de soins. Vous obtiendrez un **numéro de facturation** qui vous permettra de télétransmettre vos feuilles de soins.

Rendez-vous à la CPAM de votre département muni de votre attestation d'inscription à l'Ordre, de votre diplôme et d'un justificatif de domicile professionnel. Le traitement du dossier prend généralement 1 à 3 semaines.

## Étape 4 : S'immatriculer à l'URSSAF

En tant que professionnel libéral, vous relevez du régime des Praticiens et Auxiliaires Médicaux Conventionnés (PAMC). L'immatriculation à l'URSSAF vous attribue un **numéro SIRET** et détermine vos cotisations sociales.

Les cotisations représentent environ 40 à 45% de votre bénéfice net. Elles couvrent la maladie, la retraite (CARPIMKO), les allocations familiales et la CSG/CRDS. Le premier appel de cotisations intervient généralement 12 mois après l'installation.

## Étape 5 : Souscrire une assurance RCP

La Responsabilité Civile Professionnelle est **obligatoire**. Elle vous couvre en cas de dommage causé à un patient dans le cadre de votre exercice. Plusieurs assureurs proposent des contrats spécifiques aux IDEL : MACSF, Groupe Pasteur Mutualité, MNH…

Comptez entre 100 et 300 € par an selon les garanties. Jolene a négocié des tarifs préférentiels avec la MACSF pour les soignants inscrits sur la plateforme.

## Étape 6 : Choisir son lieu d'exercice

Vous pouvez exercer **à domicile (tournée)**, dans un **cabinet individuel ou de groupe**, ou en **maison de santé pluriprofessionnelle (MSP)**. Le choix dépend de votre projet professionnel, de la zone géographique et de vos moyens financiers.

En zone sous-dotée, vous pouvez bénéficier du **Contrat d'Aide à l'Installation des Infirmiers (CAII)** qui offre une aide forfaitaire de 37 500 € sur 5 ans. Renseignez-vous auprès de votre CPAM.

## Étape 7 : Ouvrir un compte bancaire professionnel

Un compte dédié à votre activité professionnelle est fortement recommandé (et obligatoire pour certaines formes juridiques). Il facilite la gestion comptable et la séparation entre finances personnelles et professionnelles.

Jolene est partenaire de **Qonto**, qui propose une offre spéciale pour les professionnels de santé libéraux avec des frais réduits et un accompagnement dédié.

## En résumé

Le passage en libéral demande de la préparation, mais les démarches sont bien balisées. Avec le programme **Free Transition** de Jolene, vos frais d'installation peuvent être pris en charge jusqu'à 100% en fonction de vos heures cumulées sur la plateforme. N'hésitez pas à consulter notre page dédiée pour en savoir plus.`,
  },
  {
    slug: 'loi-rist-2025-expliquee',
    titre: 'Loi Rist : ce qui change pour le staffing médical',
    extrait: 'Plafonds de rémunération, impact sur l\'intérim médical et conséquences pour les établissements : décryptage de la loi Rist.',
    date: '2026-01-25',
    tempsLecture: 6,
    tag: 'Réglementation',
    contenu: `## Contexte : pourquoi la loi Rist ?

Adoptée en avril 2021 et progressivement mise en application, la **loi Rist** (du nom de la députée Stéphanie Rist) vise à encadrer les dépenses de personnel temporaire dans les établissements de santé publics. Face à l'explosion des coûts d'intérim médical — certains médecins facturant jusqu'à 3 000 € la garde —, le législateur a décidé de plafonner les rémunérations.

## Les plafonds par profession

Depuis le 3 avril 2023, les plafonds sont les suivants pour les missions d'intérim dans les établissements publics :

**Médecins :** le plafond journalier est fixé à **1 390 € brut** pour une journée de 24 heures (garde incluse). Ce montant inclut l'indemnité de fin de mission (IFM) et l'indemnité compensatrice de congés payés (ICP).

**Infirmiers et aides-soignants :** le taux horaire est plafonné à **environ 1,3 fois le taux conventionnel**. Concrètement, cela limite le taux horaire brut d'un IDE intérimaire à environ 27-30 € selon les conventions.

**Pharmaciens et autres professions paramédicales :** des grilles spécifiques s'appliquent, généralement basées sur un coefficient multiplicateur du salaire conventionnel de la fonction publique hospitalière.

## Impact pour les établissements

Pour les hôpitaux et établissements publics, la loi Rist a des conséquences majeures :

- **Réduction des coûts** : les dépenses d'intérim médical ont baissé de 15 à 25% dans les établissements qui appliquent strictement les plafonds.
- **Difficulté de recrutement** : certains praticiens refusent les missions plafonnées, aggravant les tensions dans les zones sous-dotées.
- **Report vers le privé** : une partie des professionnels se tourne vers les cliniques privées, non soumises aux plafonds Rist.

## Impact pour les soignants

Les soignants paramédicaux (IDE, AS, pharmaciens) sont moins touchés que les médecins, car les plafonds restent proches des rémunérations habituelles du marché. Néanmoins, la loi impose une **transparence accrue** sur les rémunérations.

Sur Jolene, tous les taux horaires sont affichés avant la candidature. La plateforme vérifie automatiquement que les missions proposées par les établissements publics respectent les plafonds Rist en vigueur. Un **bandeau d'alerte** informe le soignant si une mission est soumise au plafonnement.

## Le cas particulier du secteur privé

Les établissements privés (cliniques, EHPAD privés, pharmacies d'officine) ne sont **pas soumis aux plafonds Rist**. Ils sont libres de fixer les rémunérations selon l'offre et la demande. Cependant, la tendance du marché tend à s'aligner progressivement sur les grilles publiques.

## Ce que Jolene fait pour vous

Notre plateforme intègre nativement les règles de la loi Rist :
- **Vérification automatique** des plafonds pour les établissements publics
- **Alertes** en cas de dépassement
- **Transparence totale** sur la décomposition de la rémunération (brut, IFM, ICP, majorations)
- **Conformité garantie** avec les textes en vigueur

La loi Rist est complexe, mais Jolene simplifie sa mise en application au quotidien.`,
  },
  {
    slug: 'remplacement-pharmacie-guide',
    titre: 'Remplacement en pharmacie : guide pratique pour les titulaires',
    extrait: 'Quand faire appel à un remplaçant, obligations légales et comment Jolene simplifie le processus pour les pharmacies d\'officine.',
    date: '2026-01-10',
    tempsLecture: 6,
    tag: 'Pharmacie',
    contenu: `## Quand faire appel à un pharmacien remplaçant ?

En tant que pharmacien titulaire, vous êtes légalement tenu d'être présent dans votre officine pendant les heures d'ouverture — ou de désigner un **pharmacien remplaçant qualifié**. Plusieurs situations nécessitent un remplacement :

- **Congés annuels** : vous avez droit à 5 semaines de congés payés, mais l'officine doit rester ouverte.
- **Arrêt maladie ou accident** : situation d'urgence nécessitant un remplacement rapide.
- **Formation continue** : le DPC (Développement Professionnel Continu) impose des journées de formation obligatoires.
- **Obligations personnelles** : rendez-vous, événements familiaux…
- **Surcharge d'activité** : périodes de vaccination, épidémies, inventaires.

## Les obligations légales du remplacement

Le remplacement d'un pharmacien titulaire est strictement encadré par le **Code de la Santé Publique** :

**Le remplaçant doit être pharmacien diplômé**, inscrit à la section A (officine) ou D (adjoints) de l'Ordre des Pharmaciens. Un étudiant en pharmacie en cours de thèse peut remplacer sous conditions, à condition d'avoir validé sa 6ème année.

**Déclaration obligatoire** : tout remplacement de plus de 8 jours doit être déclaré au Conseil de l'Ordre des Pharmaciens. Le titulaire reste responsable de l'officine pendant la durée du remplacement.

**Contrat écrit** : un contrat de remplacement (ou CDD) doit être établi entre le titulaire et le remplaçant. Il précise la durée, les horaires, la rémunération et les conditions d'exercice.

## Les défis du remplacement en 2026

La pharmacie d'officine connaît une **pénurie croissante de professionnels**. Selon l'Ordre des Pharmaciens, le nombre de pharmaciens en activité a diminué de 3% en 5 ans, alors que le nombre d'officines reste stable.

Les conséquences sont directes : **délais de remplacement allongés** (parfois plusieurs semaines pour trouver un remplaçant), **coûts en hausse** et **risque de fermeture temporaire** pour les officines rurales.

## Comment Jolene simplifie le remplacement

Notre plateforme a été conçue pour répondre aux besoins spécifiques des pharmacies :

**Publication rapide** : décrivez votre mission (dates, horaires, type de pharmacie) et publiez-la en 5 minutes. Votre annonce est visible immédiatement par les pharmaciens remplaçants inscrits dans votre zone géographique.

**Pharmaciens vérifiés** : chaque pharmacien inscrit sur Jolene est vérifié auprès du RPPS. Diplôme, inscription à l'Ordre et assurance RCP sont contrôlés avant toute candidature.

**Contrats automatiques** : le contrat de remplacement est généré automatiquement, conforme au Code de la Santé Publique, et signé électroniquement par les deux parties.

**Pointage et facturation** : le pharmacien remplaçant pointe son arrivée et son départ via l'application. La facturation est automatique et consolidée mensuellement.

**Partenariat Leader Santé** : les pharmacies membres du réseau Leader Santé bénéficient de tarifs préférentiels et d'un accompagnement dédié.

## En résumé

Le remplacement en pharmacie ne devrait pas être une source de stress. Avec Jolene, trouvez un remplaçant qualifié en quelques heures, en toute conformité légale. Inscrivez-vous gratuitement et publiez votre première mission dès aujourd'hui.`,
  },
  {
    slug: 'cddu-contrat-usage-sante',
    titre: 'Le CDDU dans la santé : tout comprendre en 5 minutes',
    extrait: 'CDD d\'usage, IFM, ICP : tout ce qu\'il faut savoir sur le contrat de travail temporaire dans le secteur de la santé.',
    date: '2025-12-15',
    tempsLecture: 5,
    tag: 'Réglementation',
    contenu: `## Qu'est-ce qu'un CDDU ?

Le **Contrat à Durée Déterminée d'Usage** (CDDU ou CDD d'usage) est un type particulier de CDD prévu par l'article L.1242-2-3° du Code du Travail. Il est autorisé dans certains secteurs d'activité où il est d'usage constant de ne pas recourir au CDI, en raison de la nature de l'activité exercée et du caractère temporaire de l'emploi.

Le secteur de la santé fait partie des secteurs autorisés, ce qui permet aux établissements de recruter des soignants pour des missions ponctuelles sans les contraintes du CDD classique.

## Différences entre CDD classique et CDDU

| | CDD classique | CDDU |
|---|---|---|
| Motif | Remplacement, surcroît d'activité | Usage constant du secteur |
| Durée max | 18 mois (renouvellement inclus) | Pas de durée maximale légale |
| Renouvellement | 2 fois maximum | Illimité |
| Délai de carence | Obligatoire entre deux CDD | Pas de délai de carence |
| IFM | 10% du salaire brut | Pas obligatoire (sauf convention) |

## Les indemnités : IFM et ICP

**L'Indemnité de Fin de Mission (IFM)** : dans le cadre d'un CDD classique, elle est de 10% de la rémunération brute totale. Pour le CDDU, elle n'est pas obligatoire sauf si la convention collective du secteur le prévoit. Dans la pratique, Jolene inclut systématiquement l'IFM pour garantir l'attractivité des missions.

**L'Indemnité Compensatrice de Congés Payés (ICP)** : elle est de 10% de la rémunération brute (IFM incluse). Elle compense le fait que le salarié en CDD n'a pas pu prendre ses congés payés pendant la durée du contrat. L'ICP est **toujours obligatoire**, y compris pour les CDDU.

## Avantages du CDDU pour les établissements

- **Souplesse** : pas de délai de carence entre deux contrats, ce qui permet de renouveler les missions sans interruption.
- **Adaptabilité** : durée ajustable en fonction des besoins réels de l'établissement.
- **Simplicité administrative** : sur Jolene, le contrat est généré et signé électroniquement en quelques clics.

## Obligations de l'employeur

Même dans le cadre d'un CDDU, l'établissement reste soumis à des obligations :

- **Contrat écrit** obligatoire, remis au salarié dans les 48 heures suivant l'embauche.
- **Déclaration Unique d'Embauche (DUE)** auprès de l'URSSAF avant la prise de poste.
- **Respect des durées maximales de travail** : 10h/jour, 48h/semaine, repos de 11h entre deux journées.
- **Rémunération au moins égale** à celle d'un salarié en CDI occupant le même poste.

## Comment Jolene gère les CDDU

Notre plateforme automatise l'intégralité du processus :
- Génération automatique du contrat CDDU conforme
- Calcul transparent de la rémunération (brut + IFM + ICP + majorations)
- Rappel DUE à l'établissement
- Vérification des durées légales de travail et des repos obligatoires
- Signature électronique sécurisée

Le CDDU est l'outil contractuel idéal pour le staffing médical. Jolene le rend accessible et conforme, sans paperasse.`,
  },
  {
    slug: 'free-transition-liberal',
    titre: 'Free Transition : Jolene finance votre passage en libéral',
    extrait: 'Découvrez comment Jolene prend en charge jusqu\'à 100% de vos frais d\'installation en libéral grâce au programme Free Transition.',
    date: '2025-11-28',
    tempsLecture: 5,
    tag: 'Libéral',
    contenu: `## Le passage en libéral : un investissement

S'installer en libéral représente un coût non négligeable. Entre l'assurance RCP, la comptabilité, le compte bancaire professionnel, les frais d'inscription à l'Ordre et l'équipement de départ, la facture peut rapidement atteindre **2 000 à 5 000 €**. C'est un frein majeur pour de nombreux soignants qui hésitent à franchir le pas.

C'est pourquoi nous avons créé **Free Transition**, un programme unique qui prend en charge progressivement vos frais d'installation.

## Les 4 paliers de prise en charge

Free Transition fonctionne sur un système de paliers basé sur vos heures cumulées sur Jolene :

### Palier 1 — 800 heures : 25% pris en charge
Dès 800 heures cumulées, Soin Direct prend en charge **25% de vos frais d'installation**. Cela couvre typiquement une partie de votre assurance RCP et de votre premier bilan comptable.

### Palier 2 — 1 600 heures : 50% pris en charge
À mi-parcours, la prise en charge monte à **50%**. Vous bénéficiez en plus des frais bancaires professionnels offerts pendant 6 mois grâce à notre partenariat avec Qonto.

### Palier 3 — 2 400 heures : 75% pris en charge
Les trois quarts de vos frais sont couverts. Vous accédez également à un **accompagnement personnalisé** avec un conseiller dédié qui vous guide dans vos démarches administratives (CPAM, Ordre, URSSAF).

### Palier 4 — 3 200 heures : 100% pris en charge
**Transition gratuite.** L'intégralité de vos frais d'installation est prise en charge par Soin Direct. Vous n'avez plus qu'à exercer.

## Quels frais sont couverts ?

Le programme Free Transition couvre les postes de dépenses suivants :

- **Assurance RCP** : via notre partenaire MACSF, avec des tarifs négociés (100-300 €/an)
- **Comptabilité** : abonnement Indy (anciennement Georges) pour la comptabilité en ligne (20-30 €/mois)
- **Compte bancaire professionnel** : offre Qonto dédiée aux professionnels de santé
- **Inscription à l'Ordre** : frais d'inscription au tableau (environ 75 €)
- **Accompagnement administratif** : aide à la constitution des dossiers CPAM et URSSAF

## Témoignage : Sophie, IDE passée en libéral

*« J'ai découvert Soin Direct en cherchant des remplacements pour valider mes 3 200 heures. En 20 mois de missions régulières, j'ai atteint le palier 4. Le programme Free Transition a couvert tous mes frais d'installation : RCP, comptabilité, compte bancaire. Mon conseiller Soin Direct m'a même aidée à remplir mon dossier CPAM. Aujourd'hui, je suis installée en libéral dans le Val-de-Marne et je n'ai pas déboursé un centime pour ma transition. »*

**— Sophie M., IDEL, Val-de-Marne**

## Comment en bénéficier ?

C'est simple : il suffit de **créer votre compte soignant sur Soin Direct** et de commencer à effectuer des missions. Votre compteur d'heures se met à jour automatiquement. Dès que vous atteignez un palier, vous êtes notifié et la prise en charge s'active.

Vous pouvez suivre votre progression en temps réel dans la section **Parcours 3 200h** de votre tableau de bord. Et si vous avez déjà effectué des heures en dehors de Soin Direct, vous pouvez les déclarer et les faire valider.

Le libéral n'a jamais été aussi accessible. Lancez-vous.`,
  },
];

const tagColors: Record<string, string> = {
  'Libéral': 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300',
  'Réglementation': 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300',
  'Guide': 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300',
  'Pharmacie': 'bg-violet-100 text-violet-800 dark:bg-violet-900/40 dark:text-violet-300',
};

export function getTagClasses(tag: string): string {
  return tagColors[tag] ?? 'bg-muted text-muted-foreground';
}

const gradients = [
  'from-primary/80 to-primary-dark',
  'from-primary/60 via-primary/80 to-accent-navy/80',
  'from-accent-navy/70 to-primary/70',
  'from-primary/70 to-emerald-600/60',
  'from-accent-navy/80 via-primary/50 to-primary/80',
];

export function getArticleGradient(index: number): string {
  return gradients[index % gradients.length];
}

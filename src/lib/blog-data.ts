export interface ArticleBlog {
  slug: string;
  titre: string;
  extrait: string;
  date: string;
  tempsLecture: number;
  tag: 'Libéral' | 'Réglementation' | 'Guide' | 'Pharmacie' | 'Intérim' | 'EHPAD';
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
    slug: 'cdd-contrat-usage-sante',
    titre: 'Le CDD dans la santé : tout comprendre en 5 minutes',
    extrait: 'CDD d\'usage, IFM, ICP : tout ce qu\'il faut savoir sur le contrat de travail temporaire dans le secteur de la santé.',
    date: '2025-12-15',
    tempsLecture: 5,
    tag: 'Réglementation',
    contenu: `## Qu'est-ce qu'un CDD ?

Le **Contrat à Durée Déterminée d'Usage** (CDD ou CDD d'usage) est un type particulier de CDD prévu par l'article L.1242-2-3° du Code du Travail. Il est autorisé dans certains secteurs d'activité où il est d'usage constant de ne pas recourir au CDI, en raison de la nature de l'activité exercée et du caractère temporaire de l'emploi.

Le secteur de la santé fait partie des secteurs autorisés, ce qui permet aux établissements de recruter des soignants pour des missions ponctuelles sans les contraintes du CDD classique.

## Différences entre CDD classique et CDD

| | CDD classique | CDD |
|---|---|---|
| Motif | Remplacement, surcroît d'activité | Usage constant du secteur |
| Durée max | 18 mois (renouvellement inclus) | Pas de durée maximale légale |
| Renouvellement | 2 fois maximum | Illimité |
| Délai de carence | Obligatoire entre deux CDD | Pas de délai de carence |
| IFM | 10% du salaire brut | Pas obligatoire (sauf convention) |

## Les indemnités : IFM et ICP

**L'Indemnité de Fin de Mission (IFM)** : dans le cadre d'un CDD classique, elle est de 10% de la rémunération brute totale. Pour le CDD, elle n'est pas obligatoire sauf si la convention collective du secteur le prévoit. Dans la pratique, Jolene inclut systématiquement l'IFM pour garantir l'attractivité des missions.

**L'Indemnité Compensatrice de Congés Payés (ICP)** : elle est de 10% de la rémunération brute (IFM incluse). Elle compense le fait que le salarié en CDD n'a pas pu prendre ses congés payés pendant la durée du contrat. L'ICP est **toujours obligatoire**, y compris pour les CDD.

## Avantages du CDD pour les établissements

- **Souplesse** : pas de délai de carence entre deux contrats, ce qui permet de renouveler les missions sans interruption.
- **Adaptabilité** : durée ajustable en fonction des besoins réels de l'établissement.
- **Simplicité administrative** : sur Jolene, le contrat est généré et signé électroniquement en quelques clics.

## Obligations de l'employeur

Même dans le cadre d'un CDD, l'établissement reste soumis à des obligations :

- **Contrat écrit** obligatoire, remis au salarié dans les 48 heures suivant l'embauche.
- **Déclaration Préalable à l'Embauche (DPAE)** auprès de l'URSSAF avant la prise de poste.
- **Respect des durées maximales de travail** : 10h/jour, 48h/semaine, repos de 11h entre deux journées.
- **Rémunération au moins égale** à celle d'un salarié en CDI occupant le même poste.

## Comment Jolene gère les CDD

Notre plateforme automatise l'intégralité du processus :
- Génération automatique du contrat CDD conforme
- Calcul transparent de la rémunération (brut + IFM + ICP + majorations)
- Rappel DPAE à l'établissement
- Vérification des durées légales de travail et des repos obligatoires
- Signature électronique sécurisée

Le CDD est l'outil contractuel idéal pour le staffing médical. Jolene le rend accessible et conforme, sans paperasse.`,
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
Dès 800 heures cumulées, Jolene prend en charge **25% de vos frais d'installation**. Cela couvre typiquement une partie de votre assurance RCP et de votre premier bilan comptable.

### Palier 2 — 1 600 heures : 50% pris en charge
À mi-parcours, la prise en charge monte à **50%**. Vous bénéficiez en plus des frais bancaires professionnels offerts pendant 6 mois grâce à notre partenariat avec Qonto.

### Palier 3 — 2 400 heures : 75% pris en charge
Les trois quarts de vos frais sont couverts. Vous accédez également à un **accompagnement personnalisé** avec un conseiller dédié qui vous guide dans vos démarches administratives (CPAM, Ordre, URSSAF).

### Palier 4 — 3 200 heures : 100% pris en charge
**Transition gratuite.** L'intégralité de vos frais d'installation est prise en charge par Jolene. Vous n'avez plus qu'à exercer.

## Quels frais sont couverts ?

Le programme Free Transition couvre les postes de dépenses suivants :

- **Assurance RCP** : via notre partenaire MACSF, avec des tarifs négociés (100-300 €/an)
- **Comptabilité** : abonnement Indy (anciennement Georges) pour la comptabilité en ligne (20-30 €/mois)
- **Compte bancaire professionnel** : offre Qonto dédiée aux professionnels de santé
- **Inscription à l'Ordre** : frais d'inscription au tableau (environ 75 €)
- **Accompagnement administratif** : aide à la constitution des dossiers CPAM et URSSAF

## Témoignage : Sophie, IDE passée en libéral

*« J'ai découvert Jolene en cherchant des remplacements pour valider mes 3 200 heures. En 20 mois de missions régulières, j'ai atteint le palier 4. Le programme Free Transition a couvert tous mes frais d'installation : RCP, comptabilité, compte bancaire. Mon conseiller Jolene m'a même aidée à remplir mon dossier CPAM. Aujourd'hui, je suis installée en libéral dans le Val-de-Marne et je n'ai pas déboursé un centime pour ma transition. »*

**— Sophie M., IDEL, Val-de-Marne**

## Comment en bénéficier ?

C'est simple : il suffit de **créer votre compte soignant sur Jolene** et de commencer à effectuer des missions. Votre compteur d'heures se met à jour automatiquement. Dès que vous atteignez un palier, vous êtes notifié et la prise en charge s'active.

Vous pouvez suivre votre progression en temps réel dans la section **Parcours 3 200h** de votre tableau de bord. Et si vous avez déjà effectué des heures en dehors de Jolene, vous pouvez les déclarer et les faire valider.

Le libéral n'a jamais été aussi accessible. Lancez-vous.`,
  },
  {
    slug: 'aide-soignante-interim-guide',
    titre: 'Aide-soignante en intérim : le guide complet pour 2026',
    extrait: 'Rémunération, conditions, avantages et démarches : tout ce qu\'il faut savoir pour exercer comme aide-soignant(e) intérimaire.',
    date: '2026-03-15',
    tempsLecture: 7,
    tag: 'Guide',
    contenu: `## Pourquoi l'intérim séduit de plus en plus d'aides-soignants

Le métier d'aide-soignant(e) est l'un des plus demandés dans le secteur de la santé en France. Avec plus de **400 000 AS en exercice** et une pénurie structurelle estimée à 30 000 postes vacants, l'intérim s'impose comme une solution attractive tant pour les établissements que pour les professionnels.

En 2026, près de **15% des aides-soignants** choisissent l'intérim ou le remplacement comme mode d'exercice principal ou complémentaire. Les raisons ? Une rémunération souvent supérieure au CDI, la liberté de choisir ses missions et la découverte de différents environnements de travail.

## Combien gagne un(e) aide-soignant(e) intérimaire ?

La rémunération d'un(e) AS intérimaire varie en fonction de plusieurs facteurs :

**Taux horaire de base :** entre 16 et 22\u20AC brut de l'heure, selon l'établissement et la zone géographique. Les missions en Île-de-France et dans les zones sous-dotées offrent généralement les taux les plus élevés.

**Majorations légales :** nuit (+25%), dimanche (+40%), jour férié (+100%). Ces majorations s'appliquent sur le taux horaire de base et peuvent significativement augmenter la rémunération.

**Indemnités :** en CDD, l'aide-soignant(e) perçoit une Indemnité de Fin de Mission (IFM) de 10% et une Indemnité Compensatrice de Congés Payés (ICP) de 10%, ce qui porte la rémunération totale à environ **120% du taux de base**.

## Quels établissements recrutent des AS en intérim ?

Les principaux recruteurs d'aides-soignants intérimaires sont :

- **EHPAD** : c'est le premier pourvoyeur de missions AS, avec des besoins constants liés au turn-over et à l'absentéisme.
- **Hôpitaux publics** : services de médecine, chirurgie, SSR, et urgences recrutent régulièrement des AS en remplacement.
- **Cliniques privées** : les besoins sont croissants, notamment dans les services de soins de suite.
- **SSIAD et HAD** : pour les soins à domicile, les AS interviennent au domicile des patients.
- **Établissements médico-sociaux** : IME, MAS, FAM pour l'accompagnement de personnes en situation de handicap.

## Comment s'inscrire sur Jolene en tant qu'aide-soignant(e)

L'inscription sur Jolene est gratuite et prend moins de 5 minutes :

**Étape 1 — Créez votre compte.** Renseignez vos informations personnelles, votre profession (aide-soignant) et votre zone géographique de recherche.

**Étape 2 — Téléversez vos documents.** Diplôme d'État d'Aide-Soignant (DEAS), pièce d'identité et attestation d'assurance RCP. Votre numéro ADELI sera vérifié par notre équipe.

**Étape 3 — Postulez aux missions.** Dès la validation de votre profil (sous 24h), vous accédez à toutes les missions AS disponibles dans votre zone. Postulez en un clic.

## Les avantages spécifiques pour les AS sur Jolene

- **Paiement rapide** : vos heures validées sont payées sous 7 jours.
- **Planning en temps réel** : visualisez vos missions, vos repos obligatoires et vos disponibilités dans un calendrier intégré.
- **Assurance complémentaire** : Jolene propose une couverture prévoyance optionnelle pour les soignants en mission.
- **Pas de frais** : l'inscription et l'utilisation de la plateforme sont 100% gratuites pour les soignants.

L'intérim est une opportunité pour les aides-soignants qui souhaitent diversifier leur expérience, améliorer leur rémunération ou simplement retrouver de la flexibilité dans leur vie professionnelle. Lancez-vous.`,
  },
  {
    slug: 'taux-horaire-infirmier-2026',
    titre: 'Taux horaire infirmier intérimaire en 2026 : grille complète',
    extrait: 'Combien gagne un(e) IDE en intérim ? Grille de taux horaires par type d\'établissement, spécialité et zone géographique.',
    date: '2026-03-28',
    tempsLecture: 6,
    tag: 'Intérim',
    contenu: `## Taux horaire IDE intérimaire : ce qu'il faut savoir en 2026

La rémunération des infirmiers intérimaires est un sujet central pour les soignants qui choisissent le remplacement ou l'intérim comme mode d'exercice. En 2026, le marché reste très favorable aux IDE, avec une demande qui dépasse largement l'offre dans la plupart des régions françaises.

Ce guide détaille les taux horaires moyens constatés sur Jolene, par type d'établissement, par spécialité et par zone géographique.

## Grille de taux horaires par type d'établissement

**Hôpital public :** le taux horaire brut se situe entre **25 et 30\u20AC/h** pour un poste en service de médecine ou chirurgie. Les plafonds de la loi Rist s'appliquent et limitent la rémunération à environ 1,3 fois le taux conventionnel. Les majorations (nuit, week-end, férié) s'ajoutent au taux de base.

**Clinique privée :** les taux sont généralement plus élevés, entre **27 et 35\u20AC/h**, car les cliniques ne sont pas soumises aux plafonds Rist. La concurrence entre établissements privés pousse les rémunérations à la hausse, notamment pour les spécialités en tension.

**EHPAD :** le taux moyen se situe entre **24 et 30\u20AC/h**. Les EHPAD publics sont soumis à la loi Rist, tandis que les EHPAD privés peuvent proposer des taux plus attractifs.

**HAD et SSIAD :** les missions à domicile sont rémunérées entre **26 et 32\u20AC/h**, avec parfois des indemnités kilométriques en supplément.

## Majorations et indemnités

Au taux horaire de base s'ajoutent plusieurs éléments de rémunération :

- **Majoration de nuit** : +25% entre 21h et 6h (soit environ +6 à 8\u20AC/h)
- **Majoration dimanche** : +40% (soit environ +10 à 14\u20AC/h)
- **Majoration jour férié** : +100% (doublement du taux horaire)
- **IFM** (Indemnité de Fin de Mission) : +10% sur le brut total en CDD
- **ICP** (Indemnité Compensatrice de Congés Payés) : +10% sur le brut total (IFM incluse)

**Exemple concret :** un IDE en mission de nuit un dimanche, avec un taux de base de 28\u20AC/h, perçoit : 28 + 7 (nuit) + 11,20 (dimanche) = **46,20\u20AC/h brut**, auxquels s'ajoutent IFM et ICP.

## Variations géographiques

Les taux horaires varient significativement selon les régions :

**Île-de-France :** taux les plus élevés du marché, entre 28 et 35\u20AC/h en moyenne. La densité d'établissements et la concurrence salariale expliquent ces niveaux.

**Grandes métropoles (Lyon, Marseille, Toulouse, Bordeaux) :** taux entre 25 et 32\u20AC/h, avec des pics pour les spécialités en tension (bloc opératoire, réanimation).

**Zones rurales et sous-dotées :** paradoxalement, certaines zones rurales proposent des taux élevés (jusqu'à 35\u20AC/h) pour attirer les soignants. Les aides à l'installation (CAII) peuvent compléter la rémunération.

## Spécialités les mieux rémunérées

Toutes les spécialités IDE ne sont pas rémunérées de la même manière :

- **IADE (Infirmier Anesthésiste)** : 32-48\u20AC/h — la spécialité la mieux payée
- **IBODE (Infirmier de Bloc)** : 30-42\u20AC/h — forte demande au bloc opératoire
- **IDE de réanimation** : 28-38\u20AC/h — compétences critiques très recherchées
- **IDE de soins généraux** : 25-32\u20AC/h — le plus grand volume de missions

## Ce que Jolene affiche sur chaque mission

Sur Jolene, chaque mission affiche clairement :
- Le **taux horaire brut** de base
- Les **majorations applicables** (nuit, week-end, férié)
- Le **montant estimé** des IFM et ICP
- Le **revenu net estimé** après cotisations

Aucune surprise à l'arrivée. La transparence est notre engagement.`,
  },
  {
    slug: 'ehpad-recrutement-soignants',
    titre: 'EHPAD : comment recruter des soignants face à la pénurie',
    extrait: 'Stratégies de recrutement, fidélisation et solutions digitales pour les EHPAD confrontés à la pénurie de soignants.',
    date: '2026-04-05',
    tempsLecture: 7,
    tag: 'EHPAD',
    contenu: `## La crise du recrutement en EHPAD

Les EHPAD français traversent une crise de recrutement sans précédent. Selon la DREES, **plus de 60% des EHPAD** déclarent rencontrer des difficultés pour recruter des aides-soignants, et **45% pour recruter des infirmiers**. Cette pénurie a des conséquences directes sur la qualité de la prise en charge des résidents.

Les causes sont multiples : vieillissement de la population soignante, manque d'attractivité du secteur, concurrence du secteur hospitalier et des cliniques privées, conditions de travail jugées difficiles et rémunérations perçues comme insuffisantes.

## Les professions les plus en tension

En EHPAD, les professions les plus difficiles à recruter sont :

**Aides-soignant(e)s** : c'est la profession la plus touchée par la pénurie. Un EHPAD de 80 lits a besoin en moyenne de 25 à 30 AS pour assurer la continuité des soins. Le turn-over annuel peut atteindre 30% dans certains établissements.

**Infirmier(ère)s** : les IDE en EHPAD sont responsables de la coordination des soins, de l'administration des traitements et de la surveillance clinique. Un ratio d'un(e) IDE pour 30 résidents est la norme, mais il est rarement atteint.

**Médecins coordonnateurs** : la fonction de médecin coordonnateur est essentielle mais de plus en plus difficile à pourvoir. Beaucoup d'EHPAD fonctionnent avec un temps partiel, voire sans médecin coordonnateur.

**Kinésithérapeutes et ergothérapeutes** : ces professionnels interviennent dans la prévention des chutes et le maintien de l'autonomie. Leur recrutement est rendu difficile par l'attractivité de l'exercice libéral.

## Stratégies pour améliorer le recrutement

### 1. Revaloriser les conditions de travail

Au-delà de la rémunération, les conditions de travail sont le premier facteur d'attractivité :
- **Plannings prévisibles** : publier les plannings au moins 3 semaines à l'avance
- **Ratio soignants/résidents** : viser un ratio supérieur aux minimums réglementaires
- **Formation continue** : proposer des formations qualifiantes et des perspectives d'évolution
- **Bien-être au travail** : salle de repos, repas offerts, moments de convivialité

### 2. Proposer des rémunérations compétitives

Le Ségur de la Santé a permis une revalorisation salariale, mais les écarts avec le secteur privé persistent. Les EHPAD peuvent :
- Proposer des **primes d'attractivité** pour les zones sous-dotées
- Offrir des **avantages en nature** (logement, repas, mutuelle renforcée)
- Mettre en place des **primes de fidélisation** pour réduire le turn-over

### 3. Utiliser le digital pour recruter

Les plateformes digitales de staffing médical transforment le recrutement en EHPAD :
- **Publication instantanée** : une mission peut être publiée en 5 minutes et visible par des milliers de soignants
- **Soignants vérifiés** : diplômes, RPPS/ADELI et RCP contrôlés avant toute candidature
- **Flexibilité** : recrutement ponctuel (remplacement) ou régulier (pool de soignants fidélisés)

## Comment Jolene aide les EHPAD

Jolene a été conçu pour répondre aux besoins spécifiques des EHPAD :

**Publication rapide** : décrivez votre mission (dates, horaires, profession, service) et publiez-la en quelques clics. Votre annonce est visible immédiatement par les soignants qualifiés de votre zone.

**Matching intelligent** : notre algorithme propose votre mission en priorité aux soignants qui correspondent à votre besoin (profession, distance, disponibilité, évaluations).

**Pool de soignants fidélisés** : les soignants qui ont déjà travaillé dans votre EHPAD peuvent être ajoutés à votre pool. Ils seront notifiés en priorité de vos nouvelles missions.

**Gestion administrative simplifiée** : contrats CDD générés automatiquement, pointage digital, facturation consolidée. Vous gagnez du temps sur l'administratif pour vous concentrer sur le soin.

**Tarification adaptée** : Jolene propose des tarifs préférentiels aux EHPAD, avec une commission transparente et sans frais cachés.

## En résumé

La pénurie de soignants en EHPAD est un défi structurel qui nécessite des réponses multiples : revalorisation des conditions de travail, rémunération compétitive et utilisation des outils digitaux. Jolene s'inscrit dans cette démarche en simplifiant le recrutement et en connectant les EHPAD aux soignants qualifiés de leur territoire.`,
  },
];

const tagColors: Record<string, string> = {
  'Libéral': 'bg-gradient-to-r from-emerald-100 to-teal-100 text-emerald-800 dark:from-emerald-900/40 dark:to-teal-900/40 dark:text-emerald-300',
  'Réglementation': 'bg-gradient-to-r from-amber-100 to-orange-100 text-amber-800 dark:from-amber-900/40 dark:to-orange-900/40 dark:text-amber-300',
  'Guide': 'bg-gradient-to-r from-blue-100 to-indigo-100 text-blue-800 dark:from-blue-900/40 dark:to-indigo-900/40 dark:text-blue-300',
  'Pharmacie': 'bg-gradient-to-r from-violet-100 to-purple-100 text-violet-800 dark:from-violet-900/40 dark:to-purple-900/40 dark:text-violet-300',
  'Intérim': 'bg-gradient-to-r from-cyan-100 to-sky-100 text-cyan-800 dark:from-cyan-900/40 dark:to-sky-900/40 dark:text-cyan-300',
  'EHPAD': 'bg-gradient-to-r from-rose-100 to-pink-100 text-rose-800 dark:from-rose-900/40 dark:to-pink-900/40 dark:text-rose-300',
};

export function getTagClasses(tag: string): string {
  return tagColors[tag] ?? 'bg-muted text-muted-foreground';
}

// Slug-based gradients with distinct colors per article
const articleGradients: Record<string, string> = {
  'comment-devenir-idel': 'from-teal-400 via-cyan-400 to-emerald-400',
  'loi-rist-2025-expliquee': 'from-indigo-500 via-purple-500 to-pink-400',
  'remplacement-pharmacie-guide': 'from-emerald-400 via-teal-400 to-cyan-300',
  'cdd-contrat-usage-sante': 'from-violet-500 via-fuchsia-500 to-pink-400',
  'free-transition-liberal': 'from-amber-400 via-orange-400 to-rose-400',
  'aide-soignante-interim-guide': 'from-cyan-400 via-sky-400 to-blue-400',
  'taux-horaire-infirmier-2026': 'from-teal-500 via-emerald-400 to-green-400',
  'ehpad-recrutement-soignants': 'from-rose-400 via-pink-400 to-fuchsia-400',
};

const articleIcons: Record<string, string> = {
  'comment-devenir-idel': 'Stethoscope',
  'loi-rist-2025-expliquee': 'Scale',
  'remplacement-pharmacie-guide': 'Pill',
  'cdd-contrat-usage-sante': 'FileText',
  'free-transition-liberal': 'Rocket',
  'aide-soignante-interim-guide': 'HeartHandshake',
  'taux-horaire-infirmier-2026': 'Euro',
  'ehpad-recrutement-soignants': 'Building2',
};

const fallbackGradients = [
  'from-primary/80 to-primary-dark',
  'from-primary/60 via-primary/80 to-accent-navy/80',
  'from-accent-navy/70 to-primary/70',
  'from-primary/70 to-emerald-600/60',
  'from-accent-navy/80 via-primary/50 to-primary/80',
];

export function getArticleGradient(index: number, slug?: string): string {
  if (slug && articleGradients[slug]) return articleGradients[slug];
  return fallbackGradients[index % fallbackGradients.length];
}

export function getArticleIconName(slug: string): string | null {
  return articleIcons[slug] || null;
}

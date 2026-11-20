# Kit hors site — textes prêts à l'emploi

> Rédigé le 20/11/2026, dans le cadre de `docs/SEO_STRATEGIE_ACQUISITION.md` (§8).
> **Rien de ce qui suit n'a été publié ni envoyé.** Ce sont des brouillons : chaque publication et
> chaque envoi restent à la main de Gabrielle, depuis ses propres comptes.

Un site récent n'a pas encore d'autorité aux yeux des moteurs de recherche : elle se construit par
des mentions et des liens venus d'autres sites. Ce kit donne, pour chaque canal, le texte à copier
et l'endroit où le coller.

## Règles communes

- Les seules affirmations sur Jolene sont celles déjà publiées sur le site : mise en relation
  directe, soignants vérifiés, contrat généré et signé en ligne, pointage, commission de 15 % HT
  sans abonnement, inscription gratuite pour les soignants.
- Aucun chiffre d'activité (nombre de missions, de soignants, d'établissements) tant qu'il n'est
  pas vrai et vérifiable.
- Aucune comparaison avec un concurrent nommé, aucun jugement sur un autre type de prestataire.
- Les chiffres du secteur viennent du baromètre, avec leur source (France Travail, FINESS).
- Dans une fiche publique ou un article, le lien est l'adresse nue de la page, sans paramètre de
  suivi. Dans un email, on peut ajouter `?utm_source=...&utm_medium=email` pour mesurer.
- Lier la page précise plutôt que l'accueil : la page EHPAD pour un site consacré aux EHPAD, le
  baromètre pour un journaliste.

## 1. Moteurs de recherche (à faire en premier)

| Action | Où | Durée |
|---|---|---|
| Soumettre `https://jolene.app/sitemap.xml` | Google Search Console → Sitemaps | 2 min |
| Demander l'indexation des pages ci-dessous | Search Console → Inspection de l'URL → Demander une indexation | 10 min |
| Importer le site depuis la Search Console | Bing Webmaster Tools → Importer | 5 min |

Pages à inspecter en priorité, dans cet ordre :

1. `https://jolene.app/`
2. `https://jolene.app/recruter-soignants`
3. `https://jolene.app/recruter-soignants/ehpad`
4. `https://jolene.app/recruter-soignants/clinique`
5. `https://jolene.app/recruter-soignants/hopital`
6. `https://jolene.app/recruter-soignants/soins-a-domicile`
7. `https://jolene.app/recruter-soignants/handicap`
8. `https://jolene.app/barometre-recrutement-soignants-2026`
9. `https://jolene.app/guides`
10. `https://jolene.app/devenir-soignant`

Bing, Yandex, Seznam et Naver sont prévenus automatiquement des pages ajoutées ou modifiées à
chaque mise en ligne (`scripts/seo/indexnow.mjs`). Google ne suit pas ce protocole : la Search
Console reste nécessaire.

## 2. Fiche d'établissement Google

- **Nom** : Jolene Santé
- **Catégorie** : Éditeur de logiciels (principale). Ne pas choisir une catégorie d'agence
  d'emploi : Jolene est une plateforme de mise en relation.
- **Zone desservie** : France.
- **Site web** : `https://jolene.app`
- **Description** (moins de 750 caractères) :

<!-- texte:fiche-google:750 -->
> Jolene Santé met en relation les établissements de santé et les soignants pour des missions de remplacement : vacations, CDD courts, missions libérales. L'établissement publie son besoin, des soignants dont l'identité et les qualifications ont été vérifiées postulent, et le contrat est généré et signé en ligne. Le soignant pointe son arrivée et son départ depuis l'application. L'inscription est gratuite pour les soignants. Pour les établissements : une commission de 15 % HT sur les missions pourvues, sans abonnement ni frais d'entrée.

## 3. Annuaires de logiciels (Appvizer, Capterra, GetApp)

- **Catégories** : gestion des remplacements, gestion du personnel soignant, planification du
  personnel.
- **Accroche** (moins de 160 caractères) :

<!-- texte:accroche-annuaire:160 -->
> Remplacements en établissement de santé : publiez un besoin, recevez les candidatures de soignants vérifiés, signez le contrat en ligne.

- **Description courte** (moins de 300 caractères) :

<!-- texte:description-courte:300 -->
> Jolene Santé met en relation directe les établissements de santé et les soignants pour des remplacements. Profils vérifiés, contrat généré et signé en ligne, pointage depuis l'application. Commission de 15 % HT sur les missions pourvues, sans abonnement.

- **Description longue** :

> Jolene Santé est une plateforme de mise en relation entre les établissements de santé et
> médico-sociaux (EHPAD, cliniques, hôpitaux, soins à domicile, structures du handicap) et les
> soignants : infirmiers, aides-soignants, accompagnants éducatifs et sociaux, kinésithérapeutes,
> sages-femmes et d'autres professions de santé.
>
> L'établissement crée son espace avec son SIRET et son numéro FINESS, puis publie une mission en
> renseignant la profession, les dates, les horaires et le taux horaire. Les soignants dont
> l'identité et les qualifications ont été vérifiées postulent. L'établissement valide une
> candidature ; le contrat est généré à partir de la mission et signé électroniquement. Le jour de
> la mission, le soignant pointe son arrivée et son départ depuis l'application, et l'établissement
> valide les heures.
>
> L'inscription est gratuite pour les soignants, sans commission prélevée sur leur rémunération.
> Pour les établissements, la commission est de 15 % HT sur les missions pourvues, sans abonnement
> ni engagement.

- **Fonctionnalités à cocher ou à saisir** : publication de missions, vérification des profils,
  génération et signature électronique des contrats, pointage, validation des heures, facturation,
  application mobile.
- **Tarif** : commission de 15 % HT (18 % TTC) sur les missions pourvues. Pas d'abonnement.
- **Lien** : `https://jolene.app/recruter-soignants`

## 4. Page LinkedIn de l'entreprise

- **Slogan** (moins de 220 caractères) :

<!-- texte:slogan-linkedin:220 -->
> Le remplacement en santé, entre établissements et soignants vérifiés. Contrat signé en ligne, commission de 15 % HT sans abonnement.

- **À propos** : reprendre la description longue de la section 3, puis ajouter :

> Jolene publie un baromètre du recrutement de soignants par département, à partir des données
> publiques de France Travail et du répertoire FINESS :
> https://jolene.app/barometre-recrutement-soignants-2026

- **Site web** : `https://jolene.app`
- Fiches App Store et Google Play : vérifier que le champ « site web » pointe vers `https://jolene.app`.

## 5. Le baromètre : la matière à proposer à la presse et aux sites du secteur

Le baromètre réunit, par département, des chiffres publics sur le recrutement des soignants. C'est
la page à proposer à un journaliste ou à un site du secteur : elle leur apporte une donnée locale
sourcée.

Chiffres clés, tels que la page les publie. Ne pas les reformuler : les « au moins » et les « où
cette part peut être calculée » font partie de l'exactitude du chiffre.

<!-- chiffres-barometre:debut -->
- Dans les 101 départements du tableau, les employeurs déclarent au moins 61 987 projets de recrutement d’aides-soignants pour 2026, au moins 36 491 pour les infirmiers et sages-femmes et au moins 8 465 pour les médecins.
- Dans 10 des 53 départements où cette part peut être calculée, au moins 80 % des projets de recrutement d’aides-soignants sont jugés difficiles par les employeurs.
- Parmi ces départements, ceux qui comptent au moins 200 projets et où le recrutement d’aides-soignants est jugé le plus difficile : Corrèze (19), 91 %, Deux-Sèvres (79), 88 %, Loire (42), 86 %, Haute-Savoie (74), 81 % et Charente (16), 77 %.
- Le répertoire FINESS recense 7 398 EHPAD dans ces 101 départements ; ceux qui en comptent le plus sont Nord (59), 251, Bouches-du-Rhône (13), 192 et Loire-Atlantique (44), 182.
<!-- chiffres-barometre:fin -->

Sources à citer avec ces chiffres : enquête Besoins en main-d'œuvre 2026 de France Travail ;
répertoire FINESS. Jolene les a seulement additionnés par département. Un projet de recrutement
est une intention déclarée par un employeur, pas une embauche réalisée.

Pour un journaliste local, relever dans le tableau la ligne de son département (projets
d'aides-soignants, d'infirmiers et sages-femmes, de médecins ; part jugée difficile quand elle est
publiée ; nombre d'EHPAD) et la mettre en tête du message.

### Message à un journaliste (presse locale ou spécialisée)

> **Objet** : Recrutement de soignants en 2026 : les chiffres de [département]
>
> Bonjour [prénom],
>
> Je me permets de vous signaler un tableau qui peut vous servir pour un sujet sur le recrutement
> des soignants dans [département].
>
> Pour 2026, les employeurs du département déclarent [chiffre du tableau] projets de recrutement
> d'aides-soignants [si la part est publiée : dont [part] % qu'ils jugent difficiles]. Le
> département compte [nombre] EHPAD.
>
> Ces chiffres viennent de l'enquête Besoins en main-d'œuvre de France Travail et du répertoire
> FINESS. Nous les avons réunis département par département, avec la méthode et les limites de
> lecture : https://jolene.app/barometre-recrutement-soignants-2026
>
> Je dirige Jolene Santé, une plateforme de mise en relation entre établissements de santé et
> soignants pour les remplacements. Je peux répondre à vos questions sur ces chiffres.
>
> Bien cordialement,
> Gabrielle [nom], fondatrice de Jolene Santé
> [téléphone]

Avant l'envoi : remplacer chaque crochet par la valeur lue dans le tableau. Si le tableau affiche
« ≥ » devant le nombre de projets, écrire « au moins ». S'il affiche « n.c. » pour la part,
supprimer la mention de la part.

### Message à un site qui recense les plateformes de remplacement

> **Objet** : Jolene Santé, une plateforme à ajouter à votre article
>
> Bonjour,
>
> Votre article [titre] recense les plateformes de remplacement en santé. Jolene Santé n'y figure
> pas encore ; voici de quoi l'ajouter si vous le jugez utile.
>
> - Ce que c'est : une plateforme de mise en relation directe entre établissements de santé et
>   soignants (infirmiers, aides-soignants, AES, kinésithérapeutes, sages-femmes et d'autres
>   professions).
> - Pour les établissements : commission de 15 % HT sur les missions pourvues, sans abonnement.
> - Pour les soignants : inscription gratuite, sans commission sur la rémunération.
> - Contrat généré et signé en ligne, pointage depuis l'application.
> - Présentation : https://jolene.app/recruter-soignants ; tarifs : https://jolene.app/tarifs
>
> Je reste à votre disposition pour toute précision.
>
> Bien cordialement,
> Gabrielle [nom], fondatrice de Jolene Santé

### Message à un institut de formation (IFSI, IFAS)

> **Objet** : Deux guides pour vos étudiants et jeunes diplômés
>
> Bonjour,
>
> Nous avons publié deux guides pratiques, en accès libre, qui peuvent être utiles à vos jeunes
> diplômés : une check-list pour une première mission de remplacement et un guide sur les vacations
> en établissement.
>
> - https://jolene.app/guides/premiere-mission-de-remplacement
> - https://jolene.app/guides/vacations-etablissement-de-sante
>
> Si vous tenez une page de ressources ou un espace pour vos anciens élèves, vous pouvez les y
> relayer librement.
>
> Bien cordialement,
> Gabrielle [nom], fondatrice de Jolene Santé

## 6. Suivi

Tenir une liste simple : site contacté, date, réponse, lien obtenu (oui ou non, adresse de la page).
Dans la Search Console, le rapport « Liens » montre au bout de quelques semaines les sites qui
pointent vers `jolene.app`.

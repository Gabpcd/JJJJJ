# Stratégie SEO d'acquisition — Jolene Santé

> Rédigée le 20/11/2026. Remplace la feuille de route de `docs/PERF_SEO_STRATEGIE.md` (juin 2026)
> pour la partie SEO. Décisions prises par Claude sur délégation de Gabrielle (« applique toute une
> stratégie », 20/11/2026) ; les points qui restent à sa main sont listés au §8.

## 1. Constat au 20/11/2026

### 1.1 Le marché

| Acteur | Position observée (sources publiques, novembre 2026) |
|---|---|
| Hublo | Acteur installé depuis 2016, accord-cadre Resah 2025-2029, très présent sur les requêtes de marque et « remplacement soignant ». |
| Mediflash, Brigad | Places de marché orientées soignants indépendants. |
| Florence, Medelse, Staffmatch | Applications de missions, surtout Île-de-France et grandes métropoles. |
| Appel Médical, Adecco Medical, Vitalis Médical | Agences d'intérim : elles occupent les requêtes « vacation » et « intérim » avec leurs offres d'emploi. |
| Kosme (Rennes), Relaisanté | Nouveaux entrants financés en 2026. |
| lonasante.com, sosehpad.com, softrh.fr, appines.fr, blog Skello | Sites de contenu qui captent les requêtes « avis », « comparatif », « comment trouver des vacations ». |

Aucun chiffre de volume de recherche n'est avancé ici : nous n'avons pas d'outil de mots-clés
(Semrush, Ahrefs). Les priorités sont fondées sur l'intention des requêtes et sur ce que les pages
de résultats montrent, pas sur des volumes inventés. La Search Console (domaine vérifié par DNS)
donnera les vrais chiffres : voir §7.

### 1.2 Le site

Vérifié en lisant ce que les robots reçoivent réellement de `https://jolene.app` :

1. **Canonical faux sur toutes les pages non prérendues.** Le HTML brut de `/tarifs`, `/aide`,
   `/a-propos`, `/infirmiere-liberale`, `/telecharger`, `/contact`, `/mission/:id` et des pages légales
   déclare `<link rel="canonical" href="https://jolene.app/">` (celui de l'accueil, hérité du
   squelette). Le JavaScript le corrige ensuite, mais Google peut retenir le canonical du HTML brut :
   ces pages risquent d'être traitées comme des doublons de l'accueil. Les pages mission
   (`JobPosting`, Google for Jobs) sont concernées.
2. **Accueil vide sans JavaScript.** `/` ne contient ni H1 ni texte dans le HTML brut. Bing, et les
   robots des assistants IA (ChatGPT, Perplexity, Claude) qui n'exécutent pas le JavaScript, ne
   voient rien de la page la plus importante.
3. **Pages infirmier non indexées.** Les 30 pages « Infirmier (IDE) à {ville} » sont en `noindex`
   faute de donnée locale propre. C'est le métier le plus recherché.
4. **Aucune page pour les établissements au-delà de `/recruter-soignants`.** Or ce sont eux qui
   paient la commission.
5. **Aucun contenu éditorial** (pas de guides) : rien pour les requêtes en question, rien à citer
   pour un assistant IA, rien à relayer pour obtenir des liens.
6. **Titres trop longs** sur les pages métier (jusqu'à 90 caractères, tronqués dans les résultats).
7. **Aucune présence hors site** détectée : la marque « Jolene Santé » ne remonte sur aucune page
   tierce. L'autorité du domaine est à construire.

Ce qui est déjà bon (PR #1115) : 297 pages statiques ville, métier et ville × métier, sitemap,
`JobPosting` sur les missions publiques, attribution de l'inscription à la page d'arrivée
(`landing_path`).

### 1.3 L'activité réelle

En base de production : une vingtaine de comptes réels (dont 2 établissements), aucune mission
ouverte. Le reste des comptes vient des tests automatisés. Conséquence directe pour la stratégie :

- le chiffre d'affaires vient de la commission sur les missions pourvues, donc **des établissements
  qui publient**. Le SEO doit d'abord parler à eux ;
- un soignant qui arrive sur une page sans mission doit pouvoir s'inscrire pour être prévenu, sinon
  la visite est perdue ;
- le SEO met plusieurs mois à produire. Il se construit maintenant pour être en place quand la
  prospection directe (agents de croissance, #1116) aura amené les premiers établissements. Il ne
  remplace pas cette prospection.

## 2. Positionnement

Jolene ne peut pas battre Hublo sur « remplacement soignant » ni les agences sur « intérim
infirmier » à court terme. Les angles où un nouveau domaine peut se placer :

1. **Local et précis** : « aide-soignant Brest », « infirmier Reims », avec des chiffres propres à
   chaque ville (établissements recensés par FINESS, tensions de recrutement BMO). Les concurrents
   ont des pages locales génériques.
2. **Établissement par type** : EHPAD, clinique, hôpital public, soins à domicile, handicap. Chaque
   type a ses contraintes ; une page qui en parle avec précision convertit mieux qu'une page
   générique.
3. **Transparence du prix** : 15 % HT, sans abonnement, publié. C'est un argument rare dans ce
   marché et il répond aux requêtes sur le coût du remplacement.
4. **Données publiques** : un baromètre par département (BMO + FINESS) que la presse locale et les
   blogs du secteur peuvent citer. C'est le moyen le plus réaliste d'obtenir des liens.
5. **Jamais sous l'angle de l'intérim** : Jolene n'est pas une entreprise de travail temporaire.
   Le mot n'apparaît que pour dire cette différence, sur les pages faites pour l'expliquer.

## 3. Architecture cible

```
/                                   accueil (HTML statique complet)
/recruter-soignants                 pilier établissements
  /recruter-soignants/ehpad         1 page par type d'établissement
  /recruter-soignants/clinique
  /recruter-soignants/hopital
  /recruter-soignants/soins-a-domicile
  /recruter-soignants/handicap
/devenir-soignant                   pilier soignants
/metier/<métier>                    15 pages métier
/emploi-soignant/<ville>            100 pages ville (chiffres FINESS propres)
/emploi-soignant/<ville>/<métier>   180 pages, indexées seulement avec une donnée BMO du métier
/barometre-recrutement-soignants-2026   tableau par département (BMO + FINESS)
/guides                             sommaire des guides
  /guides/<sujet>                   guides soignants et établissements
/tarifs /a-propos /infirmiere-liberale /telecharger /aide   HTML statique, canonical propre
/mission/<id>                       JobPosting (canonical corrigé)
```

Règles de maillage : chaque guide renvoie vers un pilier et vers deux ou trois pages métier ou
type d'établissement ; chaque page ville renvoie vers ses pages métier et vers le baromètre ; le
pied de page des pages publiques liste les piliers, les guides et le baromètre.

Source de vérité unique : `src/lib/seo-routes.ts` (titres, descriptions, H1, contenu statique,
indexabilité, données structurées), lue par les composants React et par
`scripts/seo/generer-pages-statiques.mjs`.

## 4. Lot 1 — fondations techniques (fait, PR #1169)

| # | Chantier | Effet attendu |
|---|---|---|
| 1 | Squelette neutre `app.html` (sans canonical) pour les routes de l'application, écrit par le build Vite ; `vercel.json` y renvoie | Plus aucun canonical faux |
| 2 | Accueil, `/tarifs`, `/a-propos`, `/infirmiere-liberale`, `/telecharger`, `/aide` en HTML statique avec leur propre `<head>` | Pages lisibles sans JavaScript, canonical correct |
| 3 | Données structurées dans le HTML statique : `WebSite`, `BreadcrumbList`, `FAQPage` | Compréhension de la structure du site, réponses reprises par les assistants IA |
| 4 | Titres des pages métier raccourcis | Titres non tronqués |
| 5 | `robots.txt` nettoyé, `llms.txt` généré | Signal clair pour les robots, y compris IA |
| 6 | Titre rendu de l'accueil et de `/tarifs` (il devenait « Jolene — Jolene » après chargement), 404 en `noindex`, `/inscription/*` hors sitemap | Titres corrects dans les résultats, pas de page d'erreur indexée |

## 5. Lot 2 — pages et contenus (fait)

| # | Chantier | Cible |
|---|---|---|
| 1 | Chiffres FINESS par ville (EHPAD, SSIAD, MAS/FAM, IME, centres de santé) sur les 100 pages ville et les 180 pages ville × métier | Soignants, requêtes locales |
| 2 | Donnée BMO « Infirmiers et sages-femmes » sur les 30 pages infirmier, qui deviennent indexables (90 pages ville × métier indexées au lieu de 60) ; parts « jugées difficiles » recalculées pour tous les métiers (voir plus bas) | Soignants, requêtes infirmier × ville |
| 3 | 5 pages par type d'établissement : `/recruter-soignants/{ehpad,clinique,hopital,soins-a-domicile,handicap}` | Directions d'établissement, cadres de santé |
| 4 | Baromètre 2026 par département : `/barometre-recrutement-soignants-2026` | Presse locale, blogs du secteur (liens) |
| 5 | 4 guides sous `/guides` (3 soignants, 1 établissement) | Requêtes en question, assistants IA |
| 6 | État vide des listes de missions : invitation à créer un compte pour retrouver la recherche | Conversion des visites tant que l'offre est faible |
| 7 | Promesses et jugements sans source retirés de l'accueil et de `/recruter-soignants` (« première mission possible dès aujourd'hui », « 20-30 % de marge », « opérationnel en 10 minutes », « aucune garantie sur les qualifications ») | Cohérence avec la réalité de l'offre |

**Deux corrections de fond issues de la revue B8 de #1170**

1. **Parts BMO fausses, en ligne depuis #1115.** L'enquête est publiée par bassin d'emploi, et le
   fichier masque certaines valeurs par un astérisque. L'ancien calcul retirait ces bassins du
   dénominateur tout en gardant leurs projets dans le total : la part « jugée difficile » affichée
   pouvait dépasser toute valeur possible (Reims, infirmiers : 83 % affichés pour 71 à 73 %
   possibles). Désormais `scripts/seo/extraire-bmo.mjs` relit le classeur officiel : le total est
   dit « au moins » quand une valeur est masquée, et la part n'est donnée que si aucune ne l'est
   (53 départements pour les aides-soignants, 43 pour les infirmiers et sages-femmes, 29 pour les
   médecins). Ailleurs la page donne le nombre de projets, sans part.
2. **Hôpitaux retirés des comptes FINESS.** La catégorie « centres hospitaliers » compte aussi des
   hôpitaux de jour, des CMP et des centres de dépistage, et pas la psychiatrie spécialisée :
   « N sites hospitaliers » aurait été lu comme un nombre d'hôpitaux. Les villes sont maintenant
   reconnues par leur code commune (un CEDEX porte le nom de la grande ville voisine).

Où cela vit dans le code :

| Quoi | Fichier |
|---|---|
| Pages par type d'établissement (textes) | `src/lib/seo-contenu/etablissements.ts` |
| Guides (textes, sources officielles) | `src/lib/seo-contenu/guides.ts` |
| Comptes FINESS (données) | `src/lib/seo-finess.json`, produit par `node scripts/seo/extraire-finess.mjs` |
| Données BMO (données) | `src/lib/seo-bmo-2026.json`, produit par `node scripts/seo/extraire-bmo.mjs` (AS et MEDECIN : catégories exactes ; IDE : agrégat « Infirmiers et sages-femmes ») |
| Titres, descriptions, structure, indexabilité, données structurées | `src/lib/seo-routes.ts` |
| Rendu commun (page affichée) | `src/components/ContenuSEO.tsx` |
| Rendu commun (HTML statique), sitemap, llms.txt | `scripts/seo/generer-pages-statiques.mjs` |

Ajouter un guide : une entrée dans `GUIDES_SEO`, rien d'autre. La route, le HTML statique, le
sitemap (avec `lastmod` = date de révision), le sommaire `/guides` et les liens des piliers suivent.

Rafraîchir les chiffres FINESS : `node scripts/seo/extraire-finess.mjs` (lit le fichier officiel en
flux, n'écrit que le JSON). La réexposition data.gouv.fr utilisée est archivée : au prochain
rafraîchissement, brancher le script sur l'extraction officielle du même jeu de données.

Règles éditoriales des guides :

- vouvoiement, ton sobre, phrases complètes ;
- aucune promesse de volume (« des centaines de missions ») tant que ce n'est pas vrai ;
- aucun chiffre sans source publique nommée ;
- aucune règle de droit affirmée par Jolene : sur le cumul d'activités, les statuts ou les
  contrats, le guide décrit le fonctionnement de la plateforme et renvoie vers la fiche officielle
  (service-public.fr, URSSAF, Ordre) ;
- les seules affirmations sur le produit sont celles déjà publiées sur le site (commission,
  vérifications, contrats, pointage, DPAE transmise par l'établissement) ;
- des conseils, pas des constats sur le secteur (« les besoins sont fréquents ») ;
- rien sur l'intérim, aucune comparaison de Jolene avec un autre type de prestataire, aucun
  exemple de prix : ces sujets attendent la validation de Gabrielle (voir §6).

Ces règles sont gardées par des tests (`src/lib/seo-contenus.test.ts`, `src/lib/seo-routes.test.ts`) :
aucun chiffre dans un guide hors tarif publié, aucun pourcentage hors 15 %, 18 % et 20 % sur les
pages établissement, sources officielles en `service-public.gouv.fr` ou `data.gouv.fr` seulement,
vouvoiement, aucune promesse de volume ni de délai, aucune généralité (« souvent », « nombreux »),
aucun lien interne cassé, chaque chiffre clé du baromètre recalculé depuis son tableau, pas plus de
40 % de texte commun entre deux pages par type d'établissement.

## 5 bis. Lot 3 — premier chargement, guides, signalement aux moteurs, kit hors site

| # | Chantier | Effet |
|---|---|---|
| 1 | **Premier chargement presque divisé par deux.** Toutes les pages, accueil compris, chargeaient jsPDF et recharts avant de s'afficher : 560 Ko compressés en production, dont 257 inutiles hors des écrans de factures et de graphiques. Cause : un groupe de découpage emporte aussi les dépendances de ses modules ; `clsx` et `prop-types` étaient partis avec recharts, l'assistant de préchargement de Vite et les assistants de compilation avec jsPDF. Le groupe `vendor-commun` (`vite.config.ts`) les en sort : environ 305 Ko attendus en production. Les espaces connectés y gagnent aussi : jsPDF n'est plus chargé que par les quatre écrans qui produisent un PDF (douze blocs l'importaient, dont le cadre commun `LayoutApp` et les tableaux de bord). | Pages plus rapides sur mobile, pour les visiteurs comme pour l'application |
| 2 | Garde : à la fin de `npm run build`, `scripts/ci/verifier-premier-chargement.mjs` échoue si une de ces bibliothèques revient dans la chaîne de l'entrée ou de `LayoutApp` ; dans `validate-pr`, il contrôle en plus un budget de 235 Ko compressés | Le défaut, invisible en recette, ne peut pas revenir en silence |
| 3 | Quatre guides : un pour les infirmiers, trois pour les établissements (rédiger une annonce, accueillir un remplaçant, anticiper les congés) | Les établissements, qui paient la commission, ont désormais autant de guides que les soignants |
| 4 | Signalement IndexNow (`scripts/seo/indexnow.mjs`, workflow `indexnow.yml`) : après un déploiement de production, les pages ajoutées, modifiées ou supprimées sont signalées à Bing, Yandex, Seznam et Naver. Le changement se lit dans `src/lib/seo-empreintes.json` (une empreinte du contenu par page, `npm run seo:empreintes`) | Découverte en heures plutôt qu'en semaines sur Bing, qui alimente aussi Copilot, DuckDuckGo et la recherche de ChatGPT. Google ne suit pas ce protocole |
| 5 | `docs/SEO_KIT_HORS_SITE.md` : textes prêts à l'emploi pour la fiche Google, les annuaires de logiciels, LinkedIn, et trois messages types (presse, sites du secteur, instituts de formation) | Brouillons seulement : rien n'a été publié ni envoyé |

Ce qui est envoyé à IndexNow : l'hôte, la clé et les adresses des pages changées. La clé est
publique par construction (`public/jolene-sante-indexnow-2026.txt`) ; ce n'est pas un secret. Le
protocole demande de ne signaler que ce qui change (indexnow.org/faq : « Submit only when content
has changed ») : seules les adresses dont l'empreinte diffère du commit précédent partent. Le
premier signalement, faute de point de comparaison, porte sur toutes les pages : c'est le cas que
le protocole admet après une refonte, et les lots 1 à 3 en sont une. Un envoi manqué (déploiement
non confirmé, service indisponible) n'est pas rattrapé par la mise en ligne suivante : il faut
relancer l'exécution dans GitHub Actions. Pour arrêter le signalement : désactiver le workflow dans
GitHub, ou supprimer le fichier de clé.

Mesures du 20/11/2026, scripts de module chargés avant affichage, compressés en gzip niveau 6 :

| Build | Avant | Après |
|---|---|---|
| Production (Vercel, suivi d'erreurs embarqué) | 559 969 octets, 45 fichiers (lu sur `jolene.app`) | 296 401 octets sur le build de prévisualisation ; environ 305 000 attendus en production, qui ajoute des identifiants de débogage (à relire sur `jolene.app` après mise en ligne) |
| Local, simulation de la CI, variante mobile | 460 739 octets, 26 fichiers | 204 577 octets, 24 fichiers |

Piste non traitée : en production, l'entrée pèse 99 Ko contre 34 en local, parce que le suivi
d'erreurs y est chargé d'emblée. Le charger à la demande ferait encore gagner du poids, mais
change le moment où les erreurs commencent à être captées : à décider à part.

## 6. Lots suivants (non faits dans cette vague)

1. **Simulateur de coût d'un remplacement** (page outil pour les établissements).
2. **Pages mission servies en HTML statique** (fonction edge) pour Google for Jobs, dès que des
   missions sont publiées régulièrement.
3. **Deux guides établissement écrits puis retirés du lot 2**, à valider par Gabrielle avant
   publication (HARD STOP n°4) :
   - « Vivier interne, agence d'intérim, plateforme : comparer les solutions » : il décrit le
     cadre légal de l'intérim et compare Jolene à des tiers ;
   - « Combien coûte le remplacement d'un soignant ? » : son exemple chiffré appliquait 15 % à
     « heures × taux », alors que la plateforme calcule la commission sur le brut total (base +
     indemnité de fin de contrat + congés payés). **Écart à trancher** : le contrat de service
     §4.3 (`src/constantes/contratServiceEtablissement.ts`) dit « heures travaillées multipliées
     par le taux horaire, majorations incluses », la FAQ de l'accueil dit « majorations et
     indemnités incluses », l'écran de décomposition affiche « base + IFM + ICP ».
4. **Guides juridiques** (cumul d'activités, CDD de remplacement, exercice libéral en
   établissement) : chaque texte part en PR avec ses sources primaires et attend la validation de
   Gabrielle (HARD STOP n°4). La FAQ de `/devenir-soignant` répond « Oui » à « Puis-je cumuler
   avec mon emploi actuel ? » : à relire dans le même mouvement.
5. **Pages comparatives nommant des concurrents** : seulement après validation, avec des faits
   vérifiables et datés (publicité comparative).
6. **Pages par département** si le baromètre obtient du trafic.
7. **Mesure d'audience sans cookie** (à décider : touche au consentement).
8. **Calcul BMO de l'outil interne : corrigé dans le code (PR #1171), données à relancer.** L'import
   n'enregistre plus la part « jugés difficiles » dès qu'un bassin est masqué. Reste à la main de
   Gabrielle : relancer l'import (Admin → Acquisition → « Synchroniser BMO + BOAMP »), après avoir
   décidé du score de tension du radar, qui lit une part vide comme 0 % (correction en B9).
9. **Vérification des données hors CI.** `npm run seo:donnees:verifier` compare les deux JSON aux
   fichiers officiels ; il interroge le réseau et se lance à la main, pas dans la CI.
10. **Poids du module `seo-routes`** : environ 26 Ko compressés, chargés par l'accueil. Laissé tel
   quel : le gain serait dix fois moindre que celui du lot 3 (§5 bis), pour un découpage risqué.
11. **Score de tension du radar d'acquisition** (`fn_admin_acquisition_cibles`,
   `fn_admin_acquisition_radar_externe`) : distinguer « part non publiée » de « part nulle ».
   Fonctions SECURITY DEFINER, donc accord explicite de Gabrielle (B9).

## 7. Mesure

- **Search Console** (domaine vérifié) : impressions, clics, pages indexées, requêtes. C'est la
  seule source fiable ; Claude n'y a pas accès.
- **Attribution interne** : `landing_path` et UTM `utm_source=seo` enregistrés à l'inscription.
- Indicateurs à suivre chaque mois : pages indexées, impressions, clics, inscriptions soignants et
  établissements dont la page d'arrivée est une page SEO, missions publiées par ces établissements.
- Délai réaliste : indexation des nouvelles pages en 2 à 6 semaines, premières positions utiles
  sur les requêtes locales en 2 à 4 mois, effet des guides en 3 à 6 mois.

## 8. Ce qui reste à la main de Gabrielle

Textes prêts à copier pour chacune de ces actions : `docs/SEO_KIT_HORS_SITE.md`.

Ces actions engagent la marque à l'extérieur ou demandent ses identifiants :

1. **Search Console** : soumettre `https://jolene.app/sitemap.xml`, puis demander l'indexation de
   l'accueil, de `/recruter-soignants` et des cinq pages par type d'établissement.
2. **Bing Webmaster Tools** : importer le site depuis la Search Console (Bing alimente ChatGPT et
   Copilot).
3. **Fiche d'établissement Google** au nom de Jolene Santé.
4. **Liens entrants**, par ordre d'intérêt :
   - annuaires de logiciels B2B (Appvizer, Capterra) : fiche « gestion des remplacements » ;
   - sites de contenu du secteur qui comparent les plateformes (lonasante.com, sosehpad.com,
     softrh.fr) : demander l'ajout de Jolene ;
   - presse locale et spécialisée avec le baromètre par département comme matière ;
   - page entreprise LinkedIn, fiches App Store et Google Play : lien vers `https://jolene.app`.
5. **Prospection des établissements** : valider les brouillons des agents de croissance. C'est le
   levier le plus rapide vers les premières missions, donc vers le premier chiffre d'affaires.

## 9. Ce que l'on ne fait pas

- Pas de pages générées en masse sans donnée propre (100 villes × 17 métiers) : risque de pages
  satellites, déjà écarté en revue de #1115.
- Pas de chiffres d'activité inventés, pas de faux avis, pas de témoignages fictifs.
- Pas de texte présentant Jolene comme une agence d'intérim.
- Pas d'achat de liens.

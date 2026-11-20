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

## 4. Lot 1 — fondations techniques

| # | Chantier | Effet attendu |
|---|---|---|
| 1 | Squelette neutre `app.html` (sans canonical) pour les routes de l'application ; `vercel.json` y renvoie | Plus aucun canonical faux |
| 2 | Accueil, `/tarifs`, `/a-propos`, `/infirmiere-liberale`, `/telecharger`, `/aide` en HTML statique avec leur propre `<head>` | Pages lisibles sans JavaScript, canonical correct |
| 3 | Données structurées dans le HTML statique : `WebSite`, `BreadcrumbList`, `FAQPage` | Compréhension de la structure du site, réponses reprises par les assistants IA |
| 4 | Titres des pages métier raccourcis | Titres non tronqués |
| 5 | `robots.txt` nettoyé, `llms.txt` généré | Signal clair pour les robots, y compris IA |

## 5. Lot 2 — pages et contenus

| # | Chantier | Cible |
|---|---|---|
| 1 | Chiffres FINESS par ville (EHPAD, sites hospitaliers publics, SSIAD, HAD, MAS/FAM, IME, centres de santé) sur les pages ville et ville × métier | Soignants, requêtes locales |
| 2 | Donnée BMO « Infirmiers et sages-femmes » sur les pages infirmier, qui deviennent indexables | Soignants, requêtes infirmier × ville |
| 3 | 5 pages par type d'établissement | Directions d'établissement, cadres de santé |
| 4 | Baromètre 2026 par département | Presse locale, blogs du secteur (liens) |
| 5 | Premiers guides (soignants et établissements) | Requêtes en question, assistants IA |
| 6 | État vide des listes de missions : invitation à s'inscrire pour être prévenu | Conversion des visites tant que l'offre est faible |

Règles éditoriales des guides :

- vouvoiement, ton sobre, phrases complètes ;
- aucune promesse de volume (« des centaines de missions ») tant que ce n'est pas vrai ;
- aucun chiffre sans source publique nommée ;
- aucune règle de droit affirmée par Jolene : sur le cumul d'activités, les statuts ou les
  contrats, le guide décrit le fonctionnement de la plateforme et renvoie vers la fiche officielle
  (service-public.fr, URSSAF, Ordre) ;
- les seules affirmations sur le produit sont celles déjà publiées sur le site (commission,
  vérifications, contrats, pointage, DPAE transmise par l'établissement).

## 6. Lots suivants (non faits dans cette vague)

1. **Simulateur de coût d'un remplacement** (page outil pour les établissements).
2. **Pages mission servies en HTML statique** (fonction edge) pour Google for Jobs, dès que des
   missions sont publiées régulièrement.
3. **Guides juridiques** (cumul d'activités, CDD de remplacement, exercice libéral en
   établissement) : chaque texte part en PR avec ses sources primaires et attend la validation de
   Gabrielle (HARD STOP n°4).
4. **Pages comparatives nommant des concurrents** : seulement après validation, avec des faits
   vérifiables et datés (publicité comparative).
5. **Pages par département** si le baromètre obtient du trafic.
6. **Mesure d'audience sans cookie** (à décider : touche au consentement).

## 7. Mesure

- **Search Console** (domaine vérifié) : impressions, clics, pages indexées, requêtes. C'est la
  seule source fiable ; Claude n'y a pas accès.
- **Attribution interne** : `landing_path` et UTM `utm_source=seo` enregistrés à l'inscription.
- Indicateurs à suivre chaque mois : pages indexées, impressions, clics, inscriptions soignants et
  établissements dont la page d'arrivée est une page SEO, missions publiées par ces établissements.
- Délai réaliste : indexation des nouvelles pages en 2 à 6 semaines, premières positions utiles
  sur les requêtes locales en 2 à 4 mois, effet des guides en 3 à 6 mois.

## 8. Ce qui reste à la main de Gabrielle

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

# Agents de croissance — diagnostic, plan et exploitation

> 08/11/2026. Demande de Gabrielle : « mettre en place des agents pour acquérir du
> trafic, des clients, et faire remplir les missions ». Ce document complète
> `STRATEGIE_GROWTH_SERIE_A.md`, `STRATEGIE_LANCEMENT_PILOTE.md` et
> `STRATEGIE_PRODUIT_ACQUISITION.md` sans les remplacer.

## 1. Diagnostic (prod, cohorte réelle, comptes de test exclus)

| Indicateur | Valeur au 08/11 |
|---|---:|
| Soignants réels inscrits | 2 (2 → 6 octobre), 0 sur les 30 derniers jours |
| Soignants réels avec documents validés | 1 |
| Établissements réels inscrits | 0 |
| Missions réelles publiées / pourvues / terminées | 0 / 0 / 0 |
| Comptes créés en 30 jours (toutes cohortes) | 1 251, dont 3 hors fixtures CI |
| Prospects établissements (FINESS) | 64 058, dont 30 633 avec email et 55 989 avec téléphone |
| Prospects établissements déjà contactés | 0 |
| Prospects soignants (RPPS) | 1 893 868, dont 170 886 avec email : **inutilisables en prospection froide** (§5) |
| Recommandations radar en attente | 913, toutes en BROUILLON depuis juillet |
| Contacts CRM | 5 |
| Mesure d'audience | aucune : Vercel Web Analytics non activé, aucun traceur |

Les inscriptions publiques sont ouvertes depuis le 25/09 (`inscriptions_publiques_actives=1`).
Le problème n'est pas le produit : **personne n'a encore été contacté**.

État des automatismes :
- **Actifs, sans envoi** : `relance-soignants-inactifs`, `digest-hebdo-soignants` et
  `avis-parrainage-post-mission` tournent mais répondent « ignoré » tant que
  `growth_config.automatisations_marketing_actives=false`.
- **En pause depuis le 29/07** (saturation CPU, `20260729121442`) :
  `jolene_acquisition_brouillons`, `jolene_crm_generer_taches`, `jolene_sourcing_*_hebdo`,
  `jolene_acquisition_boamp_quotidien`, `jolene_acquisition_bmo_mensuel`,
  `jolene_prospection_compteurs_quotidien`.
- **Supprimés** : `enrich-prospects-etab`, `enrich-prospects-soignant`, `jolene_sourcing_rpps_watchdog`.

Dettes repérées pendant le diagnostic (hors périmètre de cette PR) :
- `fn_admin_generer_posts` (onglet « Posts de la semaine ») compte aussi les missions de test.
- `sales-outreach` envoie un contenu libre sans vérifier `growth_config` ; `relance-inactifs` et
  `digest-hebdo` ignorent `preferences_notifications`. Aucun lien de désinscription en 1 clic ni
  d'en-tête `List-Unsubscribe` n'existe. Les réponses STOP sont saisies à la main.
- Les pages SEO sont une SPA sans prérendu. Le sitemap est figé au 15/06, et un slug inconnu
  est indexable (soft-404). C'est traité dans une PR SEO séparée.

## 2. Plan de croissance priorisé

Règle d'or inchangée : **densité avant étendue**. Les marchés pilotes sont Paris/92 et Lorient/56.
La demande (établissements) passe avant l'offre : un soignant inscrit sans mission repart.

### Établissements (priorité 1)

| Canal | Effort | Impact attendu | Délai |
|---|---|---|---|
| Emails B2B personnalisés via l'agent de prospection : 20 par jour, envoyés depuis le Gmail de la fondatrice, séquence J+3/J+7/J+14 | 20 min/j | Établissements de 75/92/56 joignables par une adresse classique (les adresses MSSanté sont exclues, §4) ; 2 à 4 % de réponses positives attendues | 1-4 semaines |
| Appels ciblés : liste hebdomadaire de 30 fiches d'appel préparée par l'agent (§4 bis), puis rappels dans « Actions du jour » | 30 min/j | Le meilleur taux de conversion B2B santé ; seul canal ouvert tant que les adresses des cibles sont en messagerie fermée | chaque lundi |
| Concierge première mission : publier au téléphone avec l'établissement | 15 min par établissement | Lève le blocage « première mission » | immédiat |
| Signaux BOAMP et France Travail : bonus de score dans l'agent | 0 (réactivation des imports) | Cible les établissements qui recrutent déjà | après go |
| Sièges de groupes (EMEIS, Korian, mutualistes) en direct | élevé | Fort, mais cycle long | 2-6 mois |
| Partenariats IFSI/IFAS (899 écoles, inclus dans l'agent) | faible | Flux de jeunes diplômés | rentrée, remises de diplômes |

### Soignants (priorité 2, à caler sur la demande réelle)

| Canal | Effort | Impact attendu | Délai |
|---|---|---|---|
| Posts hebdomadaires dans les groupes Facebook (93 groupes AS/IDE recensés), via l'agent | 15 min/sem | Le canal le moins cher au lancement | immédiat |
| SEO ville × métier avec HTML statique crawlable (PR séparée) | fait | Trafic organique durable | 4-12 semaines (indexation) |
| Post LinkedIn hebdomadaire de la fondatrice (cible directions) | 10 min/sem | Notoriété, crédibilité B2B | continu |
| Parrainage soignant (existant) | 0 | Fort une fois les premières missions payées | après 1res missions |
| Réactivation des inscrits bloqués (agent) | 5 min/j | Débloque l'étape documents | immédiat |
| Publicité payante | budget | À n'engager qu'une fois un marché aux seuils du cockpit | pas avant liquidité |

### Remplissage des missions

| Mécanisme | État |
|---|---|
| Vagues de notification urgentes, matching inversé des disponibilités, relance des missions sans candidat | actifs en prod |
| Agent « missions à pourvoir » : post prêt à partager pour chaque mission réelle ouverte depuis plus de 6 h sans candidature | livré, brouillons seulement |
| Appel des soignants vérifiés du même métier (le compte figure dans le brouillon) | manuel |

## 3. Veille concurrentielle (courte, sources partielles)

- **Hublo** (ex-Whoog + medGo) : logiciel de pool interne. Il aurait été refinancé de 40 M€
  en février 2026 (BeBeez, article non consultable). C'est un SaaS : il n'apporte pas de
  soignants. Il faut le compléter, pas l'affronter.
- **Mediflash** : marketplace de freelances (EHPAD, cliniques), avec une prospection terrain.
  Il est critiqué sur le risque de requalification.
- **Brigad** : freelances multi-secteurs avec une offre santé ; base large, santé secondaire.
- **Medelse**, **Click&Care** : plateformes établies ; financement non vérifié.
- **Nouveaux entrants 2025-2026** : aucun n'a été trouvé dans les sources accessibles. Les
  « apps vibe-codées » sont probablement trop jeunes pour être indexées. L'écart à combler est
  la distribution, pas les fonctionnalités.
- **Contexte réglementaire** :
  - Décret 2025-1147 : 24 mois d'exercice hors intérim avant toute mise à disposition par une ETT.
  - Plafond de dépenses d'intérim (décret 2025-612) : 54 € HT/h pour un IDE.
  - Ces deux textes pourraient être un argument pour la vacation directe. **À instruire en
    HARD STOP n°4** avant toute mention publique.

## 4. Agents livrés (`20261109140000_agents_croissance_brouillons.sql`)

Ce sont cinq routines SQL quotidiennes (la cinquième, la liste d'appels, date du 24/11/2026 : §4 bis),
plus un rapport hebdomadaire. **Aucune n'envoie quoi que ce soit ni n'appelle personne** : ni pg_net,
ni Resend, ni SMS, ni téléphonie, ni publication. Elles n'appellent pas de LLM, donc ne coûtent rien
en tokens.

Les deux crons (`jolene_growth_agents_quotidien`, `jolene_growth_rapport_hebdo`) sont créés
**désactivés**, en production comme sur le staging, qui doit rester sans cron actif. La fondatrice
les active depuis l'onglet Agents (« Activer la préparation automatique »). Ce bouton appelle
`fn_admin_growth_planification(true)` et ne demande aucun SQL manuel en production.
« Préparer maintenant » lance les agents à la demande, que la préparation automatique soit active
ou non.

| Agent | Quand | Produit |
|---|---|---|
| Prospection établissements | chaque jour à 05:50 UTC, une fois activé | Jusqu'à 20 premiers emails par jour (file plafonnée à 60), plus les relances étapes 2 et 3 des contacts CRM échus. Détail ci-dessous. |
| Appels établissements | chaque jour, dans la limite de la semaine | Jusqu'à 30 fiches d'appel par semaine (file plafonnée à 60) : nom, numéro, raisons du classement, script modifiable. Détail au §4 bis. |
| Posts sociaux | chaque jour (idempotent à la semaine) | 1 post Facebook par département × {AS, IDE} et 1 post LinkedIn par semaine. Chiffres réels : missions ouvertes réelles, ou à défaut données BMO publiques. Groupes suggérés. |
| Missions à pourvoir | chaque jour | 1 post par mission réelle ouverte depuis plus de 6 h, sans candidature, avec lien `/mission/:id` et UTM |
| Réactivation | chaque jour | Email aux inscrits réels bloqués (documents, vérification, candidature, première mission), au plus un tous les 14 jours, `preferences_notifications` respecté |
| Rapport hebdomadaire | lundi à 05:15 UTC | Entonnoir de la semaine ISO écoulée figé dans `growth_rapports_hebdo` |

Détail de l'agent de prospection :
- Cible : 75/92/56, types EHPAD, HANDICAP, DOMICILE, CENTRE_SANTE, HOPITAL, DIALYSE, ECOLE_SANTE.
- Score explicable : type d'établissement, email générique, téléphone, signal BOAMP sur 90 jours, tension BMO.
- Les départements alternent dans la file.
- Donnée BMO citée dans les brouillons (prospection et posts) : uniquement quand la part des projets
  « jugés difficiles » existe en base (`bmo_difficulte_pct IS NOT NULL`). Depuis le 20/11/2026,
  l'import n'enregistre cette part que si aucun bassin d'emploi du département ne masque ses chiffres
  (« * » dans le classeur France Travail) ; sinon elle reste vide et l'agent ne cite rien. L'ancien
  calcul la prenait sur les seuls bassins publiés et donnait donc un pourcentage que la source ne
  permet pas d'établir (exemple : 74 % affichés pour les aides-soignants du Morbihan, part en réalité
  non calculable). Même règle que les pages publiques (`scripts/seo/extraire-bmo.mjs`, PR #1170).
  Les valeurs en base restent celles de l'ancien calcul tant que l'import n'a pas été relancé :
  Admin → Acquisition → Priorités externes → « Synchroniser BMO + BOAMP ». Deux effets de cette
  relance : les brouillons déjà en file gardent leur texte (ils expirent au bout de sept jours), et
  le score de tension du radar interne lit une part vide comme 0 % (`fn_admin_acquisition_cibles`,
  `fn_admin_acquisition_radar_externe`) : les départements sans part publiée y descendent. Corriger
  ce score demande une migration sur des fonctions SECURITY DEFINER, donc un accord explicite.
- Exclusions : STOP, PERDU, OPPOSITION, adresse déjà en séquence.
- Adresses MSSanté exclues (domaine `mssante.fr` et ses sous-domaines, `20261116143942`) : premiers contacts, relances, et revalidation par le prédicat unique (§5). Une seule règle, `private.fn_growth_email_mssante`. Les brouillons MSSanté encore en file (`BROUILLON` ou `VALIDE`) ont expiré au déploiement, avec un motif visible dans l'historique, et ne comptent pas dans le quota du jour. MSSanté est un espace de confiance fermé, une boîte MSSanté n'échange qu'avec les messageries MSSanté de la liste blanche de l'ANS, donc un email envoyé depuis Gmail est rejeté (ANS : [doctrine MSSanté](https://esante.gouv.fr/doctrine/mssante), [« Basiques de la MSSanté », 08/2026](https://esante.gouv.fr/sites/default/files/media/document/Pr%C3%A9sentation%20-%20Basiques%20de%20la%20MSSant%C3%A9%20-%20082026.pdf)).
- Adresses Apicrypt exclues aussi (domaine `apicrypt.org` et ses sous-domaines, `20261117060000`), par la même règle, donc par les mêmes premiers contacts, relances, revalidation, expiration et quota. Constat du 17/11 : le premier passage après `20261116143942` a préparé 7 brouillons, tous vers une adresse `@interop-mssante.apicrypt.org` ; 554 prospects ont une telle adresse. Ce sont les adresses MSSanté des utilisateurs d'Apicrypt, publiées dans l'annuaire national ([FAQ Apicrypt](https://www.apicrypt.org/files/FAQ_mars2019_BD.pdf)) : même espace fermé. Force des sources : la FAQ fonde `interop-mssante.apicrypt.org` ; le reste d'`apicrypt.org` (messagerie chiffrée entre apicrypteurs) est un **choix de conformité Jolene**, prudent, sans adresse concernée au 17/11. `gmsi-mssante.fr` (1 adresse) n'est pas exclu, faute de source primaire. La migration verrouille par empreinte la règle et les quatre fonctions qui l'appliquent, puis vérifie le prédicat et la file après l'expiration.

### 4 bis. Zéro visible et liste d'appels (`20261124123500_prospection_zero_visible_liste_appels.sql`)

Constat du 20/11/2026 (lecture seule en production) : une fois les messageries fermées exclues, l'agent
email n'a plus de cible. Sur les 2 318 établissements ciblés de 75, 92 et 56, 656 ont une adresse, toutes
MSSanté ou Apicrypt ; 2 017 ont un téléphone (1 796 numéros distincts). Il ne préparait plus rien, sans
erreur ni message.

**Un seul univers ciblé.** `private.fn_growth_prospects_cibles()` lit une fois les départements et les
types ciblés et dit, pour chaque établissement : adresse fermée, adresse utilisable, téléphone
utilisable (un numéro français complet), cible disponible, et les points du score (type, signal BOAMP
de moins de 90 jours, tension BMO exacte). L'agent email, l'agent d'appels et le décompte lisent cette
fonction : aucun ne re-décide le ciblage.

Une cible est **disponible** si elle n'a jamais été contactée, n'est pas au CRM (date d'ajout sur le
prospect, ou contact CRM au même FINESS), n'est pas déjà inscrite sur la plateforme, n'est ni ignorée ni
en opposition, et n'a aucun brouillon vivant. Deux décisions à connaître :
- une cible n'a qu'un canal à la fois, et un brouillon **rejeté**, ou **validé puis expiré**, ferme la
  cible aux deux canaux. « Ne pas appeler » sur une fiche prive donc aussi l'établissement d'un email
  futur. C'est voulu : vous avez écarté cet établissement, ou vous avez pu le contacter sans le noter.
  Seul un brouillon jamais validé qui expire libère sa cible ;
- un numéro se compare sous sa forme nationale : `01 23 45 67 89`, `+33 1 23 45 67 89` et
  `0033 1 23 45 67 89` désignent le même numéro (`private.fn_growth_telephone_national`), pour le
  dédoublonnage comme pour le STOP. Un champ qui contient deux numéros, ou un numéro incomplet, n'est
  pas utilisable.

**Zéro visible.** `private.fn_growth_cibles_prospection()` compte l'univers : établissements ciblés,
adresses fermées, adresses utilisables, adresses restant à contacter, téléphones utilisables, téléphones
restants. Ce décompte figure dans le résultat de l'agent email (`growth_agent_executions.details.cibles`)
et dans l'entonnoir figé chaque semaine (`prospection.cibles_agent`). L'écran l'affiche :
- en haut de page, quel que soit l'onglet : « Prospection par email à l'arrêt » quand aucune adresse
  n'est utilisable, « Plus aucune adresse à contacter par email » quand elles sont toutes traitées ;
- sur la carte de l'agent : « Aucune cible joignable » à la place de « Brouillons seulement », et le décompte ;
- dans le rapport hebdomadaire : colonnes « Appels notés » et « Adresses utilisables ».

L'agent ne lève pas d'erreur : une exception annulerait aussi les relances préparées au même passage.

**Liste d'appels.** `private.fn_growth_agent_appels()` écrit des fiches dans `growth_brouillons`
(agent `APPEL_ETABLISSEMENT`, canal `TELEPHONE`) :
- 30 fiches par semaine (lundi, heure de Paris) et 60 en file au plus. Ce sont des défauts du code ;
  les clés facultatives `agents_appels_quota_semaine` et `agents_appels_file_max` les remplacent ;
- classement par le score existant sans sa part email, les départements alternant comme pour l'email.
  Au 24/11, aucun signal BOAMP n'a moins de 90 jours et la tension BMO est la même dans tout un
  département : l'ordre suit donc le type (EHPAD, hôpitaux, handicap, domicile, centres de santé et
  dialyse, écoles) ;
- mêmes interdits que l'email, par le prédicat unique `fn_growth_destinataire_bloque` (STOP, opposition,
  contact perdu, comparés par FINESS, adresse et numéro), moins le motif `MSSANTE` qui ne dit rien d'un
  appel : `private.fn_growth_appel_bloque`. Un même numéro (standard partagé) n'est proposé qu'une fois,
  fiche rejetée comprise ;
- la sélection n'est pas bornée avant ces contrôles : des cibles écartées en tête de classement ne
  tarissent pas la liste (c'était un défaut de l'agent email, corrigé pour les deux agents). Quand des
  places restent vides, l'agent le dit (`places_non_pourvues`) et sa carte affiche « Liste épuisée » ;
- une fiche non traitée expire au bout de 14 jours ; jamais validée, elle libère sa cible.

**Sur l'écran.** La fiche montre le nom, le numéro et son origine, les raisons du classement et le
script, modifiable.
1. « Valider la fiche » revérifie les interdits. Rien n'est composé.
2. « Appeler le … » revérifie la fiche **à chaque fois**, côté serveur, puis ouvre le composeur du
   téléphone : une opposition, un passage au CRM ou une inscription arrivés depuis la validation sont
   vus avant l'appel, pas après, et un numéro modifié dans l'annuaire est celui qui est composé. C'est
   vous qui confirmez l'appel sur votre téléphone. Un lien « composer le … » reste affiché deux minutes
   si le composeur ne s'est pas ouvert.
3. Après l'appel, vous notez le résultat : A répondu, Sans réponse, Intéressé, À rappeler, Pas intéressé
   ou STOP. Le décideur crée la fiche CRM silencieuse (`fn_admin_sourcing_ajouter_crm`) et traite le
   résultat par la logique CRM existante (`fn_admin_crm_effectuer_action`) : les rappels arrivent dans
   Prospects → « Actions du jour » ; « Pas intéressé » et « STOP » ferment tout contact ultérieur, email
   compris.

Si une opposition arrive pendant l'appel lui-même : un refus entendu (STOP, Pas intéressé) est toujours
enregistré ; tout autre résultat n'entre pas au CRM (« appel non enregistré au CRM ») mais reste lisible
sur la fiche.

Le rapport hebdomadaire compte les **fiches d'appel notées** de la semaine. Les rappels suivants se
suivent dans le CRM.

Limites connues, non traitées dans ce lot :
- l'avertissement lit le dernier passage de l'agent email : il apparaît après le premier passage qui
  suit le déploiement (06 h 50, ou « Préparer maintenant ») ;
- un contact CRM créé pour ce FINESS dans les secondes qui séparent « Appeler » du résultat noté est
  fusionné par la logique CRM existante ;
- dans le CRM, un second « À rappeler » sur un contact resté à l'étape 0 ne crée pas de tâche
  (`fn_crm_generer_taches`, clé déjà utilisée) : défaut antérieur à ce lot, à corriger à part ;
- `fn_sales_outreach_est_interdit` compare les numéros tels qu'ils sont saisis. La liste d'appels
  présente donc chaque numéro sous ses trois écritures ; les autres écrans du CRM ne le font pas.

**Script d'appel** (`private.fn_growth_script_appel`). Il ne reprend que des phrases déjà publiées :

| Phrase du script | Source publiée |
|---|---|
| « Jolene facture à l'établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée, majorations et indemnités incluses lorsqu'elles entrent dans cette base. » | FAQ de l'accueil, « Comment fonctionne la commission ? » (`src/lib/seo-contenu/accueil.ts`), mot pour mot |
| « Il n'y a ni abonnement ni frais d'entrée : vous ne payez que lorsque vous recrutez. » | Guide, « Combien coûte la publication d'une mission ? » (`src/lib/seo-contenu/guides.ts`), mot pour mot |
| « plateforme de mise en relation directe », « vous publiez votre besoin, des soignants vérifiés candidatent » | FAQ de `/recruter-soignants` (`src/lib/seo-contenu/recruter-soignants.ts`) |
| « le contrat est signé en ligne » | Accroche de l'accueil (« Contrat signé en ligne ») |
| « pour des missions et remplacements ponctuels », « l'inscription est gratuite pour les soignants » | Description de l'accueil (`src/lib/seo-routes.ts`) |

Il ne contient aucun chiffre hors le tarif publié, aucune promesse de délai, aucune comparaison avec un
autre type de prestataire, aucune règle de droit. Il se termine par : « Si vous préférez ne pas être
rappelé, dites-le-moi : je le note et Jolene ne vous rappellera plus. » Les écoles de santé ont une
variante (faire connaître Jolene aux jeunes diplômés), sans tarif.
`tests/node/prospection-liste-appels.node.mjs` compare ces phrases à leur source à chaque PR.

Parcours de la fondatrice (Admin → Acquisition → **Agents de croissance**, `/admin/fondateur/agents`) :
1. **À valider** : relire, modifier si besoin, puis « Valider et ouvrir Gmail » (email pré-rempli)
   ou « Valider et copier » (post).
2. Envoyer depuis Gmail, ou publier dans le groupe.
3. « J'ai envoyé » / « J'ai publié ». Pour un établissement, l'ajout au CRM et la séquence
   J+3/J+7/J+14 se font via `fn_admin_sourcing_ajouter_crm` et `fn_crm_enregistrer_email_envoye`.
   La relance due revient le moment venu en brouillon d'étape 2.
4. Une réponse STOP se saisit dans le CRM (action STOP existante). Elle est revérifiée à chaque
   validation : un brouillon devenu interdit est rejeté et le rejet persiste.

**Entonnoir** : vue en direct sur 7, 30 ou 90 jours (cohorte réelle) et historique hebdomadaire.
**Agents** : dernier passage, erreurs, bouton « Préparer maintenant ».

Réglages (`growth_config`, texte) : `agents_croissance_actifs`, `agents_departements_cibles`,
`agents_types_cibles`, `agents_prospection_quota_jour`, `agents_prospection_file_max`,
`prospection_signature`, `prospection_mention_opposition`, et, facultatives (absentes de la table,
défauts 30 et 60 dans le code), `agents_appels_quota_semaine` et `agents_appels_file_max`. Sans mention d'opposition, l'agent de
prospection refuse de tourner : le verrou est explicite et l'erreur est tracée.

## 5. Conformité — HARD STOP n°4 (validation de Gabrielle requise avant merge)

Wording exposé aux prospects, ajouté en pied de chaque email de prospection :

> Vos coordonnées professionnelles proviennent des annuaires publics des établissements de santé
> (répertoire FINESS et Annuaire Santé). Si vous ne souhaitez plus être contacté par Jolene, répondez
> simplement « STOP » à cet email : nous ne vous écrirons plus.

Origine vérifiée en base au 08/11 : les 64 058 établissements viennent de FINESS, et leurs 30 633 emails
viennent de l'enrichissement Annuaire Santé (FHIR ANS). Les relances de l'agent ne concernent que les
contacts qu'il a lui-même ouverts, ce qui garde cette mention exacte.

| Source | Force | Ce qu'elle impose |
|---|---|---|
| [CPCE art. L34-5](https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000042155961) | texte légal | Consentement préalable pour la prospection par email d'une **personne physique** ; dans tous les cas, identité de l'émetteur et moyen valable de demander l'arrêt |
| [RGPD art. 14.3.b et art. 21](https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32016R0679) | texte légal | Informer de la source des données au plus tard à la première communication ; droit d'opposition à la prospection, sans condition |
| [CNIL, prospection par courrier électronique](https://www.cnil.fr/fr/la-prospection-commerciale-par-courrier-electronique-sms-mms-et-automate-dappel) | doctrine de l'autorité | B2B sans consentement préalable si (1) le message est en lien avec la profession, (2) la personne est informée de l'origine des données et de la finalité, (3) elle peut s'opposer simplement |
| Envoi manuel depuis Gmail, quota de 20/j, STOP revérifié, cibles = établissements (personnes morales) via adresses professionnelles | choix de conformité Jolene | Délivrabilité, réputation, aucune automatisation d'envoi |

Choix de conformité proposés :
- **Pas de prospection des soignants particuliers.** Les 170 886 emails RPPS ne sont pas utilisés,
  car le consentement préalable est requis (L34-5).
- Les emails de réactivation ne visent que des inscrits (relation existante). Ils respectent
  `preferences_notifications.canal_email` et rappellent que les préférences se gèrent dans le compte.
- Les posts sont publiés à la main dans des groupes publics : pas d'auto-post, pas de scraping des
  membres (règles Meta).

Les emails reprennent uniquement des affirmations déjà publiques sur `/recruter-soignants` :
15 % HT de commission, sans abonnement, contrôle de l'identité et des qualifications (RPPS lorsqu'il
existe), contrats et facturation automatiques. Il n'y a aucune mention réglementaire.

Garde-fous du code :
- Appels (24/11/2026). Choix de conformité Jolene, sans règle de droit affichée : les fiches ne visent
  que le numéro publié de l'établissement dans les annuaires publics (FINESS, Annuaire Santé), jamais un
  particulier ; la fondatrice appelle elle-même ; le script propose de ne plus être rappelé, et « STOP »
  ou « Pas intéressé » sont définitifs pour tous les canaux. Aucun texte de loi n'est cité à
  l'interlocuteur ni affirmé ici : le cadre juridique du démarchage téléphonique entre professionnels
  n'a pas été instruit dans ce lot (à faire avec sa source primaire avant d'en écrire une ligne, HARD
  STOP n°4). La phrase d'opposition du script est une proposition soumise à Gabrielle.
- Un **prédicat unique**, `private.fn_growth_destinataire_bloque`, sert aux agents comme à la
  validation. Il refuse un compte supprimé, les emails désactivés (préférence globale ou événement
  `SERIE_ONBOARDING`), les oppositions STOP et, en dernier, les adresses MSSanté (motif `MSSANTE`,
  affiché « Destinataire invalide » à la validation).
- La visibilité d'une mission vient de `fn_mission_publique`.
- Les brouillons d'un compte supprimé sont effacés.
- Un brouillon non envoyé, même validé, expire.
- Après le dernier email (étape 3), la séquence CRM s'arrête.
- Écart connu (A4, non bloquant) : quand un compte est supprimé, ses brouillons sont effacés au
  passage suivant des agents (quotidien une fois activés, ou « Préparer maintenant »). D'ici là, ils
  restent visibles des seuls admins, et aucun envoi n'est possible : la validation revérifie le compte
  et efface le brouillon. La correction complète consiste à purger les brouillons dans le parcours de
  suppression de compte (`fn_supprimer_mon_compte*`), ce qui sort du périmètre de cette PR.
- Une relance validée puis expirée bloque l'étape suivante de ce contact. C'est un choix prudent :
  l'email a pu partir sans constat. Le contact reste suivi dans le CRM.

## 6. Ce qui attend le feu vert de Gabrielle

1. **Merge de cette PR** (tiering B9 : nouvelles tables RLS, RPC SECURITY DEFINER, GRANT ; HARD
   STOP n°4 sur le wording du §5).
2. **Activation** : dans Admin → Agents de croissance → onglet Agents, cliquer sur « Activer la
   préparation automatique ». Les brouillons arrivent ensuite chaque matin à 06:50 (heure de Paris).
   On peut aussi cliquer sur « Préparer maintenant » pour en avoir tout de suite.
3. **Premiers envois réels** : c'est la fondatrice qui valide et envoie chaque email depuis son Gmail.
4. **Réactivation des imports BOAMP, BMO et FINESS** (crons en pause) : à rejouer après correction
   de l'authentification de service, une source à la fois, en surveillant le CPU.
5. **`automatisations_marketing_actives=true`** (relance, digest, avis) : non recommandé avant
   d'avoir ajouté le lien de désinscription en 1 clic et le respect de `preferences_notifications`
   dans ces trois Edge Functions.
6. **Activer Vercel Web Analytics** (ou un équivalent sans cookie) pour mesurer le trafic SEO.
7. **Instruction juridique** de l'argument « vacation directe vs intérim » (§3) avant tout usage public.

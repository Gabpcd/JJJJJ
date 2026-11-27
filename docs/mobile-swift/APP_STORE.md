# Soumission App Store de l'app Swift (`ios-native/`)

Workflow : `.github/workflows/ios-native-app-store.yml` (« iOS Swift — soumission App Store »).
Gardes : `scripts/mobile/ios-native-app-store.mjs`, testées par `tests/node/ios-native-app-store.node.mjs`
(job `validate-pr`, étape « Gardes de la soumission App Store »). Décisions : `DECISIONS_LOT6.md`.

## Ce que fait le workflow, et ce qu'il ne fait jamais

Il soumet à la revue Apple un build de l'app `app.jolene` (App Store Connect `6774672845`) **déjà envoyé
sur TestFlight** par `ios-native-testflight.yml` et déjà traité (`VALID`). Il active la publication
progressive sur sept jours, écrit le champ « Nouveautés » fr-FR et place en tête du champ « Notes » des
informations pour la vérification le bloc du rôle vérifié du compte de démonstration
(`config/ios-review-notes-2.0-soignant.txt` ou `config/ios-review-notes-2.0-etablissement.txt`, section
« Notes pour la revue et compte de démonstration »).

Il ne fait **jamais** : de compilation, d'envoi de binaire, de modification des captures, de la
description, de la confidentialité ou de la classification. Il n'écrase jamais des identifiants de
démonstration présents : il ne copie la fiche de vérification de la version distribuée que si la 2.0.0 n'en a
pas. Il ne part jamais seul : ni push, ni PR, ni merge, ni fin d'un autre workflow ne le déclenchent.

**Pièces jointes de la fiche de vérification** (comportement de deliver 2.240.1, inchangé par ce workflow) : à
chaque soumission, deliver supprime toutes les pièces jointes de la fiche (vidéo, document), faute de fichier
fourni (`deliver/lib/deliver/upload_metadata.rb`, `review_attachment_file`). Une vidéo reprise de 1.0.7
disparaît donc. Rien ne le signale au journal.

Deux modes : `verifier` (défaut) joue toutes les gardes, dont le pré-vol des notes pour la revue (lane
`preflight_review_native` : fiche lue, compte de démonstration connecté à la production puis déconnecté, notes
composées et mesurées), sans rien écrire chez Apple, et s'arrête avant la soumission et le tag ;
`soumettre` joue les mêmes gardes, puis soumet et pose le tag, et exige en plus la phrase de confirmation.
Lancer d'abord en `verifier` : c'est la répétition à blanc de la soumission, fiche et compte compris.

## Avant de lancer

1. **Aucun port en attente, dans aucun lot (1 à 5)**, sur `main` : les cinq listes
   `DemoWorldTests.portsEnAttenteLot1` à `portsEnAttenteLot5` sont vides. Au 26/11/2026, c'est le cas : le
   dernier, `recovery` (« Mot de passe oublié ? », reste de L1-T10), est câblé, et la garde `lots` passe sur
   l'arbre de `main`. Un port remis en attente ferait refuser toute soumission ; c'est voulu.
2. Un build a été envoyé **depuis ce `main`** par `ios-native-testflight.yml` (build 32 ou plus), **il y a
   moins de 14 jours** (rétention de l'artefact de provenance, garde `provenance`). Notez son numéro.
3. Le dernier run de « iOS Swift — socle natif » (`ios-swift-ci.yml`) sur le commit dont ce build est issu
   est **vert** (garde `ci-ios`). Ce workflow ne tourne sur un push de `main` que si ses chemins changent,
   et un push suivant annule le run en cours : si le commit n'a pas de run vert, lancer
   `ios-swift-ci.yml` à la main sur `main` **avant** l'envoi TestFlight, au même commit.
4. Ce build a été recetté sur iPhone (`RECETTE_DEVICE_LOT4.md`, `RECETTE_DEVICE_LOT5.md`), dont les liens
   universels et le push de production.
5. Les saisies d'App Store Connect sont faites (`LOT6_PLAN.md` §3) : fiche, confidentialité, classification,
   captures. Le compte de démonstration (« Connexion requise ») et, dans les notes, les identifiants de l'autre
   compte de revue viennent de la version précédente : si la 2.0.0 n'en a pas, la lane les copie de la version
   distribuée (1.0.7). Le run `verifier` prouve que ce compte se connecte en production et sur quel rôle.
6. `config/mobile-release-notes-ios.txt` contient le texte voulu pour « Nouveautés ».

## Lancer la soumission

GitHub → Actions → « iOS Swift — soumission App Store » → *Run workflow*, branche `main` :

- **Mode** : `verifier` d'abord (défaut, rien n'est soumis), puis `soumettre`.
- **Numéro du build** : celui du build TestFlight, par exemple `32`.
- **Confirmation** (mode `soumettre` seulement) : écrire exactement `SOUMETTRE 2.0.0 (N)` en remplaçant
  `N` par le numéro du build (pour le build 32 : `SOUMETTRE 2.0.0 (32)`). Toute autre saisie arrête le
  workflow. La lane la recompare elle-même avant d'écrire chez Apple.
- **Publication** : `automatique` (mise en vente dès l'approbation) ou `manuelle` (la version attend en
  « Pending Developer Release » jusqu'au clic « Release this version »). Progressive dans les deux cas.

Trois jobs s'enchaînent :

- `gardes` (Ubuntu, « Gardes avant soumission (sans écriture chez Apple ; compte de démonstration connecté puis
  déconnecté) ») : toutes les gardes ci-dessous, pré-vol des notes compris, puis
  un verdict posé seulement si toutes ont réussi ; aucune de ses étapes n'est conditionnelle ;
- `soumettre` (macOS 26), en mode `soumettre` et sur verdict des gardes seulement : lane
  `fastlane ios submit_native` ;
- `consigner` (Ubuntu), après `soumettre` : tag `mobile-native-ios-N` sur le commit source du build.

En mode `verifier`, `soumettre` et `consigner` sont ignorés : rien n'est écrit chez Apple ni dans le dépôt.
Seule trace du pré-vol : une connexion du compte de démonstration à la production, aussitôt révoquée.

Une seule soumission à la fois (groupe de concurrence `ios-native-app-store`, sans annulation).

**Toujours relancer le workflow entier** (« Re-run all jobs ») : « Re-run failed jobs » sur `soumettre`
ou `consigner` réutiliserait les sorties d'un job `gardes` plus ancien sans le rejouer. Les deux jobs, et
la lane, comparent donc la tentative des gardes à la tentative en cours et refusent tout écart.

## Les gardes

Chaque refus s'affiche sous la forme `[garde] message (voir docs/mobile-swift/APP_STORE.md, garde « … »)`
et arrête le workflow avant toute écriture chez Apple. Aucune garde ne se désactive par une option.

| Garde | Ce qu'elle vérifie | Si elle échoue |
|---|---|---|
| `entrees` | Déclenchement manuel sur `main` ; mode `verifier` ou `soumettre` ; numéro de build entier, supérieur à 24 et au moins égal à `ios.minimumBuildNumber` ; en mode `soumettre`, phrase de confirmation exacte ; mode de publication connu. | Corriger la saisie. Un build 25 à 31 ne se soumet pas : il précède la clôture des lots 1 à 5. |
| `notes` | `config/mobile-release-notes-ios.txt` existe, tient en 4 000 caractères, annonce la reconnexion et Face ID, sans texte provisoire. | Corriger le fichier par une PR. |
| dépôt | Les gardes statiques du TestFlight (`TESTFLIGHT.md`) : production, chiffrement exempté, manifeste de confidentialité, icône, entitlements. | Voir `TESTFLIGHT.md`. |
| `provenance` | `main` n'a pas avancé depuis le déclenchement ; un run réussi de `ios-native-testflight.yml`, lancé à la main depuis `main`, a produit l'artefact `ios-native-testflight-<N>-<commit>`, encore disponible ; ce commit appartient à l'historique de `main`. L'artefact est conservé **14 jours** (`retention-days` de `ios-native-testflight.yml`) : au-delà, le build ne se soumet plus, y compris pour une nouvelle soumission après un refus d'Apple, et le refus le dit (« a expiré », ou « introuvable » une fois purgé). | Relancer depuis le `main` courant. Artefact expiré ou purgé : refaire un envoi TestFlight et soumettre le nouveau build. |
| `ci-ios` | Le dernier run de `ios-swift-ci.yml` sur le commit source exact, sur `main` (push ou déclenchement manuel ; état de sa dernière tentative), est terminé et réussi. Le refus nomme le commit et la conclusion lue. Aucun run sur ce commit : refus, jamais de repli sur un ancêtre. | Lancer `ios-swift-ci.yml` sur `main` à ce commit et attendre le vert, ou envoyer un nouveau build depuis un commit dont la CI iOS est verte. |
| `lots` | Dans la source de ce commit, les cinq listes `DemoWorldTests.portsEnAttenteLot1` à `portsEnAttenteLot5` sont vides : aucun port en attente, dans aucun lot. Lecture stricte : commentaires retirés, une seule déclaration, un tableau de noms entre guillemets et rien qui le prolonge (`+`, `.filter`, `as`…) ; sinon la liste est « illisible » et la garde refuse. | Câbler le port nommé par le refus, puis envoyer un nouveau build. |
| `etablissement` | Dans la même source : la table `OuvertureEspaceEtablissement.pour(mode:)` (`JoleneCore/Session/EspaceResolution.swift`) rend `.ouvert` pour `.production` (lot 5, T14). Lecture stricte : commentaires retirés, un seul `switch mode` fait de `case .x: return .ouvert/.ferme`, sans `default` ni `#if`, chaque cas de `JoleneMode` (lu dans `Environment.swift`) décidé une fois ; sinon la table est « illisible » et la garde refuse. Câblage (revue de #1190, M2 et m1) : chaque construction de `SessionController(` et de `DeepLinkCoordinator(` de la cible app est dans `AppContainer.swift`, hors de toute compilation conditionnelle (`#if`), et reçoit `espaceEtablissement: .pour(mode: environment.mode)` ; `.pour(mode: .demo)` n'est admis que pour le contrôleur de la branche `case .demo:` de `switch environment.mode` ; une construction sans l'argument (défaut `.ferme`) est refusée. Rôles (m2) : `EspaceResolution.espace` rend `.etablissement` et `UserRole.isNativelyServed` rend `true` pour `.adminEtablissement` et `.etablissementLegacy`. Limite : la garde lit ces sources, pas la résolution complète de la session ni le coupe-circuit distant `ios_natif_etab_espace_actif` (`DECISIONS_LOT5.md`, section T14) ; `SessionControllerEtablissementTests` couvre le reste en `swift test`. | Ne pas soumettre un build dont l'espace établissement est fermé en production : rouvrir par une PR consignée dans `DECISIONS_LOT5.md` (section T14). |
| `apple-4.2` | Dans la même source : ports `dashboard`, `mesMissions`, `presence`, `pointage` câblés ; fichiers des écrans natifs du tableau de bord, de Mes missions et du pointage présents ; onglets `tab-accueil` et `tab-missions` de `MainTabView.swift` qui montent `AccueilScreen` et `MesMissionsScreen` (pour le pointage, seuls la présence de son fichier et l'appel de `fn_scanner_code_pointage` sont contrôlés, pas son montage) ; RPC `fn_dashboard_soignant_complet` et `fn_scanner_code_pointage` appelées par le client Swift ; aucune vue web à la racine de l'app. | Ne pas soumettre : Apple refuse un site réemballé (règle 4.2). |
| `ota` | Aucun client de mise à jour à chaud (règle 2.5.2), cherché par nom dans les sources Swift de `Jolene/` et de `Packages/*/Sources`, **et** dans les `Package.swift`, `Package.resolved` et `project.yml` de `ios-native/` ; au moins un `Package.swift` et un `Package.resolved` doivent être lus. C'est une liste de noms interdits, pas une liste de dépendances admises. | Retirer la dépendance. |
| backend | Le dernier déploiement Supabase de production est vert et couvre le backend de `main` (`delivery-plan-backend.mjs`). | Attendre ou réparer `deploy-supabase`. |
| `build` | Dans App Store Connect : un seul build `N`, `VALID`, non expiré, `usesNonExemptEncryption = false`, version `2.0.0`, plateforme iOS ; version supérieure à 1.0.7, build supérieur à 24. | Attendre la fin du traitement, ou envoyer un nouveau build. |
| compte de démonstration et notes | Lane `preflight_review_native` dans les gardes (les deux modes), puis de nouveau dans la lane de soumission, avant la garde « revue en cours » (`fastlane/ios_review_notes.rb`) : version modifiable `2.0.0`, ou aucune ; fiche lue (celle de la version distribuée si la 2.0.0 n'a pas d'identifiants) ; identifiants présents ; connexion à Supabase de production réussie, sur le rôle soignant ou établissement ; notes composées en 3 900 unités UTF-16 au plus. Détail : section « Notes pour la revue et compte de démonstration ». | Voir « Si le verrou refuse », dans cette section. |
| revue en cours | Dans la lane (`fastlane/ios_review_submission.rb`) : version supérieure à la version en vente ; une soumission encore « en attente de revue » pour un build plus ancien est annulée puis remplacée ; une revue commencée (`IN_REVIEW`) n'est jamais interrompue. | Lire le message : la revue en cours est préservée. |

## Secrets et droits

Trois secrets, ceux du TestFlight : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`. Aucun
matériel de signature n'est lu. La connexion du compte de démonstration n'ajoute aucun secret : l'URL et la clé
publishable de production sont publiques et lues dans `ios-native/Config/Production.xcconfig`. Droits du jeton
GitHub : lecture seule, sauf le job `consigner` qui pose le tag. Les entrées passent par des variables
d'environnement, jamais par interpolation dans un script ; la phrase saisie n'est pas réaffichée. Les actions
sont épinglées par leur commit.

**Journaux de Spaceship.** Le client App Store Connect de fastlane (Spaceship, 2.240.1,
`spaceship/lib/spaceship/client.rb`) écrit chaque requête et chaque réponse de l'API d'Apple, corps compris,
dans un fichier `$TMPDIR/spaceship*.log` du runner. Seule une clé `password` de premier niveau y est masquée :
la lecture de la fiche de vérification (par la lane comme par deliver) et sa copie y laissent donc le mot de
passe du compte de démonstration, en clair. Règles :

- jamais `VERBOSE`, `--verbose`, `FASTLANE_VERBOSE` ni `SPACESHIP_DEBUG` dans ces workflows : avec `VERBOSE`, ce
  journal part sur la sortie standard, donc dans le journal GitHub ; avec `--verbose`, fastlane affiche aussi la
  cause des erreurs ;
- jamais d'artefact (`upload-artifact`) ni de cache du dossier temporaire : `ios-native-app-store.yml` n'en
  envoie aucun (gardé par `tests/node/ios-native-app-store.node.mjs`) ;
- les journaux sont effacés avec la clé App Store Connect, à la fin du pré-vol et à la fin de la soumission,
  quel que soit le résultat ; les runners GitHub sont de toute façon détruits après le job.

Le journal GitHub, lui, ne contient aucune valeur de la fiche : seulement des noms de champs, des longueurs,
des états et les lignes « compte de démo : … ».

**La lane hors du workflow.** `fastlane ios submit_native` refuse de tourner hors du job `soumettre` de
ce workflow sur `main` (contexte GitHub Actions, `workflow_dispatch`, `GITHUB_WORKFLOW_REF` de ce
fichier), sans le mode `soumettre`, sans le verdict des gardes de la même tentative, ou sans la phrase
exacte (`IosReviewSubmission.exiger_contexte_workflow!`, `fastlane/ios_review_submission.rb`).
`fastlane ios preflight_review_native` refuse de tourner hors de ce workflow sur `main`, dans l'un de ses deux
modes (`IosReviewSubmission.exiger_contexte_prevol!`). Ce sont des contrôles de contexte : ils arrêtent une
lane lancée par erreur depuis un poste ou un autre workflow, pas une personne qui détient la clé App Store
Connect et appelle l'API d'Apple directement. La vraie protection est la garde de la clé : elle ne doit
exister nulle part ailleurs que dans les secrets GitHub.

**Action du propriétaire du dépôt, non faite (réglage hors code).** « Depuis `main` seulement » n'est
garanti que par le fichier : un `workflow_dispatch` sur une autre branche exécute la copie du workflow de
cette branche, avec les mêmes secrets de dépôt ; une copie modifiée ne refuserait plus rien (il faut un
accès en écriture au dépôt). Pour le garantir côté GitHub : créer un environnement (par exemple
`app-store`) dont les règles de déploiement n'admettent que la branche `main`, y déplacer les secrets
`ASC_KEY_ID`, `ASC_ISSUER_ID` et `ASC_PRIVATE_KEY_BASE64` (et, pour `ios-native-testflight.yml` et
`mobile-delivery.yml`, les secrets de signature et de Google Play), puis déclarer `environment:` sur les
jobs qui les lisent, dans une PR. `mobile-store-status.yml` (lecture seule de l'état des stores) lit les
mêmes trois secrets `ASC_*` : son job doit déclarer le même environnement dans la même PR, sinon il perd
l'accès dès que les secrets sont déplacés. Tant que ce réglage n'est pas fait, cette limite demeure.

## Après la soumission

- « Soumis », « approuvé » et « en vente » sont trois états distincts : le tag prouve la soumission.
- Suivre l'état par `mobile-store-status.yml` (lecture seule) ou dans App Store Connect.
- Relancer le workflow avec le même build ne soumet pas deux fois : si ce build est déjà soumis (en
  attente de revue ou en revue) ou déjà en vente, publication progressive comprise, la lane s'arrête sur
  « déjà soumis » et le job finit vert. Dès que la 2.0.0 n'est plus modifiable, c'est-à-dire dans l'un des huit
  états qui suivent une soumission (`ReviewNotes::SOUMISES`), le pré-vol des notes constate qu'elle est déjà
  soumise. Il ne lit alors ni la fiche de 1.0.7 ni celle de la 2.0.0, et ne connecte pas le compte de
  démonstration, que le relecteur peut être en train d'utiliser. En mode `verifier`, le run finit donc vert. En
  mode `soumettre`, la garde de la revue décide, toujours sans rien écrire chez Apple :

  | État de la 2.0.0 (même build) | Mode `soumettre` |
  |---|---|
  | `IN_REVIEW`, `PENDING_APPLE_RELEASE`, `WAITING_FOR_EXPORT_COMPLIANCE`, `PROCESSING_FOR_DISTRIBUTION`, `READY_FOR_DISTRIBUTION` (publication progressive comprise) | vert : « déjà soumis » |
  | `PENDING_DEVELOPER_RELEASE` (publication `manuelle`, version approuvée) | **rouge** : la mise en vente se fait par le bouton « Release this version » |
  | `ACCEPTED` (état hérité d'une version approuvée) | **rouge** : « automatic replacement stopped and review preserved » |
  | `REPLACED_WITH_NEW_VERSION` (2.0.0 remplacée par une version plus récente) | **rouge** : « already distributed or superseded » ; soumettre une version plus récente |

  `WAITING_FOR_REVIEW` n'est pas dans cette liste : la version reste modifiable, et le pré-vol la contrôle en
  entier (fiche, connexion, notes) avant que la garde conclue « déjà soumis ». Une 2.0.0 dans un autre état non
  modifiable (par exemple `READY_FOR_REVIEW`) arrête le pré-vol, nommément.
- Pour remplacer un build en attente de revue par un build plus récent, relancer avec le nouveau numéro.
- Publication progressive : 1 %, 2 %, 5 %, 10 %, 20 %, 50 % puis 100 % sur sept jours ; pause possible
  jusqu'à 30 jours ; chacun peut toujours mettre à jour à la main depuis l'App Store.
- Après la mise à jour, chaque utilisateur se reconnecte une fois et réactive Face ID (plan §6). Le taux
  de reconnexion se suit par `fn_audit_connexion`.

## Notes pour la revue et compte de démonstration

Personne ne se connecte au site App Store Connect : la lane passe par l'API, avec la clé ASC du workflow.
Code : `fastlane/ios_review_notes.rb` (notes, fiche) et `fastlane/ios_review_demo_account.rb` (connexion du
compte) ; tests hors réseau : `fastlane/ios_review_notes.test.rb` (job `validate-pr`).

**Où sont les notes.** Le texte pour le relecteur Apple (en anglais) existe en deux variantes versionnées, une par
compte possible dans les champs « Sign-in required » :

- `config/ios-review-notes-2.0-soignant.txt` : le compte des champs est le compte soignant ; le compte
  établissement est dans les notes précédentes ;
- `config/ios-review-notes-2.0-etablissement.txt` : l'inverse.

La variante est choisie d'après le rôle **vérifié** par la connexion (ci-dessous), jamais supposé. Dans App
Store Connect, le champ « Notes » de la version 2.0.0 devient :

1. ce bloc ;
2. une ligne vide, puis la ligne `--- Notes from version 1.0.7 (previous hybrid app) ---` ;
3. les notes déjà présentes, telles quelles. Quand la version 2.0.0 est créée, elles viennent de 1.0.7 (app
   Capacitor, trois rôles dont un compte administrateur) ; elles portent les identifiants de l'autre compte
   de revue, auxquels le bloc renvoie.

La lane ne passe pas par l'option `app_review_information` de deliver, qui remettrait `demoAccountRequired` à
faux faute d'identifiants. Aucun identifiant n'entre dans le dépôt (public) : un bloc est refusé s'il contient
une adresse e-mail.

**Connexion du compte de démonstration** (pré-vol, `fastlane/ios_review_demo_account.rb`). Avec le nom et le
mot de passe de la fiche (celle de la 2.0.0, ou celle de 1.0.7 si la reprise doit s'appliquer), la lane se
connecte à Supabase de production exactement comme l'app native (`SupabaseAuthGateway.signIn`) :
`POST /auth/v1/token?grant_type=password`, clé publishable en en-tête `apikey`, sans jeton captcha (l'app n'en
envoie pas à la connexion). Elle relit le rôle par la même RPC que l'app (`fn_get_my_role`), puis révoque
aussitôt cette session seulement (`POST /auth/v1/logout?scope=local`). Rôles admis : soignant (`SOIGNANT`, le
compte attendu) ou établissement (`ADMIN_ETABLISSEMENT`). Tout
autre rôle (`ADMIN_PLATEFORME`, `ADMIN_GROUPE`, `INCONNU`) arrête la lane : l'app ne sert pas ces comptes.
Journal : « compte de démo : connexion OK, rôle soignant » (ou établissement) ; en échec, un motif fermé :
« connexion refusée (HTTP 400) », « connexion refusée, captcha exigé (HTTP 400) », « connexion impossible
(réseau : …) », « rôle ADMIN_PLATEFORME », « déconnexion non confirmée ». Jamais d'adresse, de mot de passe,
de jeton, d'identifiant ni de corps de réponse. La fiche écrite et soumise doit porter exactement les
identifiants connectés au pré-vol (empreinte gardée en mémoire), sinon la lane s'arrête.

**Lecture du rôle** (`CompteDemo.extraire_role`). `fn_get_my_role` est une fonction scalaire (`RETURNS jsonb`, non
`SETOF`) qui rend un objet `{user_id, role, etablissement_id}` ; l'app la lit en `AnyJSON`. Le run `verifier` n° 2
(27/11/2026, run 45952839306) s'est arrêté sur « rôle illisible (HTTP 200) » sans que la forme exacte de la réponse
soit connue : la lane admet donc les formes plausibles, et leurs combinaisons, trois déballages au plus :

- objet portant `role` texte ;
- tableau d'un seul élément (forme `SETOF` ou `vnd.pgrst`) ;
- objet à la seule clé `fn_get_my_role` ;
- chaîne JSON qui encode l'une de ces formes.

Toute autre forme est refusée. Le refus porte un **diagnostic sans aucune valeur** (`CompteDemo.diagnostic_role`) :
type JSON racine (objet, tableau, chaîne, nombre, booléen, null, invalide) ; pour un objet, les noms de clés de
premier niveau de la liste blanche `role`, `user_id`, `etablissement_id`, `fn_get_my_role`, et le nombre des
autres ; pour un tableau, le nombre d'éléments ; pour une chaîne, le type qu'elle encode ; puis le type MIME de
`Content-Type`, la taille du corps en octets et le `Content-Encoding` restant. Par exemple : « rôle illisible
(HTTP 200 ; JSON racine : tableau ; éléments : 0 ; type : application/json ; corps : 2 octets ; encodage :
aucun) ».

**Compression.** Le transport (`CompteDemo::TransportHttps`) construit la requête sans en-têtes initiaux : Net::HTTP
pose lui-même `Accept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3`, garde `decode_content` vrai, décompresse un
corps gzip ou deflate à la lecture, puis retire `Content-Encoding`. Un `Accept-Encoding` ou un `Range` fournis par
l'appelant désactiveraient ce décodage : le transport les refuse. Un test le prouve sur une réponse gzip et une
réponse deflate servies en boucle locale (127.0.0.1). Un encodage encore présent dans le diagnostic signifierait
donc un corps non décompressé.

**Dépendance : réglage Supabase de session unique.** `scope=local` ne révoque que la session du pré-vol. Cela ne
préserve la session d'un relecteur Apple que si le réglage Supabase Auth « session unique par utilisateur »
(*single session per user*, tableau de bord → Authentication → Sessions) est **désactivé** : s'il est actif, c'est
la connexion du pré-vol elle-même qui ferme les autres sessions du compte. Le dépôt ne fixe pas ce réglage
(`supabase/config.toml` n'a pas de section `[auth]`) ; il se constate dans le tableau de bord, et doit rester
désactivé. Le pré-vol ne se connecte pas quand la 2.0.0 est en revue, approuvée, en attente de publication ou en
vente (`ReviewNotes::SOUMISES`, ci-dessus). Il se connecte en revanche avant la soumission et pendant l'attente de
revue (`WAITING_FOR_REVIEW`, état modifiable, contrôlé en entier), quand aucun relecteur n'est encore connecté :
le risque se limite à ces runs.

**Reprise de la fiche de vérification.** Si la 2.0.0 (retrouvée ou tout juste créée) n'a pas de fiche, ou n'a pas
d'identifiants de démonstration (nom ou mot de passe vide), la lane la complète depuis la dernière version
distribuée avant la 2.0.0, qui doit être la coquille Capacitor figée : aujourd'hui 1.0.7.

**Choix de la source** (`ReviewNotes.choisir_source`). Apple laisse `appVersionState = READY_FOR_DISTRIBUTION` sur
**toutes** les versions déjà publiées, pas seulement sur celle en vente : le premier run `verifier` réel (27/11/2026)
en a compté sept, dont 1.0.7 (son journal ne donne que le nombre ; la liste exacte n'est pas prouvée). La lane ne
suppose donc aucune unicité et :

- refuse si une version distribuée a un numéro non numérique (un à trois entiers attendus) ;
- refuse si une version distribuée n'est pas antérieure à la 2.0.0 ;
- prend la version distribuée de plus haut numéro (comparaison `Gem::Version`, donc 1.0.10 > 1.0.7) ;
- refuse si deux versions portent ce même numéro maximal ;
- **verrou** : refuse si cette version n'est pas exactement la coquille figée, `COQUILLE_IOS_FIGEE.marketingVersion`
  de `scripts/mobile/release-config.mjs` (source unique, lue côté Ruby par `ReviewNotes.lire_coquille_figee!`,
  qui refuse toute autre forme de la déclaration). C'est la version dont les notes décrivent l'app précédente, et
  que le séparateur nomme.

Puis la lane copie :

- les identifiants, d'un bloc : `demoAccountName`, `demoAccountPassword`, et `demoAccountRequired` écrit à `true`
  (la connexion de ces identifiants a réussi au pré-vol) ;
- les contacts (`contactFirstName`, `contactLastName`, `contactPhone`, `contactEmail`) et `notes`, seulement là
  où la 2.0.0 est vide : une valeur déjà saisie n'est jamais remplacée.

Des identifiants présents dans la 2.0.0 ne sont jamais écrasés. La copie va d'une réponse de l'API à une requête
de l'API, dans le job ; le journal nomme les champs copiés, jamais une valeur. La fiche est relue et comparée à la
copie avant la suite. Une fiche illisible (erreur d'Apple) n'est jamais tenue pour absente : la lane s'arrête
sans rien copier. La copie n'a lieu qu'à l'écriture, jamais au pré-vol.

**`demoAccountRequired` inconnu (null).** Apple a déjà renvoyé ce booléen à `null` sur ce compte. Si les
identifiants sont présents et que la connexion a réussi, la lane l'écrit explicitement à `true` : c'est la seule
écriture permise hors `notes` et hors reprise. Un `false` explicite (« Connexion requise » décoché) n'est jamais
retourné : la lane s'arrête.

**Ordre dans la lane** (`IosReviewSubmission.enchainer!`) :

1. pré-vol, sans écriture chez Apple, avant la garde « revue en cours » (donc avant toute annulation) : si une
   version modifiable existe, elle doit être `2.0.0` ; sa fiche est lue et, s'il lui manque les identifiants,
   celle de la version distribuée aussi ; si la 2.0.0 n'existe pas encore, la fiche de la version distribuée sert
   de prévision ; si la 2.0.0 est déjà soumise (en revue, approuvée ou en vente), rien de plus n'est lu, aucune
   connexion n'est faite et la garde conclut. Puis : verrou sur la
   fiche telle qu'elle sera après la copie, connexion du compte, choix du bloc par le rôle, notes composées et
   mesurées. Rien n'est écrit, pas même la copie ;
2. garde « revue en cours » (`ios_review_submission.rb`) ;
3. version `2.0.0` retrouvée, ou créée si aucune version n'est modifiable (même requête que deliver) ; fiche
   relue, copiée de la version distribuée si besoin puis relue ; `demoAccountRequired` écrit à `true` s'il est
   inconnu ; mêmes identifiants qu'au pré-vol ; verrou rejoué ; champ `notes` écrit puis relu (verrou, identifiants
   et texte contrôlés encore une fois) ;
4. soumission par deliver, qui retrouve cette même version (`get_edit_app_store_version`) sans en créer une
   seconde.

La lane `preflight_review_native` du job `gardes` n'exécute que l'étape 1, dans les deux modes : le run
`verifier` sur `main` prouve donc la fiche, la connexion du compte, son rôle et la longueur des notes avant toute
soumission.

**Le verrou.** La soumission s'arrête si, après la copie éventuelle, `demoAccountRequired` n'est pas `true`, le
nom ou le mot de passe du compte de démonstration est vide, la fiche est absente, ou la connexion échoue. Elle
s'arrête aussi si la 2.0.0 n'a pas d'identifiants et que la version distribuée n'en a pas non plus (ou qu'il n'y
a pas de version distribuée). Le message dit ce qui manque, jamais une valeur : le nom et le mot de passe ne sont
ni affichés ni journalisés, pas même masqués. Le texte des notes et les contacts ne le sont pas non plus.

**Idempotence.** Si les notes commencent déjà par le bloc du rôle vérifié, rien n'est écrit. Si un bloc précédent
est en tête (texte placé avant la ligne de séparation, y compris l'autre variante), il est remplacé ; les notes de
la version précédente restent une seule fois, et le bloc n'apparaît jamais deux fois. Plus d'une ligne de
séparation : arrêt (composition ambiguë).

**Marge sous la limite d'Apple.** Apple limite le champ à 4 000 caractères. La lane s'arrête au-delà de 3 900,
comptés en unités UTF-16 (un émoji en compte deux), fins de ligne `\r\n` ramenées à `\n`, dès le pré-vol. Chaque
bloc fait 2 090 unités, 2 147 avec le séparateur : il reste 1 753 unités pour les notes de 1.0.7.

**Avertissement sans échec, dès le pré-vol.** Si les notes de la version précédente ne contiennent aucune adresse
e-mail autre que celle du compte de démonstration (comparaison en mémoire, rien n'est affiché ; une adresse collée à
de la ponctuation, entre accents graves, guillemets ou après `Login:`, est reconnue comme telle), elles ne donnent
pas les identifiants de l'autre compte de revue, que le bloc y annonce. Le journal l'écrit au pré-vol, donc aussi
en mode `verifier`, puis de nouveau à l'écriture ; la soumission continue. Qu'une adresse soit accompagnée de son
mot de passe ne se contrôle pas dans un texte libre : c'est une vérification à faire à la main (`LOT6_PLAN.md`
§3, action 3).

**Candidature sur le compte de démonstration.** Profil du soignant de revue en production, relevé en lecture seule
le 26-27/11/2026 (booléens et statuts seulement) :

- IDE, exercice `LIBERAL` ; SIRET au bon format mais **non vérifié** (`fn_soignant_liberal_actif_verifie` faux) ;
- **RPPS vérifié** : le serveur dispense alors du diplôme et du RPPS (`fn_documents_ok_pour_mission`, hors IADE et
  IBODE), et l'app les masque dans « Mes documents » (`ExigencesDocuments`) ;
- assurance RCP vérifiée ; carte d'identité, RIB et attestation URSSAF en revue manuelle.

Aucun faux document n'est fabriqué. Ce qui bloque vraiment l'acceptation d'une candidature salariée : **la carte
d'identité et le RIB**, en attente de vérification. Le bloc ne cite que cela :

> Applying needs validated documents (identity, bank details…); some are still under review on this demo account
> (Profil > Mon espace > "Mes documents"): an application is sent, but the facility cannot accept it until they
> are validated.

Le seul chemin atteignable aujourd'hui par ce compte, vérifié dans `ios-native/` et dans les fonctions du serveur :

- l'app affiche « Postuler », envoie la demande sans choix de contrat (`fn_confirmer_action_planning_v1`, puis
  `fn_postuler_mission_rate_limited`, puis `fn_postuler_mission`) ;
- sur une mission `TOUS`, un profil libéral non vérifié se résout en **salarié** (`fn_resoudre_contrat_mission`,
  branche « sinon ») : la candidature est enregistrée en attente, avec la notification « Complétez vos documents
  salariés » ;
- l'app affiche « ✅ Candidature envoyée — En attente de réponse », puis « Prochaine étape : validez vos documents
  pour que l'établissement puisse vous accepter. » et le bouton « 📄 Valider mes documents (2 min) » vers
  « Mes documents » (`CandidatureSection`) ;
- côté établissement, l'app renvoie l'acceptation d'une mission `TOUS` au site (`CandidaturesEtabRules`,
  `contratNonSalarie`), où `fn_finaliser_attribution_mission` refuse tant que les documents salariés ne sont pas
  validés.

**La branche libérale n'est pas atteignable par ce compte** : elle suppose un SIRET vérifié, et aucun choix de
contrat n'est proposé (`choixRequis` ne vient qu'à un profil `MIXTE` libéral vérifié). Si un choix libéral était
envoyé aujourd'hui, le refus viendrait de `fn_resoudre_contrat_mission` (« Votre profil libéral doit être actif,
avec SIRET et identité vérifiés. ») ; une fois le SIRET vérifié, de `fn_postuler_mission` (« Les documents
requis pour candidater en libéral sont manquants ou expirés. », la carte d'identité étant en revue). Le bloc n'en
parle donc pas.

Les trois missions (IDE, `TOUS`, sur candidature, à l'adresse de l'établissement de revue, à Paris, début entre
J+7 et J+21) sont créées et entretenues par la PR #1198 : la phrase « three demo assignments in Paris » n'est
vraie qu'une fois cette PR mergée et son cron passé. **Ordre à tenir** : merger #1198 et attendre son cron
avant le run `soumettre`.

**Autres arrêts.** Une version modifiable autre que `2.0.0` (deliver la renommerait, avec sa fiche) arrête la
lane au pré-vol. Une version distribuée au numéro non numérique, non antérieure à 2.0.0, deux versions au numéro
distribué maximal, ou un maximum autre que la coquille figée l'arrêtent aussi (« Choix de la source », ci-dessus).
Une version qui change entre le pré-vol et l'écriture, des identifiants différents de ceux connectés, une
fiche relue différente de la copie, ou des notes relues différentes de celles écrites, arrêtent la lane avant la
soumission.

**Si le verrou refuse.** Rien n'est soumis, et le pré-vol refuse avant toute écriture : avant de créer la version,
avant toute copie et avant toute annulation de revue. Si ni la 2.0.0 ni la version distribuée n'ont
d'identifiants qui se connectent sur un rôle admis, ils ne peuvent se saisir que par l'API
(`PATCH /v1/appStoreReviewDetails/{id}`, ou création de la fiche si elle manque), dans une étape distincte,
relue, qui ne met aucun identifiant dans le dépôt ni dans un journal. Ensuite, relancer le workflow entier,
d'abord en `verifier`.

**Changer le texte.** Modifier les deux fichiers `config/ios-review-notes-2.0-*.txt` par une PR (anglais, pas
d'adresse, pas de ligne de séparation, faits vérifiés dans `ios-native/`). À la soumission suivante, le bloc en
tête est remplacé par le nouveau. Une version déjà soumise n'est pas modifiée : la lane s'arrête sur « déjà
soumis » avant l'écriture.

**Libellés du bloc vérifiés dans `ios-native/` (26/11/2026).** Onglets soignant : Accueil, Explorer, Mes missions,
Revenus, Profil (`MainTabView.swift`). Suppression, soignant : section « Suppression de compte », bouton
« Supprimer mon compte » de l'onglet Profil (`CompteSuppression.swift`). Établissement : onglet Compte, section
« Aide & légal », entrée « Supprimer mon compte » (`RenvoisWebEtab.swift`), qui ouvre la page de suppression du
site jolene.app (connexion redemandée) : le bloc le dit. « Mot de passe oublié ? » est sur l'écran de connexion
(`LoginScreen.swift`). Paiements : établissements prélevés par SEPA, Jolene créancière du mandat, honoraires
versés au soignant par virement, hors de l'app (`docs/flux-monetaire-escrow.md`). Les données des comptes de
revue (trois missions à Paris, publication désactivée faute de vérification) ne se vérifient pas dans le code :
elles se vérifient sur les comptes eux-mêmes.

**Prouvé seulement au vrai run.** Le run `verifier` prouve, sans rien écrire : la lecture de la fiche et du mot de
passe par l'API (probable : `download_metadata` de deliver, `deliver/lib/deliver/setup.rb`, relit
`demo_account_password` par la même requête), la connexion et le rôle du compte, la longueur des notes de 1.0.7,
l'état des versions et le choix de la source parmi les versions distribuées (le premier run réel en a révélé
sept). Restent à prouver au run `soumettre` : qu'Apple réponde `data: null` pour une
version sans fiche (une erreur est tenue pour « illisible » et arrête la lane sans copie) ; qu'une version créée
par l'API reprenne ou non la fiche de 1.0.7 (les deux cas sont traités) ; qu'Apple accepte la création ou la copie
de la fiche, l'écriture de `demoAccountRequired` et celle des notes dans l'état de la version, sans rien modifier
d'autre ; le décompte exact des caractères chez Apple (marge de 100).

## Vérification locale

```bash
node --test tests/node/ios-native-app-store.node.mjs
node scripts/mobile/ios-native-app-store.mjs source .   # gardes lots, apple-4.2 et ota sur l'arbre courant
ruby fastlane/ios_review_submission.test.rb              # revue en cours et contexte des lanes
ruby fastlane/ios_review_notes.test.rb                   # notes, fiche et connexion simulée du compte de démonstration
```

Sur l'arbre de `main` au 26/11/2026, la deuxième commande passe : aucun port en attente, espace établissement
ouvert, Apple 4.2 et absence de mise à jour à chaud vérifiés. Les lanes elles-mêmes ne tournent que dans le
workflow.

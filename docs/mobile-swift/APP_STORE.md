# Soumission App Store de l'app Swift (`ios-native/`)

Workflow : `.github/workflows/ios-native-app-store.yml` (« iOS Swift — soumission App Store »).
Gardes : `scripts/mobile/ios-native-app-store.mjs`, testées par `tests/node/ios-native-app-store.node.mjs`
(job `validate-pr`, étape « Gardes de la soumission App Store »). Décisions : `DECISIONS_LOT6.md`.

## Ce que fait le workflow, et ce qu'il ne fait jamais

Il soumet à la revue Apple un build de l'app `app.jolene` (App Store Connect `6774672845`) **déjà envoyé
sur TestFlight** par `ios-native-testflight.yml` et déjà traité (`VALID`). Il active la publication
progressive sur sept jours et écrit le champ « Nouveautés » fr-FR.

Il ne fait **jamais** : de compilation, d'envoi de binaire, de modification des captures, de la
description, des notes pour la revue, de la confidentialité ou de la classification. Il ne part jamais
seul : ni push, ni PR, ni merge, ni fin d'un autre workflow ne le déclenchent.

Deux modes : `verifier` (défaut) joue toutes les gardes en lecture seule et s'arrête avant la lane et
avant le tag ; `soumettre` joue les mêmes gardes, puis soumet et pose le tag, et exige en plus la phrase de
confirmation. Lancer d'abord en `verifier` : c'est la répétition à blanc de la soumission.

## Avant de lancer

1. **Aucun port en attente, dans aucun lot (1 à 5)**, sur `main` : les cinq listes
   `DemoWorldTests.portsEnAttenteLot1` à `portsEnAttenteLot5` sont vides. **Au 24/11/2026, ce n'est pas le
   cas, et pas seulement pour les lots 4 et 5** : `portsEnAttenteLot1` contient encore `recovery`, la
   réinitialisation native du mot de passe (« Mot de passe oublié ? », `SupabaseRecoveryGateway`,
   `ResetPasswordScreen`), qui n'a de tranche ni au lot 1 ni au lot 3 (`DECISIONS_LOT3.md`, reste de
   L1-T10). Tant que `recovery` n'est pas câblé, la garde `lots` refuse toute soumission ; c'est voulu.
   Soumettre sans lui exigerait une décision écrite de la fondatrice et une PR qui modifie la garde.
2. Un build a été envoyé **depuis ce `main`** par `ios-native-testflight.yml` (build 32 ou plus), **il y a
   moins de 14 jours** (rétention de l'artefact de provenance, garde `provenance`). Notez son numéro.
3. Le dernier run de « iOS Swift — socle natif » (`ios-swift-ci.yml`) sur le commit dont ce build est issu
   est **vert** (garde `ci-ios`). Ce workflow ne tourne sur un push de `main` que si ses chemins changent,
   et un push suivant annule le run en cours : si le commit n'a pas de run vert, lancer
   `ios-swift-ci.yml` à la main sur `main` **avant** l'envoi TestFlight, au même commit.
4. Ce build a été recetté sur iPhone (`RECETTE_DEVICE_LOT4.md`, `RECETTE_DEVICE_LOT5.md`), dont les liens
   universels et le push de production.
5. Les saisies d'App Store Connect sont faites (`LOT6_PLAN.md` §3) : fiche, notes pour la revue et compte
   de démonstration, confidentialité, classification, captures.
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

- `gardes` (Ubuntu, lecture seule) : toutes les gardes ci-dessous, puis un verdict posé seulement si
  toutes ont réussi ; aucune de ses étapes n'est conditionnelle ;
- `soumettre` (macOS 26), en mode `soumettre` et sur verdict des gardes seulement : lane
  `fastlane ios submit_native` ;
- `consigner` (Ubuntu), après `soumettre` : tag `mobile-native-ios-N` sur le commit source du build.

En mode `verifier`, `soumettre` et `consigner` sont ignorés : rien n'est écrit chez Apple ni dans le dépôt.

Une seule soumission à la fois (groupe de concurrence `ios-native-app-store`, sans annulation).

**Toujours relancer le workflow entier** (« Re-run all jobs ») : « Re-run failed jobs » sur `soumettre`
ou `consigner` réutiliserait les sorties d'un job `gardes` plus ancien sans le rejouer. Les deux jobs, et
la lane, comparent donc la tentative des gardes à la tentative en cours et refusent tout écart.

## Les gardes

Chaque refus s'affiche sous la forme `[garde] message (voir docs/mobile-swift/APP_STORE.md, garde « … »)`
et arrête le workflow avant toute écriture chez Apple. Aucune garde ne se désactive par une option.

| Garde | Ce qu'elle vérifie | Si elle échoue |
|---|---|---|
| `entrees` | Déclenchement manuel sur `main` ; mode `verifier` ou `soumettre` ; numéro de build entier, supérieur à 24 et au moins égal à `ios.minimumBuildNumber` ; en mode `soumettre`, phrase de confirmation exacte ; mode de publication connu. | Corriger la saisie. Un build 25 à 31 ne se soumet pas : il précède la clôture des lots 4 et 5. |
| `notes` | `config/mobile-release-notes-ios.txt` existe, tient en 4 000 caractères, annonce la reconnexion et Face ID, sans texte provisoire. | Corriger le fichier par une PR. |
| dépôt | Les gardes statiques du TestFlight (`TESTFLIGHT.md`) : production, chiffrement exempté, manifeste de confidentialité, icône, entitlements. | Voir `TESTFLIGHT.md`. |
| `provenance` | `main` n'a pas avancé depuis le déclenchement ; un run réussi de `ios-native-testflight.yml`, lancé à la main depuis `main`, a produit l'artefact `ios-native-testflight-<N>-<commit>`, encore disponible ; ce commit appartient à l'historique de `main`. L'artefact est conservé **14 jours** (`retention-days` de `ios-native-testflight.yml`) : au-delà, le build ne se soumet plus, y compris pour une nouvelle soumission après un refus d'Apple, et le refus le dit (« a expiré », ou « introuvable » une fois purgé). | Relancer depuis le `main` courant. Artefact expiré ou purgé : refaire un envoi TestFlight et soumettre le nouveau build. |
| `ci-ios` | Le dernier run de `ios-swift-ci.yml` sur le commit source exact, sur `main` (push ou déclenchement manuel ; état de sa dernière tentative), est terminé et réussi. Le refus nomme le commit et la conclusion lue. Aucun run sur ce commit : refus, jamais de repli sur un ancêtre. | Lancer `ios-swift-ci.yml` sur `main` à ce commit et attendre le vert, ou envoyer un nouveau build depuis un commit dont la CI iOS est verte. |
| `lots` | Dans la source de ce commit, les cinq listes `DemoWorldTests.portsEnAttenteLot1` à `portsEnAttenteLot5` sont vides : aucun port en attente, dans aucun lot. Lecture stricte : commentaires retirés, une seule déclaration, un tableau de noms entre guillemets et rien qui le prolonge (`+`, `.filter`, `as`…) ; sinon la liste est « illisible » et la garde refuse. | Câbler les ports (aujourd'hui `recovery`, lot 1, et ceux des lots 4 et 5), puis envoyer un nouveau build. |
| `apple-4.2` | Dans la même source : ports `dashboard`, `mesMissions`, `presence`, `pointage` câblés ; fichiers des écrans natifs du tableau de bord, de Mes missions et du pointage présents ; onglets `tab-accueil` et `tab-missions` de `MainTabView.swift` qui montent `AccueilScreen` et `MesMissionsScreen` (pour le pointage, seuls la présence de son fichier et l'appel de `fn_scanner_code_pointage` sont contrôlés, pas son montage) ; RPC `fn_dashboard_soignant_complet` et `fn_scanner_code_pointage` appelées par le client Swift ; aucune vue web à la racine de l'app. | Ne pas soumettre : Apple refuse un site réemballé (règle 4.2). |
| `ota` | Aucun client de mise à jour à chaud (règle 2.5.2), cherché par nom dans les sources Swift de `Jolene/` et de `Packages/*/Sources`, **et** dans les `Package.swift`, `Package.resolved` et `project.yml` de `ios-native/` ; au moins un `Package.swift` et un `Package.resolved` doivent être lus. C'est une liste de noms interdits, pas une liste de dépendances admises. | Retirer la dépendance. |
| backend | Le dernier déploiement Supabase de production est vert et couvre le backend de `main` (`delivery-plan-backend.mjs`). | Attendre ou réparer `deploy-supabase`. |
| `build` | Dans App Store Connect : un seul build `N`, `VALID`, non expiré, `usesNonExemptEncryption = false`, version `2.0.0`, plateforme iOS ; version supérieure à 1.0.7, build supérieur à 24. | Attendre la fin du traitement, ou envoyer un nouveau build. |
| revue en cours | Dans la lane (`fastlane/ios_review_submission.rb`) : version supérieure à la version en vente ; une soumission encore « en attente de revue » pour un build plus ancien est annulée puis remplacée ; une revue commencée (`IN_REVIEW`) n'est jamais interrompue. | Lire le message : la revue en cours est préservée. |

## Secrets et droits

Trois secrets, ceux du TestFlight : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`. Aucun
matériel de signature n'est lu. Droits du jeton GitHub : lecture seule, sauf le job `consigner` qui pose
le tag. Les entrées passent par des variables d'environnement, jamais par interpolation dans un script ;
la phrase saisie n'est pas réaffichée. Les actions sont épinglées par leur commit.

**La lane hors du workflow.** `fastlane ios submit_native` refuse de tourner hors du job `soumettre` de
ce workflow sur `main` (contexte GitHub Actions, `workflow_dispatch`, `GITHUB_WORKFLOW_REF` de ce
fichier), sans le mode `soumettre`, sans le verdict des gardes de la même tentative, ou sans la phrase
exacte (`IosReviewSubmission.exiger_contexte_workflow!`, `fastlane/ios_review_submission.rb`). Ce sont
des contrôles de contexte : ils arrêtent une lane lancée par erreur depuis un poste ou un autre workflow,
pas une personne qui détient la clé App Store Connect et appelle l'API d'Apple directement. La vraie
protection est la garde de la clé : elle ne doit exister nulle part ailleurs que dans les secrets GitHub.

**Action du propriétaire du dépôt, non faite (réglage hors code).** « Depuis `main` seulement » n'est
garanti que par le fichier : un `workflow_dispatch` sur une autre branche exécute la copie du workflow de
cette branche, avec les mêmes secrets de dépôt ; une copie modifiée ne refuserait plus rien (il faut un
accès en écriture au dépôt). Pour le garantir côté GitHub : créer un environnement (par exemple
`app-store`) dont les règles de déploiement n'admettent que la branche `main`, y déplacer les secrets
`ASC_KEY_ID`, `ASC_ISSUER_ID` et `ASC_PRIVATE_KEY_BASE64` (et, pour `ios-native-testflight.yml` et
`mobile-delivery.yml`, les secrets de signature et de Google Play), puis déclarer `environment:` sur les
jobs qui les lisent, dans une PR. Tant que ce réglage n'est pas fait, cette limite demeure.

## Après la soumission

- « Soumis », « approuvé » et « en vente » sont trois états distincts : le tag prouve la soumission.
- Suivre l'état par `mobile-store-status.yml` (lecture seule) ou dans App Store Connect.
- Relancer le workflow avec le même build ne soumet pas deux fois : si ce build est déjà soumis (en
  attente de revue ou en revue) ou déjà en vente, la lane s'arrête sur « déjà soumis » et le job finit vert.
  **Exception** : en publication `manuelle`, une fois la version approuvée (« Pending Developer
  Release »), la lane lève une erreur (`ios_review_submission.rb`) et le job finit **rouge** : rien n'a
  été changé chez Apple ; la mise en vente se fait par le bouton « Release this version ».
- Pour remplacer un build en attente de revue par un build plus récent, relancer avec le nouveau numéro.
- Publication progressive : 1 %, 2 %, 5 %, 10 %, 20 %, 50 % puis 100 % sur sept jours ; pause possible
  jusqu'à 30 jours ; chacun peut toujours mettre à jour à la main depuis l'App Store.
- Après la mise à jour, chaque utilisateur se reconnecte une fois et réactive Face ID (plan §6). Le taux
  de reconnexion se suit par `fn_audit_connexion`.

## Brouillon de notes pour la revue

À adapter à l'état réel de l'app à la clôture du lot 5, puis à saisir dans App Store Connect. Les
identifiants des comptes de revue se saisissent dans les champs sécurisés, jamais dans le dépôt
(`docs/STORE_METADATA_FR.md`).

> Jolene 2.0 est une réécriture native (Swift) de l'application. Elle remplace la version 1.0.7.
>
> Jolene est une plateforme professionnelle de remplacement en santé. Les comptes de revue contiennent
> des données de démonstration.
>
> Compte soignant : tableau de bord, recherche de missions, candidature, Mes missions, documents,
> contrats, revenus, compte. Compte établissement : tableau de bord, missions, candidatures, présences.
> Les comptes administrateur et groupe sont renvoyés vers le site jolene.app : leur espace n'existe pas
> dans l'application.
>
> Le pointage demande la position (au premier plan seulement) et un code affiché sur place par
> l'établissement : il ne peut pas être terminé hors d'un établissement. La caméra n'est demandée que
> pour photographier un document ou scanner un code. Le paiement, la signature par SMS et Pro Santé
> Connect ne doivent pas être menés à leur terme par la revue.
>
> La suppression du compte se lance depuis l'application, dans les réglages du compte (indiquer ici le
> chemin exact des écrans).

## Vérification locale

```bash
node --test tests/node/ios-native-app-store.node.mjs
node scripts/mobile/ios-native-app-store.mjs source .   # gardes lots, apple-4.2 et ota sur l'arbre courant
ruby fastlane/ios_review_submission.test.rb              # revue en cours et contexte de la lane
```

Sur l'arbre actuel, la deuxième commande refuse sur la garde `lots` (`recovery` au lot 1, ports des lots
4 et 5) : c'est l'état attendu tant que les lots ne sont pas clos.

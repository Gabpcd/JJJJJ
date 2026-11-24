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

## Avant de lancer

1. Les lots 4 et 5 sont sur `main` et un build a été envoyé **depuis ce `main`** par
   `ios-native-testflight.yml` (build 32 ou plus). Notez son numéro.
2. Ce build a été recetté sur iPhone (`RECETTE_DEVICE_LOT4.md`, `RECETTE_DEVICE_LOT5.md`), dont les liens
   universels et le push de production.
3. Les saisies d'App Store Connect sont faites (`LOT6_PLAN.md` §3) : fiche, notes pour la revue et compte
   de démonstration, confidentialité, classification, captures.
4. `config/mobile-release-notes-ios.txt` contient le texte voulu pour « Nouveautés ».

## Lancer la soumission

GitHub → Actions → « iOS Swift — soumission App Store » → *Run workflow*, branche `main` :

- **Numéro du build** : celui du build TestFlight, par exemple `32`.
- **Confirmation** : écrire exactement `SOUMETTRE 2.0.0 (N)` en remplaçant `N` par le numéro du build
  (pour le build 32 : `SOUMETTRE 2.0.0 (32)`). Toute autre saisie arrête le workflow.
- **Publication** : `automatique` (mise en vente dès l'approbation) ou `manuelle` (la version attend en
  « Pending Developer Release » jusqu'au clic « Release this version »). Progressive dans les deux cas.

Trois jobs s'enchaînent :

- `gardes` (Ubuntu, lecture seule) : toutes les gardes ci-dessous ;
- `soumettre` (macOS 26) : lane `fastlane ios submit_native` ;
- `consigner` (Ubuntu) : tag `mobile-native-ios-N` sur le commit source du build.

Une seule soumission à la fois (groupe de concurrence `ios-native-app-store`, sans annulation).

## Les gardes

Chaque refus s'affiche sous la forme `[garde] message (voir docs/mobile-swift/APP_STORE.md, garde « … »)`
et arrête le workflow avant toute écriture chez Apple. Aucune garde ne se désactive par une option.

| Garde | Ce qu'elle vérifie | Si elle échoue |
|---|---|---|
| `entrees` | Déclenchement manuel sur `main` ; numéro de build entier, supérieur à 24 et au moins égal à `ios.minimumBuildNumber` ; phrase de confirmation exacte ; mode de publication connu. | Corriger la saisie. Un build 25 à 31 ne se soumet pas : il précède la clôture des lots 4 et 5. |
| `notes` | `config/mobile-release-notes-ios.txt` existe, tient en 4 000 caractères, annonce la reconnexion et Face ID, sans texte provisoire. | Corriger le fichier par une PR. |
| dépôt | Les gardes statiques du TestFlight (`TESTFLIGHT.md`) : production, chiffrement exempté, manifeste de confidentialité, icône, entitlements. | Voir `TESTFLIGHT.md`. |
| `provenance` | `main` n'a pas avancé depuis le déclenchement ; un run réussi de `ios-native-testflight.yml`, lancé à la main depuis `main`, a produit l'artefact `ios-native-testflight-<N>-<commit>` ; ce commit appartient à l'historique de `main`. | Relancer depuis le `main` courant. Si l'artefact a disparu (purge de GitHub), refaire un envoi TestFlight et soumettre le nouveau build. |
| `lots` | Dans la source de ce commit, `DemoWorldTests.portsEnAttenteLot4` et `portsEnAttenteLot5` sont vides : les lots 4 et 5 sont clos. | Terminer les lots, puis envoyer un nouveau build. |
| `apple-4.2` | Dans la même source : ports `dashboard`, `mesMissions`, `presence`, `pointage` câblés ; écrans natifs du tableau de bord, de Mes missions et du pointage présents et montés par les onglets ; RPC `fn_dashboard_soignant_complet` et `fn_scanner_code_pointage` appelées ; aucune vue web à la racine de l'app. | Ne pas soumettre : Apple refuse un site réemballé (règle 4.2). |
| `ota` | Aucun client de mise à jour à chaud dans l'app Swift (règle 2.5.2). | Retirer la dépendance. |
| backend | Le dernier déploiement Supabase de production est vert et couvre le backend de `main` (`delivery-plan-backend.mjs`). | Attendre ou réparer `deploy-supabase`. |
| `build` | Dans App Store Connect : un seul build `N`, `VALID`, non expiré, `usesNonExemptEncryption = false`, version `2.0.0`, plateforme iOS ; version supérieure à 1.0.7, build supérieur à 24. | Attendre la fin du traitement, ou envoyer un nouveau build. |
| revue en cours | Dans la lane (`fastlane/ios_review_submission.rb`) : version supérieure à la version en vente ; une soumission encore « en attente de revue » pour un build plus ancien est annulée puis remplacée ; une revue commencée (`IN_REVIEW`) n'est jamais interrompue. | Lire le message : la revue en cours est préservée. |

## Secrets et droits

Trois secrets, ceux du TestFlight : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`. Aucun
matériel de signature n'est lu. Droits du jeton GitHub : lecture seule, sauf le job `consigner` qui pose
le tag. Les entrées passent par des variables d'environnement, jamais par interpolation dans un script ;
la phrase saisie n'est pas réaffichée. Les actions sont épinglées par leur commit.

## Après la soumission

- « Soumis », « approuvé » et « en vente » sont trois états distincts : le tag prouve la soumission.
- Suivre l'état par `mobile-store-status.yml` (lecture seule) ou dans App Store Connect.
- Relancer le workflow avec le même build ne soumet pas deux fois : la lane s'arrête sur « déjà soumis ».
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
```

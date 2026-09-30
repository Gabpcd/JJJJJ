# Anonymisation de l’auteur d’une notation après fermeture du compte

## Défaut reproduit en CI

La CI SQL de `849f7db8fc19696dc821a74aab12382351927560` (run `36741951997`, job `109978302372`) échoue avec `23502` : le trigger existant `fn_trg_anonymiser_notations_suppression` écrit `notateur_id = NULL` mais cette colonne impose `NOT NULL`. L’assertion d’origine dans `notation-reverse-transactionnelle.test.sql` reste inchangée. Le correctif de fixture administrateur de `849f7db8` est conservé.

La lecture ciblée du catalogue LIVE a confirmé ce conflit pour les deux déclencheurs, soignant et établissement. Elle a aussi établi que l’ancienne comparaison d’auteur de `fn_modifier_notation_mission` laissait passer une valeur NULL. Le signalement doit conserver sa cible non NULL et refuser un compte fermé dont le JWT est encore vivant.

## Correction bornée

La migration `20260930161816` autorise un auteur NULL uniquement si `notateur_anonymise IS TRUE`. Elle garde `note_id NOT NULL`, les notes, leurs critères et commentaires, les destinataires, la publication différée, les délais, les triggers et les politiques RLS. Elle ne définit aucune nouvelle politique de conservation ou de purge.

Les deux RPC vérifient le compte actif avant le lookup et sélectionnent uniquement une note autorisée, avec comparaison NULL-safe et verrou de ligne. L’auteur ou son membre canonique conserve la modification ; un véritable administrateur conserve son droit préexistant de modification. Le signalement reste réservé au destinataire canonique, sans nouveau privilège admin. Les tiers reçoivent le même refus pour une note existante, absente ou un identifiant NULL.

Le préflight refuse une définition, une ACL ou une entrée d’inventaire inattendue. Aucun `GRANT` n’est modifié. Empreintes `md5(prosrc)` :

| Fonction | LIVE avant | Après |
|---|---|---|
| `fn_modifier_notation_mission` | `519608bb01e325189ce23f860d9e2794` | `63f28d2ca3ad4580538aa7de55020edb` |
| `fn_signaler_notation` | `2cc5ec80ff301f99ae0e488e9e0578b0` | `4f58a286981573d8b1096568af11d2f8` |
| Trigger d’anonymisation | `c1075608a0b29574cd78451c8e9e703d` | Inchangée |

## Preuve SQL préparée

`tests/security/notation-anonymisation-compte.test.sql` est raccordé à la liste explicite du workflow. Il crée sept identités fictives, trois missions terminées et cinq notes via la vraie RPC de création. Il exerce ensuite les **deux vrais wrappers de suppression**, une seconde fois pour vérifier leur idempotence. Les comptes Auth demeurent présents et non bannis dans cette transaction : l’interdiction après fermeture dépend donc bien de l’état applicatif.

Assertions : membre RH autorisé avant fermeture puis toujours authentifié mais sans tenant canonique ; refus tiers, sans profil, UID NULL et comptes fermés ; impossibilité d’anonymiser directement par UPDATE RLS ; CHECK auteur NULL et NOT NULL de la cible ; limite de modification de sept jours ; auteur anonymisé modifiable par admin réel, signalable par sa cible active ; refus du doublon ; notes publiées accessibles à la cible et note non réciproque toujours masquée ; cinq notes conservées, témoins et contenus inchangés, reçus privés confirmés, audit attribué à l’admin.

Un sous-bloc transactionnel annule les fixtures avec une sentinelle contrôlée par **code et message**, puis vérifie l’absence de résidus, même si le runner CI retire le BEGIN/ROLLBACK extérieur. Aucun appel métier distant, aucune suppression Auth distante n’a été exécuté pendant la préparation.

**Limite :** le parsing local (migration : 8 instructions SQL / 5 corps PL/pgSQL ; test : 3 / 1) ne constitue pas une exécution PostgreSQL. La CI devra démontrer ces assertions. Une concurrence réelle de sessions n’est pas simulée dans cette suite.

## Simulation frontend

Le scénario `e2e/recette-complete-notation-suppression.spec.ts` utilise les routes réelles « Mon compte », puis les écrans de confidentialité/sécurité, pour les deux familles. Il vérifie annulation sans appel, confirmation obligatoire, refus explicite, texte de confirmation conservé, réessai avec bouton désactivé, succès, déconnexion puis refus des routes privées après deux rechargements. Trois appels Edge exacts par parcours : un refus métier, un refus HTTP 503 dont le corps anglais `Failed to fetch` déclenche une véritable erreur SDK, puis un succès. Le message utilisateur reste français et la confirmation demeure ouverte avec sa saisie.

La preview dédiée est compilée depuis cette branche, avec clé fictive et URL API loopback. HTTP, Auth et WebSockets sont simulés ; les sorties non prévues échouent. Toutes les sorties console restent conservées : exactement une erreur de chargement HTTP 503 volontaire est attendue ; aucun autre console error, warning, pageerror ou endpoint inconnu n’est admis. La capacité Service Worker est explicitement absente : cette preuve ne couvre ni PWA, ni push, ni suppression Auth réelle, ni appareil physique. La conservation des notes repose sur la preuve SQL distincte, pas sur le mock frontend.

Commandes :

```sh
node_modules/.bin/tsc -b
node_modules/.bin/tsc --noEmit --skipLibCheck --moduleResolution bundler --module ESNext --target ES2022 --types node e2e/recette-complete-notation-suppression.spec.ts
actionlint .github/workflows/validate-pr.yml
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18468 RECETTE_RESULTS_DIR=/private/tmp/jolene-notations-anonymisation-20260930/ui-final node_modules/.bin/playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-notation-suppression.spec.ts e2e/recette-complete-soignant-compte.spec.ts --grep 'annuler, refuser|suppression compte annulée'
```

La matrice finale du 2026-09-30T16:43:35.838Z passe **15/15** : dix nouveaux cas (deux familles × cinq formats) et cinq cas du scénario soignant préexistant. Zéro skip, retry ou flaky. Les dix nouveaux cas enregistrent chacun le seul 503 volontaire, zéro autre erreur console, zéro warning, pageerror, requête inconnue ou sortie externe. Les captures des deux parents sur iPhone, ainsi que les rendus iPad, Android et ordinateur, ont été inspectés.

Résultats et limites de cette révision sont conservés dans `audits/2026-09-30-preparation-nationale/preuves/notation-anonymisation-compte/` du workspace racine, avec manifeste SHA256. Les traces des premiers essais restent dans `/private/tmp/jolene-notations-anonymisation-20260930/`.

La première passe ordinateur a échoué deux fois dans le test : le bouton était déjà désactivé avant réception de la requête par le mock. Une attente explicite du compteur de transport a corrigé cette course de fixture ; aucun sleep, filtre, retry automatique ou changement produit. Les traces initiales sont conservées.

L’ajout du refus SDK a reproduit un défaut soignant : la confirmation se fermait après une erreur technique, avec un toast extérieur. Les deux parents affichent maintenant l’erreur dans le formulaire (`role=alert`) et gardent la saisie ; champ, Annuler et confirmation restent désactivés pendant l’appel. Le soignant ne ferme automatiquement sa confirmation qu’après succès. Les textes contractuels et les API sont inchangés. L’ancien scénario de suppression soignant attend désormais le formulaire conservé plutôt que sa réouverture.

Les unités vérifient 14 cas sur les deux parents (refus métier, SDK anglais, JWT expiré, réponse vide, exception réseau, double clic et reprise) ; les cinq tests SEPA préexistants restent verts. Le message de production est testé avec `DEV=false`, car le traducteur expose volontairement le détail brut en développement. `tsc -b`, typecheck E2E ciblé, actionlint et diff-check sont verts.

La relecture croisée par `revue_export_201` n’a repéré aucun P1/P2 sur migration, catalogue, suite SQL, deux formulaires, unités et spec UI. Elle ne vaut pas revue B8 fraîche ; SQL réel et CI restent à confirmer avant merge.

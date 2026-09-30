# Banc dashboard E10 — 30 septembre 2026

E utilisait une identité et un JWT pour tous les VUs. E10 prépare dix profils AS
minimaux distincts ; à 100 VUs, dix VUs utilisent chaque identité. Le contrat de
chaque réponse contrôle le profil attendu, et dix compteurs indépendants exigent
qu'ils aient tous été mesurés. Les dix séries `dashboard_duree_profil_0` à `_9` conservent aussi les latences,
y compris celles des réponses refusées. Les seuils p95/p99 et HTTP existants restent
inchangés. Aucun profil vérifié, historique, document ou paiement n'est créé.

## Préparation et nettoyage

Le nouvel orchestrateur réutilise le préparateur unitaire et ses mêmes SQL,
empreintes de triggers, refus de cron actif et gardes de notifications. Les
comptes sont créés séquentiellement via Auth Admin avec `email_confirm=true`,
sans signup ni invite. Chaque membre a un sous-run et un UUID déterministes.

Le manifeste global existe avant le premier POST Auth ; chaque manifeste membre
précède sa création. Les états individuels sont conservés après une réponse
perdue. Le nettoyage contrôle le lot entier avant toute suppression, poursuit
les membres sûrs si l'un échoue, et garde l'état global `partial` jusqu'à
confirmation complète. Il ne supprime jamais un autre compte par préfixe.
Un membre commencé exige zéro Auth, profil et préférence ; un membre
`not-started` n'a pas émis de POST. Une création ambiguë encore absente reste un
échec à contrôler, même si les autres membres ont été nettoyés.

Le JSON de mots de passe n'est écrit que dans `GITHUB_ENV`, après préparation
complète ; mots de passe masqués et aucun JWT dans les manifests ou résumés.
Le nombre attendu de profils dans le résumé n'est pas une preuve de réussite :
les dix compteurs et tous les seuils doivent passer.

## Vérifications locales

- 86/86 tests Node du banc : scripts k6 réels avec HTTP en mémoire, cent VUs
  attribués aux dix JWT, refus du profil voisin, pool complet obligatoire,
  échecs de création/SQL/login aux membres 1/5/10, interruptions et reprise du
  cleanup, membre modifié/dépendance, manifeste altéré et dix secrets-canaris.
- TypeScript, build frontend, ESLint ciblé, syntaxe Node, actionlint incluant
  shellcheck et contrôle du diff : réussis.
- Simulation frontend locale **10/10 verte** : deux profils issus du même générateur de
  manifeste, sur cinq formats. Connexion par email propre au membre, dashboard,
  ouverture du compte, nom/UUID attendu et rechargement ; absence du nom du
  voisin, contrôle des requêtes de profil, erreurs et débordement horizontal.
  Les réponses API de cette simulation sont entièrement fictives.

Résultats locaux : `/private/tmp/jolene-dashboard-e10-node.txt` et
`/private/tmp/jolene-dashboard-e10-ui-final/results.json` ; captures et arbres
accessibles dans le dossier frontend. Le premier essai conservé sous
`/private/tmp/jolene-dashboard-e10-ui` utilisait à tort le nom d'onglet mobile
« Menu » ; la recette utilise maintenant son nom réel « Profil ».

Les gardes SQL du préparateur unitaire n'ont pas été modifiées ; leur preuve
PGlite historique reste distincte d'un nouvel exercice staging complet. Aucun
test SQL local ancien n'est présenté comme une nouvelle exécution.

## Campagne staging restant à exécuter

Aucun appel staging, compte réel de recette ni charge n'a été lancé pour ce lot.
Le workflow est manuel. Après revue et validation des volumes par le responsable,
une première exécution E avec `dashboard_fixture_only=true` prépare, préflighte
et nettoie les dix membres **sans k6**. Une mesure distincte E100/1 min pourra
suivre, en consignant révision, seuils, dix compteurs et cleanup. Un smoke E10
nécessite dix VUs minimum, afin d'exercer tous les slots.

Volumes nominaux : dix comptes/profils/préférences, 50 appels de préparation,
50 de nettoyage ; vingt appels de setup supplémentaires pour la mesure. Les
cent VUs ne se connectent pas simultanément : ils réutilisent dix sessions. Le
verrou `jolene-supabase-staging-writes` reste partagé avec déploiement staging et
SQL CI. Ne pas contourner sa sérialisation pour préparer le lot en parallèle.

En cas d'arrêt brutal du runner, le cleanup `always()` peut ne pas se terminer :
conserver les manifests non sensibles disponibles et reprendre le cleanup exact
avec la même révision/run et les accès staging existants. Ne pas marquer le run
vert sur la seule disparition du job, ni relancer sa préparation.

**Limite frontend intégrée :** aucune navigation de deux utilisateurs réels
staging pendant k6 n'est prouvée. Il faut une preview reliée au staging, les deux
sessions éphémères du lot et le contrôle des écritures d'audit/activité suscitées
par le vrai frontend avant de les ajouter au nettoyage. Le workflow k6 actuel
n'installe ni ne lance un navigateur connecté ; les simulations locales ne
remplacent pas cette preuve. Aucun appareil physique n'a été testé ici.

Le résultat attendu reste une mesure de dix profils sans historique. Ni le
passage des tests locaux ni un éventuel E100 vert ne garantissent une capacité
nationale ou une charge métier mixte ; D/F demeurent suspendus.

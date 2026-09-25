# Tests de charge API — état au 25 septembre 2026

Les scripts ciblent exclusivement le staging `mejpriaetwgtcstbgfid`. La garde dans `tests/load/helpers/auth.js` refuse toute autre URL, sans repli vers la production. Ils ne mesurent pas le rendu de l’app, les images par seconde, les appareils physiques ni la capacité du frontend Vercel.

Le durcissement du 25 septembre est validé par des **tests des scripts avec un transport en mémoire**. Il ne constitue pas un résultat de charge : les mesures k6 effectives doivent être jointes après une campagne staging réussie.

## Scénarios et état réel

| Scénario | Charge par défaut | Preuve recherchée | État |
| --- | --- | --- | --- |
| A — inscription Auth | Rampe vers 100 VUs, plateau 1 min | Réponses de `/auth/v1/signup` ; capacité Auth seulement | Disponible, crée des comptes ; vérifier l’isolation email avant exécution. Ne prouve ni le dossier métier ni RPPS. |
| B — connexion | Rampe vers 50 VUs, plateau 1 min | Password grant sur les deux comptes fixes staging | Disponible ; deux identités répétées, pas 50 utilisateurs distincts. |
| C — recherche publique | Rampe vers 200 VUs, plateau 90 s | Réponses JSON valides, HTTP et latence de la RPC publique | Lecture seule, préflight peuplé obligatoire. |
| D — candidatures simultanées | Ancienne cible : 50 soignants sur une mission | Candidatures effectivement créées, unicité, refus justifiés | **Suspendu : échec explicite avant toute requête.** |
| E — dashboard | Rampe vers 100 VUs, plateau 1 min | Profil et données métier valides, HTTP et latence de la RPC | Lecture métier seule après connexion, préflight profil obligatoire. |
| F — facturation hebdomadaire | Ancienne cible : 500 missions | Factures exactes du lot après un traitement isolé | **Suspendu : échec explicite avant toute requête.** |

`all` inclut D et F et doit donc échouer tant que leur isolation n’est pas rétablie. Pour les premières mesures, lancer C puis E individuellement. Aucun faux résultat vert n’est substitué aux scénarios suspendus.

## C — recherche publique avec des données

`03-recherche-missions.js` utilise `fn_missions_publiques_recherche(p_profession, p_ville)` avec la clé publique staging. Il ne crée aucune mission.

Le préflight doit obtenir au moins une mission publique valide sans filtre. Le schéma vérifié inclut identifiant, titre, profession, dates, taux numérique et `total_count`. Une réponse HTTP 200 contenant `null`, un objet erreur ou un tableau mal formé échoue. Ensuite, une requête sur cinq répète la recherche sans filtre et exige le volume attendu (`LOAD_TEST_EXPECTED_MISSIONS`, au moins 1 hors préparation CI) ; les autres utilisent des professions actuelles et villes variées, où un tableau vide est légitime.

La fixture doit respecter les règles existantes de publication. Les missions dont le titre commence par `[` et les établissements `est_compte_test=true` sont exclus par la RPC : le seed historique `[loadtest]` ne satisfait pas ce préflight. Préparer des données **uniquement dans le staging isolé**, sans modifier les règles de visibilité du produit pour les tests. Le nombre de missions visibles est consigné dans le journal ; une petite fixture ne démontre pas le comportement d’un catalogue national.

### Préparer et nettoyer un catalogue quantifié

`scripts/ci/prepare-load-fixtures.mjs` prépare **500 missions par défaut**, bornées entre 100 et 1000, réparties entre 10 établissements fictifs dans 10 villes et 10 professions (100 combinaisons). Les départs sont compris entre J+14 et J+27. Les établissements et titres portent `RECETTE CHARGE <run>` ; les contacts sont sous `example.invalid`. Aucun compte Auth, soignant assigné, pièce, signature, facture ou règlement n’est créé.

Le script exige simultanément la ref et l’URL exactes du staging, un identifiant de run explicite, l’accès Management API déjà existant et la clé anonyme staging. Variables : `LOAD_TEST_RUN_ID` (run GitHub + tentative conseillés), `LOAD_FIXTURE_COUNT` (défaut 500), `LOAD_FIXTURE_MANIFEST` (défaut `tests/load/results/fixture-missions-manifest.json`). Les secrets ne sont jamais écrits dans le manifeste.

```bash
node scripts/ci/prepare-load-fixtures.mjs prepare
# lancer ensuite le scénario C
node scripts/ci/prepare-load-fixtures.mjs cleanup
```

L’intégration CI doit exécuter le nettoyage dans une étape `always()` après C, même si la préparation ou k6 a échoué. Le manifeste est écrit **avant** l’appel SQL et reste conservé si la réponse est ambiguë. Il contient tous les UUID déterministes du run ; un manifeste modifié ou remplacé est refusé. Les runs sont sérialisés par le groupe de concurrence staging existant.

Préparation et nettoyage prennent aussi le **même verrou SQL transactionnel par run**, avant toute lecture ou écriture. Le nettoyage attend donc une préparation encore en vol. Une réponse réseau perdue, un timeout de verrou ou un HTTP transitoire autorisent au maximum trois tentatives de nettoyage ; la préparation ambiguë n’est jamais rejouée automatiquement. Sans confirmation, le manifeste reste intact et l’étape échoue.

Pour fermer également le cas d’une requête de préparation retardée avant son arrivée en base, le nettoyage écrit sous ce verrou un reçu dans `journaux_audit`, même si aucune fixture n’existe encore. Son UUID est déterministe par run ; toute préparation ultérieure du même run est refusée. Le reçu utilise les valeurs autorisées `action=SYSTEM`, `type_acteur=SYSTEME`, `acteur_id=NULL` et `details.evenement=RECETTE_CHARGE_NETTOYEE` avec le run et la ref staging. **Un reçu immuable reste volontairement après nettoyage**, sans donnée personnelle ni secret. Aucun DDL ni modification/suppression de journal n’est exécuté. Un nouveau lot exige un nouvel identifiant de run.

La préparation exige qu’aucun cron ne soit actif sur staging. `session_replication_role=replica` est limité à la transaction de préparation pour éviter les déclencheurs de notification/génération ; aucun trigger global n’est modifié. Les contraintes CHECK restent actives, les seuls liens fournis mission→établissement du lot sont vérifiés, puis le rôle `origin` est rétabli avant la lecture de contrôle. Les critères de publication de la RPC restent inchangés : `est_compte_test=false`, établissement fictif `VERIFIE`, publication autorisée, titre sans crochet. Cela ne valide aucun établissement ni document réel.

Après commit, une véritable requête HTTP **anonyme** doit retrouver tous les IDs du lot. Le script exporte alors le minimum attendu vers k6. Le cleanup conserve les FK actives, supprime uniquement les IDs et marqueurs du manifeste, refuse une mission assignée/modifiée ou une dépendance métier ajoutée, et doit constater **zéro mission et zéro établissement du run restants**. Il ne supprime jamais une cohorte par un `LIKE` global.

Le rôle Management doit pouvoir lire le journal sans filtrage RLS (`BYPASSRLS` ou superuser) ; le script refuse autrement. L’inspection staging du 25 septembre confirme que l’unique trigger d’insertion du journal ignore cet événement ; tout autre trigger d’insertion fait échouer la préparation/nettoyage. La confirmation de suppression et l’écriture du reçu ont lieu dans la transaction verrouillée, avant commit.

Définition live lue sur production et staging le 25 septembre : recherche identique, sans paramètre de pagination ni `LIMIT` dans son corps. Aucun changement de pagination n’est introduit avant une mesure démontrant un problème. Le test porte donc explicitement sur le catalogue quantifié retourné par la RPC existante.

Seuils : zéro contrôle fonctionnel échoué, au moins une itération ; HTTP échoué < 1 %, p50 < 400 ms, p95 < 1 s et p99 < 2 s.

## E — dashboard avec profil métier

`05-dashboard-concurrent.js` se connecte avec le compte soignant fixe staging, puis vérifie `fn_dashboard_soignant_complet()` avant la charge. Un compte `auth.users` sans profil `soignants`, un objet `{error: ...}`, `null` ou une structure incomplète échouent explicitement.

Le même JWT utilisateur est réutilisé par les VUs. Cela mesure des lectures concurrentes d’un seul profil avec son jeu de données ; cela **ne représente pas cent profils distincts**. Le login de setup crée une session d’authentification ; aucune mutation de mission, contrat, présence ou paiement n’est exécutée.

Seuils : zéro contrôle fonctionnel échoué, au moins une itération ; HTTP échoué < 1 %, p95 < 2 s et p99 < 3,5 s.

## Paramètres du workflow

Le workflow manuel `.github/workflows/load-tests.yml` fournit `LOAD_TEST_VUS` et `LOAD_TEST_DURATION`. Les scénarios A, B, C et E passent désormais par `helpers/options.js` et consomment réellement ces valeurs.

- VUs : entier de 1 à 999. Si seule cette valeur est indiquée, elle remplace les cibles non nulles de la rampe.
- Durée : entier positif suivi de `s` ou `m`, au maximum 15 minutes par scénario.
- Si une durée est indiquée, le scénario utilise des VUs constants pendant **cette durée totale**, sans ajouter une rampe cachée. Sans override VUs, la cible maximale habituelle est utilisée.
- Sans paramètres, les rampes historiques sont conservées.
- Les contrôles `checks: rate==1` et `iterations: count>0` sont obligatoires. Un `check()` faux rend la campagne rouge même si la réponse HTTP est 200.

Pour un smoke prudent de C ou E : 2 VUs pendant 10 s. Ce smoke vérifie le banc et les contrats API ; ce n’est pas une mesure de capacité nationale. Augmenter ensuite selon le volume autorisé et conserver le nombre de VUs, la durée et le volume de données avec chaque résultat.

## Pourquoi D et F sont suspendus

D créait des comptes Auth sans garantir de profils soignants éligibles, ignorait des logins échoués puis pouvait conclure à « zéro doublon » sur **zéro candidature**. Le script faisait aussi des créations/suppressions hors d’un lot identifié par run. Sa remise en service nécessite un lot de profils métier contrôlés, une mission isolée, des requêtes de candidature correspondant au frontend courant, et un contrôle du nombre exact de candidatures créé par rapport aux tentatives attendues. Un refus total ne peut pas prouver une course de candidatures réussie.

F acceptait zéro mission, invoquait le cron global de facturation, puis lisait le nombre total de factures sans le relier au lot. Sa remise en service nécessite une sélection exacte des missions réellement facturables, un état avant/après par identifiant, et l’isolation des envois email/paiement des prestataires. Le script actuel échoue avant tout appel de cron, y compris si `setup` est désactivé. Aucun succès n’est annoncé et le JSON porte `preuve_metier: false`.

Le seed SQL historique n’est pas une preuve de dossier éligible ou de mission facturable. Ne pas l’exécuter automatiquement pour lever cette suspension : il doit être revu séparément avec le schéma courant et les garde-fous métier.

## Vérification locale sans réseau

```bash
node --test tests/node/load-tests.node.mjs tests/node/prepare-load-fixtures.node.mjs
```

Les 16 tests de charge et les 19 tests du préparateur (35 au total) vérifient les paramètres et les seuils, chargent les vrais scripts avec un transport HTTP en mémoire, et couvrent les réponses incorrectes, les préflights vides/incomplets, le refus de production ainsi que l’absence de requête de D/F. Les erreurs injectées couvrent un commit tardif après timeout, le réessai borné et la conservation du manifeste. Ils ne génèrent aucun compte ni mail et ne lancent aucune charge réelle.

La probe PGlite vérifie l’acquisition et la libération réelle du verrou via `pg_locks`, ainsi que les deux ordres préparation→nettoyage et nettoyage→préparation tardive avec le reçu immuable. **PGlite utilise une seule session** : ce contrôle et l’injection réseau ne constituent pas une mesure de contention simultanée sur PostgreSQL staging.

## Lecture des résultats d’une campagne réelle

Les rapports JSON sont écrits sous `tests/load/results/` et joints par le workflow, y compris en cas d’échec. Pour C/E, le résumé indique la configuration effective et affiche **« non mesuré »** si une métrique n’existe pas ; une absence d’échantillon ne devient pas 0 % d’erreur.

Consigner : révision Git, projet staging, date, scénario, nombre de missions/profil représenté, VUs et durée effectifs, contrôles fonctionnels, HTTP, p50/p95/p99, code de sortie et lien d’artefact. Ne pas attribuer un succès à un scénario dont le préflight ou un seuil a échoué.

En cas de lenteur, examiner d’abord les requêtes et leur plan sur staging. Aucun index, quota ou facteur de capacité production ne peut être déduit du seul taux d’échec ou d’un volume vide. Les mesures staging ne sont pas automatiquement une borne basse de la production : jeu de données, cache, dimensionnement et prestataires diffèrent.

## Campagnes constatées dans ce correctif

| Date | Vérification | Résultat |
| --- | --- | --- |
| 25 septembre 2026 | Tests Node des scripts avec HTTP en mémoire | 35/35 verts (16 charge + 19 préparateur) ; aucune charge réelle. |
| 25 septembre 2026 | Probe SQL locale PGlite, schéma minimal et vraies fonctions de recherche/miroir d’audit | 500 missions visibles, zéro déclencheur de notification appelé, cleanup ciblé complet ; dépendance tierce et cron actif refusés. Verrou transactionnel et deux ordres d’arrivée vérifiés ; deux reçus conservés, zéro alerte. Ce n’est pas le schéma staging complet ni une contention multi-session. |
| À consigner par le workflow | k6 staging C/E | Aucun résultat de capacité annoncé par ce document avant exécution réussie. |

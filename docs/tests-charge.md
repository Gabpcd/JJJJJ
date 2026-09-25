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

Le préflight doit obtenir au moins une mission publique valide sans filtre. Le schéma vérifié inclut identifiant, titre, profession, dates, taux numérique et `total_count`. Une réponse HTTP 200 contenant `null`, un objet erreur ou un tableau mal formé échoue. Ensuite, une requête sur cinq répète la recherche sans filtre et exige un résultat ; les autres utilisent des professions actuelles et villes variées, où un tableau vide est légitime.

La fixture doit respecter les règles existantes de publication. Les missions dont le titre commence par `[` et les établissements `est_compte_test=true` sont exclus par la RPC : le seed historique `[loadtest]` ne satisfait pas ce préflight. Préparer des données **uniquement dans le staging isolé**, sans modifier les règles de visibilité du produit pour les tests. Le nombre de missions visibles est consigné dans le journal ; une petite fixture ne démontre pas le comportement d’un catalogue national.

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
node --test tests/node/load-tests.node.mjs
```

Les 15 tests vérifient les paramètres et les seuils, chargent les vrais scripts avec un transport HTTP en mémoire, et couvrent les réponses incorrectes, les préflights vides/incomplets, le refus de production ainsi que l’absence de requête de D/F. Ils ne génèrent aucun compte ni mail et ne lancent aucune charge réelle.

## Lecture des résultats d’une campagne réelle

Les rapports JSON sont écrits sous `tests/load/results/` et joints par le workflow, y compris en cas d’échec. Pour C/E, le résumé indique la configuration effective et affiche **« non mesuré »** si une métrique n’existe pas ; une absence d’échantillon ne devient pas 0 % d’erreur.

Consigner : révision Git, projet staging, date, scénario, nombre de missions/profil représenté, VUs et durée effectifs, contrôles fonctionnels, HTTP, p50/p95/p99, code de sortie et lien d’artefact. Ne pas attribuer un succès à un scénario dont le préflight ou un seuil a échoué.

En cas de lenteur, examiner d’abord les requêtes et leur plan sur staging. Aucun index, quota ou facteur de capacité production ne peut être déduit du seul taux d’échec ou d’un volume vide. Les mesures staging ne sont pas automatiquement une borne basse de la production : jeu de données, cache, dimensionnement et prestataires diffèrent.

## Campagnes constatées dans ce correctif

| Date | Vérification | Résultat |
| --- | --- | --- |
| 25 septembre 2026 | Tests Node des scripts avec HTTP en mémoire | 15/15 verts ; aucune charge réelle. |
| À consigner par le workflow | k6 staging C/E | Aucun résultat de capacité annoncé par ce document avant exécution réussie. |

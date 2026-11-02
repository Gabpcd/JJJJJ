# Saturation CPU de la base prod par le contrôle des crons Edge (2 novembre 2026)

## Observation production (01:34 → 03:45 UTC)

Symptômes relevés dans l'ordre où ils sont apparus :

- `cron.job_run_details` : le job 123 `jolene-monitor-crons-edge-critiques`
  (`SELECT private.fn_controler_crons_edge_critiques()`, toutes les 5 min)
  échoue à chaque passage depuis 01:34 avec
  `canceling statement due to statement timeout` (120 s) à la ligne 8
  (`FOR over SELECT rows`). Il tournait donc 120 s sur 300.
- D'autres jobs pg_cron (116 email-cron-hourly-immediate, 71 messagerie
  cleanup, 13 auto-transitions, 49, 56, 59, 121, 124, 44) tombent en
  `job startup timeout`.
- CI GitHub (PR #1103, run 41379076315, 3 tentatives) : le job
  « Playwright E2E (PR — Chromium) » s'arrête en global setup
  (`GLOBAL_ERROR`, `NO_TEST_EXECUTED`) ; côté API,
  `POST /rest/v1/rpc/fn_test_purge_mission` répond 500 avec le code 57014.
  En direct, la même purge prend 0,3 s par mission.
- Sur PR #1104, le job Chromium a été annulé au bout des 75 min du job, et
  le lot iPad portrait 2/3 a échoué sur une assertion de chargement de chunk
  (`recette-complete-prechargement-reprise.spec.ts`, 1 au lieu de 2), test
  vert sur les deux runs précédents.
- Mesure directe, base sans autre requête active :
  `select count(*) from private.cron_edge_execution_log` (12 Mo,
  313 lectures disque) = 70,9 s ; `select count(*) from notifications`
  (5 748 blocs, 100 % en cache) = 27,5 s. Le goulot est le CPU partagé de
  l'instance, pas le disque.

## Cause

`private.fn_controler_crons_edge_critiques` joint
`private.cron_edge_execution_log` à `net._http_response` sur `r.id`.
pg_net 0.19.5 n'indexe que `created` : le plan est un `Seq Scan` complet de
`net._http_response` (148 Mo pour 6 h de réponses, `email-cron` étant appelé
chaque minute), répété toutes les 5 min. Quand la charge CI de la nuit
(matrices de recette rejouées) s'est ajoutée, le balayage a dépassé 120 s ;
comme la transaction est annulée, aucune ligne n'est marquée `controle_le`,
le travail repart intégralement au passage suivant et le CPU reste
monopolisé.

## Mitigation immédiate (SQL direct, incident avéré)

`select cron.alter_job(123, active := false)` à 03:41 UTC. Une minute plus
tard, `select count(*) from notifications` repasse de 27,5 s à 0,34 s. Les
alertes `CRON_EDGE_HTTP_FAILED` ne sont plus émises tant que le job est en
pause ; les crons Edge eux-mêmes continuent de tourner.

## Correctif durable

Migration `20261102040000_controle_crons_edge_sans_balayage_reponses.sql` :

- même fonction (définition de départ : LIVE, identique à
  `20260729121442`), jointure bornée
  `r.created ∈ [demande_le − 1 min, demande_le + 15 min)` → parcours de
  `_http_response_created_idx`. Mesure en prod sur les 198 lignes en attente :
  1 444 blocs lus, 5,7 s sous charge (contre > 120 s), ~0,5 s à vide ;
- réactivation du job `jolene-monitor-crons-edge-critiques` uniquement là où
  `email-cron-hourly-immediate` est actif (prod), pour ne pas réveiller une
  base de preview.

## Second foyer : boucle `fn_finaliser_document_verification` (04:10 → 04:30 UTC)

Après la pause du cron, la base est repartie (0,34 s) puis s'est de nouveau
effondrée (35 s) alors qu'aucune matrice CI ne tournait. `pg_stat_database`
mesure 2,1 s de temps actif par seconde écoulée, portés par deux sessions
PostgREST (pids 4119164 et 4119173, ouvertes le 31/10 à 03:02 UTC) qui
rejouaient sans interruption `fn_finaliser_document_verification` avec le rôle
`service_role` ; chaque appel échoue en `40001 Tentative documentaire périmée`
(ligne 28 de la fonction). Les journaux Postgres montrent ce motif à cadence
métronomique (1,000 s) depuis le 31/10 03:02:38, soit ~3 600 erreurs/heure
pendant deux jours, sans aucune trace correspondante dans `edge_logs`,
`function_edge_logs` ni `function_logs` : les requêtes n'ont pas traversé la
passerelle publique.

Mitigation à 04:28 UTC : `pg_terminate_backend` sur les deux sessions. La même
requête témoin est passée de 35,9 s à 0,14 s immédiatement ; aucune nouvelle
session PostgREST active n'a repris la boucle dans la minute qui a suivi.
Observation en cours (`pgrst.log_level = info` posé sur `authenticator` à
04:24 UTC pour journaliser l'appelant si la boucle reprend ; à remettre à
`error` ensuite).

Piste principale : la fonction utilise l'ERRCODE `40001`
(`serialization_failure`) pour un refus métier définitif. Ce code est celui
que les couches de transport considèrent comme rejouable ; un client ou un
intermédiaire qui rejoue sur 40001 boucle donc indéfiniment sur une tentative
documentaire périmée. Correctif à instruire (fonction `SECURITY DEFINER`,
catégorie B9) : code d'erreur non rejouable pour ce refus, et `verify-document`
qui mappe ce nouveau code vers 409.

## Points ouverts (hors périmètre de ce correctif)

- `fn_finaliser_document_verification` lève « Tentative documentaire
  périmée » (40001) environ une fois par seconde depuis au moins 24 h, via
  PostgREST en `service_role`, sans trace correspondante dans `edge_logs` ni
  `function_logs`. Coût ≈ 4 % d'un cœur. L'appelant reste à identifier.
- Des établissements de test « Clinique Audit Jolene »
  (`playwright-test-etab-<ts>-<rand>@jolene.app`) s'accumulent toutes les
  10 min environ : aucun nettoyage ne les cible (le global setup ne purge que
  `playwright-test-gps-%`).
- Sept missions `[pw-test:…]` orphelines restaient en base ; la purge du
  global setup les traite dès que la base répond.

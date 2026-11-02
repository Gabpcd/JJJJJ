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
  (5 748 accès tampon `shared hit`, 100 % en cache) = 27,5 s. Le goulot est le CPU partagé de
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
  `_http_response_created_idx`. Mesure en prod à 03:50 UTC sur les 198 lignes
  alors en attente : 1 444 blocs lus, 5,7 s sous charge (contre > 120 s),
  ~0,5 s à vide. EXPLAIN de la revue fraîche : Nested Loop + Index Scan
  `idx_cron_edge_execution_log_a_controler` + Bitmap Index Scan
  `_http_response_created_idx`, coût 5 030 contre 19 028 (Seq Scan) ;
- **verrou du gap TTL** (constat majeur de la revue fraîche B8) : pg_net purge
  `net._http_response` après `pg_net.ttl` (6 h). Une demande plus ancienne
  sans réponse n'est pas un échec de transport : la fonction la marque
  `NON_CONTROLABLE` (`erreur_transport` explicite, compteur `non_controlables`
  dans le JSON de retour) sans alerte ni `echecs`. Sans ce verrou, tout
  arriéré plus vieux que 6 h (pause du contrôleur, panne) déclenchait une
  alerte CRITICAL « aucune réponse » par cron critique et faisait échouer le
  gate `.success == true and .echecs == 0` de `deploy-supabase.yml`, qui
  laisse alors les 9 crons Edge critiques et le monitor en pause ;
- **acquittement de l'arriéré** accumulé pendant l'incident puis la pause du
  contrôleur : 529 lignes à 07:19 UTC (`demande_le` de 01:29 à 07:19, +≈ 90/h),
  dont 17 échecs réels de la fenêtre de saturation, 02:15 → 04:57 UTC
  (9 HTTP 500 `email-cron-hourly-immediate` « Une erreur interne est
  survenue », 8 timeouts pg_net 55 s : email-cron ×3, escrow-release ×2,
  jolene_process_externalisations ×2, process-stripe-refunds-15min ×1). Les
  lignes sont marquées `controle_le` + `erreur_transport = NON_CONTROLE …`,
  statut HTTP et erreur de transport conservés quand la réponse existe
  encore ; les sondes du déploiement, postérieures à la migration, ne sont
  pas concernées. Depuis 05:00 UTC, 0 échec sur ≈ 300 appels Edge (tous les
  crons, toutes les heures) : les échecs étaient confinés à la saturation ;
- réactivation du job `jolene-monitor-crons-edge-critiques` uniquement là où
  `email-cron-hourly-immediate` est actif (prod), pour ne pas réveiller une
  base de preview.

Vérification attendue juste avant le déploiement :
`select count(*) from private.cron_edge_execution_log where controle_le is null`
puis, après le déploiement, `fn_ops_controler_crons_edge_critiques` à
`echecs = 0` et le premier passage du job 123 sans alerte
`CRON_EDGE_HTTP_FAILED` antérieure à la migration.

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

Mitigation vers 04:25 UTC : `pg_terminate_backend` sur les deux sessions
(dernières requêtes de la boucle en 503 à 04:25:15). La même requête témoin
est passée de 35,9 s à 0,14 s immédiatement ; aucune nouvelle session
PostgREST active n'a repris la boucle dans la minute qui a suivi.

Appelant identifié par le journal PostgREST (`pgrst.log_level = info` posé sur
`authenticator` de 04:24 à 04:40 UTC, puis remis à `error` — vérifié en prod) : `127.0.0.1 - service_role "POST /rpc/fn_finaliser_document_verification"`
avec l'agent `Deno/2.1.4 (variant; SupabaseEdgeRuntime/1.77.8; ref=flripxtsyegjshnhzjkz)`.
Les requêtes viennent donc du runtime Edge Supabase du projet, par le chemin interne
(`127.0.0.1`), ce qui explique leur absence de `edge_logs`. Les deux dernières ont reçu
un 503 à 04:25:15 (sessions terminées) et la boucle ne s'est pas reconstituée. Le code
déployé de `verify-document` (seul appelant de cette RPC dans le dépôt) est identique au
dépôt et ne contient aucune boucle : l'origine exacte (invocation interne répétée,
isolat résident, relance par un intermédiaire) reste à établir.

Piste principale : la fonction utilise l'ERRCODE `40001`
(`serialization_failure`) pour un refus métier définitif. Ce code est celui
que les couches de transport considèrent comme rejouable ; un client ou un
intermédiaire qui rejoue sur 40001 boucle donc indéfiniment sur une tentative
documentaire périmée. Correctif à instruire (fonction `SECURITY DEFINER`,
catégorie B9) : code d'erreur non rejouable pour ce refus, et `verify-document`
qui mappe ce nouveau code vers 409.

## Points ouverts (hors périmètre de ce correctif)

- Boucle `fn_finaliser_document_verification` (≈ 3 600 erreurs 40001/h
  pendant deux jours, ≈ 4 % d'un cœur) : appelant identifié (runtime Edge
  interne, cf. § Second foyer), mécanisme de relance à établir ; correctif du
  code d'erreur 40001 à instruire (fonction `SECURITY DEFINER`, B9).
- Trois fonctions live joignent encore `net._http_response` sur `id` seul
  (Seq Scan, coût borné à quelques secondes car hors boucle 5 min) :
  `fn_controler_rappels_notation_j1` (run quotidien 05:17 UTC via
  `email-cron-daily`, 0 ligne à contrôler aujourd'hui),
  `fn_etat_sondes_crons_edge_critiques` et `fn_activer_crons_edge_critiques`
  (appelées à chaque déploiement, moy. 0,9 s, max 11,6 s), ainsi que
  `scripts/ci/f1-cloud-sql.mjs`. À borner sur `created` et à verrouiller par
  un garde CI (`test:guards`) interdisant toute jointure sur `id` seul.
- `fn_controler_rappels_notation_j1` contrôle à J+1 des réponses pg_net
  purgées après 6 h : toute ligne en attente sera classée « réponse absente »
  (défaut de conception indépendant de l'index, à instruire).
- Des établissements de test « Clinique Audit Jolene »
  (`playwright-test-etab-<ts>-<rand>@jolene.app`) s'accumulent toutes les
  10 min environ : aucun nettoyage ne les cible (le global setup ne purge que
  `playwright-test-gps-%`).
- Sept missions `[pw-test:…]` orphelines restaient en base ; la purge du
  global setup les traite dès que la base répond.

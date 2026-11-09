# Crons Edge critiques en échec après un redémarrage de Postgres (9 novembre 2026)

## Chronologie (UTC)

- **08:05:04** — Postgres redémarre (`pg_postmaster_start_time()`).
- **08:06** — premiers échecs. Jusqu'à 10:05, la plupart des passages des crons
  Edge critiques échouent avec
  `duplicate key value violates unique constraint "cron_edge_execution_log_pkey"`.
  Sur ces 2 h : `email-cron-hourly-immediate` 119 échecs, `honoraires-emission-demandes` 24,
  `jolene_process_externalisations` 23, `process-stripe-refunds-15min` 8,
  `escrow-release` 7, `escrow-debit-echeance` 2 (08:11 et 09:11).
- **10:05-10:09** — le déploiement de #1124 (run deploy-supabase 42598226981)
  désactive les 10 crons comme prévu, puis la sonde échoue sur la même clé
  (`request_id` 189) : les crons restent inactifs.
- **10:13** — correctif d'incident en SQL direct (garde-fous 9.0) :
  `SELECT setval('net.http_request_queue_id_seq', 1000000, true);`
- **10:15** — relance de l'étape « Sonder puis activer » : succès, 10 crons
  critiques actifs, crons d'acquisition inactifs.
- **10:16** — premiers passages réussis (`email-cron-hourly-immediate`,
  `jolene_process_externalisations`).

## Cause

Les tables de pg_net (`net.http_request_queue`, `net._http_response`) sont
`UNLOGGED`, et la séquence `net.http_request_queue_id_seq` aussi
(`relpersistence = 'u'`). Après un redémarrage non propre, PostgreSQL les vide
et la séquence repart de 1.

`private.cron_edge_execution_log` (clé primaire `request_id`) conservait
120 636 demandes depuis le 30 juillet, avec des identifiants jusqu'à 163 236.
Chaque nouvel identifiant pg_net retombait sur une ligne déjà journalisée.
L'INSERT de `private.fn_appeler_edge_critique` échouait alors, et annulait
l'appel Edge dans la même transaction.

Le contrôleur toutes les 5 min (`jolene-monitor-crons-edge-critiques`) n'a rien
vu. Il contrôle les réponses HTTP des demandes journalisées, or une demande
annulée avant d'être journalisée ne laisse aucune trace.

## Correctif durable

Migration `20261109102500_sequence_pg_net_journal_crons_edge.sql` :

- `private.fn_resynchroniser_sequence_pg_net()`. Sous verrou consultatif
  transactionnel, si la séquence est repassée sous le plus grand `request_id`
  journalisé, elle saute à ce maximum + 100 000 et lève un `WARNING`. En régime
  normal, c'est un no-op : un parcours d'index et une comparaison.
- `private.fn_appeler_edge_critique`, réécrite depuis sa définition **live**,
  appelle cette garde avant `net.http_post`.
- La garde est rejouée une fois à la migration. En prod, c'est un no-op.

Banc : `tests/security/sequence-pg-net-journal-crons-isolated.test.sql`
(PostgreSQL 17 isolé, 8 scénarios : rattrapage, redémarrage simulé, séquence
fraîche non appelée juste sous le journal, régime normal sans saut, sonde de
9 appels dans une transaction, allowlist, ACL, absence de pg_net). Le verrou
consultatif entre deux sessions n'est pas exercé par ce banc (une seule
session) ; il l'est par construction : `pg_advisory_xact_lock` est tenu
jusqu'au COMMIT de l'INSERT du journal.

## Reste à faire

- **Angle mort du contrôleur.** Un cron critique dont la transaction échoue
  avant l'INSERT du journal reste invisible. Correctif proposé : faire aussi lire
  à `fn_controler_crons_edge_critiques` les `cron.job_run_details` en `failed`
  des 10 jobs critiques depuis son dernier passage. Il émettrait alors la même
  alerte CRITICAL. PR séparée (B9 : crons escrow).
- **Renommage pg_net.** Si une montée de version renomme
  `net.http_request_queue_id_seq`, la garde devient un no-op. À revoir à
  chaque montée de pg_net (aujourd'hui 0.19.5).
- **Autre lecteur.** `private.notation_email_dispatch.request_id` (sans contrainte
  d'unicité) est relu par `fn_controler_rappels_notation_j1`, qui joint sur `id`
  seul. Il ne peut pas faire échouer un cron, mais après un redémarrage il peut
  relier une ancienne demande à une nouvelle réponse. À borner dans le temps
  (pattern du 02/11).
- **Rattrapage métier.** Les passages manqués entre 08:06 et 10:16 sont repris
  au créneau suivant, parce que chaque fonction Edge traite l'arriéré dû
  (échéances, versements, remboursements, file d'e-mails). Aucune écriture
  manuelle n'a été faite.

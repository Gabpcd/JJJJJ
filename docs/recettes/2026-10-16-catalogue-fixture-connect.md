# Revue du catalogue du témoin Connect sous rollback

Le 16 octobre 2026, les trois empreintes de `REVIEWED_CATALOGUE` sont renouvelées
manuellement pour le staging `mejpriaetwgtcstbgfid`. Le témoin s'exécute avant les
migrations de la PR : son verrou du 2 octobre ne décrivait plus la base déployée.
Cette revue ne change ni le seed, ni les barrières de contexte et de quiescence,
ni le contrat de préparation des acteurs, qui reste fermé (`ready:false`).

## Lectures et rapprochement

Trois requêtes explicites `BEGIN READ ONLY` ont été exécutées via le CLI lié au
seul staging, le 16 octobre à partir de 13:50 UTC. Elles lisent des métadonnées,
empreintes et compteurs ; elles n'appellent aucun métier ni fournisseur.

Le constructeur exact `catalogueSqlFixture()` donne :

| Élément | Empreinte MD5 relue |
| --- | --- |
| routines | `c9d5fa4245eea2bf374c213a2d4544a3` |
| triggers | `62e9482e5965040e763888baa8078bed` |
| columns | `90e5efeb01de258eda706210903145e1` |

Les trois compteurs `queuedRequests`, `activeCrons`, `runningCrons` sont zéro ;
`generationUrlAbsent` et `supportStagingExact` sont vrais. L'empreinte du helper
de commission reste `c736c66d76001b64ba425484f77c6ea2`.

Le catalogue détaillé est comparé à
`audits/2026-10-07-cloture-nationale/catalogue-staging.json` : 1 091 des 1 107
fonctions initiales sont identiques (corps, définition, ACL, propriétaire,
configuration). Les différences sont explicitées :

- les corps de `fn_calculer_montant_periode` et `fn_lister_missions_a_facturer`
  correspondent exactement à la migration versionnée `20261006144619` ;
- le corps de `fn_signer_contrat_otp` correspond exactement à la migration
  versionnée `20261006144554` ;
- `fn_envoyer_otp_signature` et les cinq fonctions nouvelles correspondent au
  supplément SMS installé puis réconcilié du run `38699509552` ;
- douze fonctions conservent leur définition et leurs autres métadonnées, avec
  le seul retrait du droit EXECUTE de PUBLIC ; aucun droit n'est ajouté.

Les 136 définitions et états des triggers de la projection du 7 octobre sont
inchangés. Ses 505 colonnes sont inchangées, hormis la qualification textuelle
de sept defaults `extensions.uuid_generate_v4()` par le search_path de lecture.
Cette projection partielle n'est pas utilisée seule pour accepter le catalogue.

Le snapshot canonique de l'installateur SMS est également relu, sans installer
quoi que ce soit. Ses **huit** routines correspondent à toutes les métadonnées
attendues du contrat versionné. Il donne `closed:true` et `quiet:true`. Les quatre
invariants complets et la cible sont strictement égaux au reçu réconcilié du
15 octobre `sms-sql-only-38699509552-postcommit-readonly.json` :

| Élément | MD5 identique au reçu réconcilié |
| --- | --- |
| structure hors supplément SMS | `d349e5b21984b03eedbfb22e897a85c0` |
| routines hors supplément SMS | `bf4f1bda1997824bdad1bf442e810354` |
| inventaire hors supplément SMS | `40ca9434c5f6074ea2664565c844744a` |
| registre des migrations | `5a8c3b616fa94d919a5c7556bcdb2c6d` |
| cible SMS complète | `4afa782ee97ecdfbc9e28fd3b0255474` |

Le digest des lignes métier a évolué ; il n'est ni accepté comme preuve
d'immutabilité ni épinglé par cette modification. Le témoin doit toujours créer
son propre instantané avant exécution et exiger sa restauration exacte après
rollback. Le run SMS initial reste historiquement en échec ; seule sa relecture
indépendante a réconcilié le commit, sans rejouer son SQL.

## Preuves conservées et limites

Les reçus bruts de ces nouvelles lectures sont conservés dans le dossier local
`audits/2026-10-14-reprise/preflight-fournisseurs/catalogue-fixture-20261016/` :

| Fichier | SHA256 |
| --- | --- |
| `catalogue-detail-readonly.json` | `e196f80d88d1e24df50f39f30897c41359190d33fe38abaa809529c7939e2e89` |
| `sms-snapshot-readonly.json` | `c358824c4cf3bfdcf401cd76c4cd9c5ad853f02cb9f81ad2b7f657785ea5cabb` |
| `catalogue-exact-readonly.json` | `dda41c42b7bc56cc8090d86dd65d0f30fa30b31268df61a772766e88011720cd` |

Ces lectures autorisent uniquement ce renouvellement manuel des trois valeurs
du verrou. Elles ne prouvent pas l'exécution du seed sous rollback avec la PR
actuelle, ni une recette frontend, un SMS reçu ou un paiement Stripe TEST. La CI
doit encore exécuter le témoin. Aucun contrôle n'est ignoré et aucun repin
automatique n'est introduit ; un prochain écart sera à nouveau refusé.

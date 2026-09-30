# Draft contrat v1.1 : recette SQL sans publication

Ce lot part de main `58fda7df712cbc5637e41a9dc06a639288a05554`. Il n'ajoute
aucune migration produit, aucun écran, aucune version signable durablement.
`tests/fixtures/contrat-service-v11/draft.sql` reprend exactement le draft local
(SHA256 `534a2efae44ba72270868cd182efd9f1b1e8246e2f413dbe1bb1391d735b169e`).
Le texte n'est ni complété ni approuvé juridiquement. Le DPA absent reste un
blocage de publication ; cette recette ne publie pas le draft.

## Déclenchement et confinement

Le job PR existant `sql-transaction` détecte les changements de cette fixture,
de sa suite, de son runner et de son test Node. Un mélange avec des migrations
produit est refusé avant toute étape distante. Le mode fixture ne lance ni
Supabase CLI, ni bootstrap, ni synchronisation, ni Auth HTTP, ni fournisseur.
Le verrou reste `jolene-supabase-staging-writes`, sans annulation du run courant.
Ce n'est pas un nouveau workflow manuel.

Le runner exige un contexte PR, les SHA base/exécuté, run/attempt et le seul
projet autorisé `mejpriaetwgtcstbgfid`. Seul le token Management staging est lu.
Trois requêtes au maximum, sans redirection ni reprise automatique :

1. SELECT de préflight, comparaison exacte avec le catalogue versionné.
2. BEGIN et garde répétée → savepoint → DDL fixture + assertions → rollback au
   savepoint → même garde de catalogue/résidus → sentinelle typée → ROLLBACK.
3. Même SELECT indépendant, y compris après un refus/réponse perdue de l'étape2.

Un HTTP200 seul n'est jamais un succès : une ligne exacte
`{"preuve":"CONTRAT_V11_SQL_ROLLBACK","annule":true}` et le contrôle indépendant
sont tous deux requis. Une réponse perdue reste un échec, même si la lecture
indépendante ne voit aucun résidu validé ; elle ne prouve pas à elle seule que
la requête initiale est terminée. Aucun nettoyage compensatoire n'est effectué.

Les empreintes des quatre entrées sont figées dans le runner. Ne jamais les
recapturer pour masquer une dérive : relire les définitions et effets concernés.
Le résumé JSON filtré est émis dans le log et écrit dans
`$RUNNER_TEMP/contrat-v11-sql-proof.json` ; aucun corps fournisseur, SQL, jeton,
URL libre, trace navigateur ou donnée utilisateur n'y apparaît.

## Préflight LIVE lu le 30 septembre 2026

Lectures SELECT seules sur staging : 29 tables (colonnes/defaults, contraintes,
indexes, RLS/policies, triggers/règles), 52 fonctions (définition, ACL/propriétaire),
événements DDL et rôles. Le catalogue impose 26 compteurs de collisions à zéro,
zéro cron actif, zéro trigger Auth INSERT/UPDATE inattendu, zéro trigger statement
dans les cascades FK, zéro FK non validée dans cette fermeture, zéro default de
séquence, deux buckets privés et absence des objets/inventaire/migration draft.
Les FK de cascade sont parcourues récursivement.

Les collisions incluent les soignants et références auteur/utilisateur sans FK
Auth : la suppression Auth/anonymisation ne doit jamais atteindre un orphelin
préexistant au même UUID. Les sept UUID fixes restent réservés à cette recette.
Les préférences des cinq établissements sont fermées dans la transaction.

Effets relus : signature/anonymisation/audits uniquement SQL ; trigger SEPA
inactif pour compte test ou mandat NULL ; miroir de téléportation inactif pour
les actions de la recette. Les triggers DDL PostgREST font un NOTIFY transactionnel,
annulé au savepoint. Les branches CREATE/DROP EXTENSION ne sont pas atteintes.
Pas de Storage prefixes installé. Aucun défaut nextval/setval identifié dans
les tables de cette fermeture. Une évolution LIVE de ces conditions refuse
l'exécution, y compris après intégration de nouvelles migrations.

## Validation locale et preuve restant à acquérir

- `node --test tests/node/contrat-v11-sql-proof.node.mjs tests/node/staging-migration-base.node.mjs` : 20/20.
- `node --check scripts/ci/contrat-v11-sql-proof.mjs`, actionlint et diff check : verts.
- `bash tests/non-regression/guards.sh` : 17/17.
- Assemblage réel local 98 212 octets : pglast 49 instructions SQL, 14 corps
  PLpgSQL, un BEGIN/savepoint/rollback-to/release/ROLLBACK, aucun COMMIT.

Les mocks transport couvrent mauvais contexte/destination, altération des
entrées, dérive catalogue, sentinelle invalide, HTTP/JSON/timeout/redirect,
contrôle final divergent et non-divulgation des erreurs fournisseur. Les tests
exécutent le vrai bloc de scope YAML dans de petits dépôts synthétiques.
Ils ne prouvent pas l'exécution PostgreSQL : le run réel reste à autoriser après
revue, puis à contrôler indépendamment. Aucun push ou workflow lancé ici.

La suite SQL couvre snapshot, acteurs/RBAC, consultation, legacy, reprise,
immuabilité, révocation, anonymisation et cascades. La preuve frontend existante
est 30/30 simulations (six scénarios, cinq formats), non rejouée pour ce lot sans
changement UI. Cette recette teste les métadonnées Storage, pas les octets ni
l'API Storage/Auth Admin ; elle ne prouve ni concurrence interconnexion ni
appareil physique. Aucun circuit de paiement n'est repris.


## Premier pilote et correction du contexte ACL

Run `36755425612`, job `110024348959`, head `fd5be121` : préflight accepté,
transaction refusée à 18:00:31.866 UTC, SQLSTATE `42501`, contexte
`inline_code_block line 74 at IF`. L'assertion ACL utilisait le nom textuel du
helper `private.fn_purger_preparations_contrat_non_signees` alors que le rôle
courant était `authenticated`. Le SELECT de diagnostic confirme l'absence de
USAGE sur `private`, avec USAGE sur `public` et accès au helper de catalogue.

Le correctif encadre uniquement ces assertions par `RESET ROLE` puis
`SET LOCAL ROLE authenticated`. Les rôles explicitement testés par
`has_function_privilege` restent inchangés. Aucun GRANT, texte, DDL ou appel
métier déplacé sous un rôle privilégié. Seule l'empreinte de la suite change
dans le runner ; les trois autres empreintes sont inchangées.

Le contrôle indépendant du premier run a confirmé les 26 compteurs à zéro et
le catalogue exact. L'archive initiale reste conservée dans
`/private/tmp/jolene-contrat-v11-sql-36755425612` ; elle n'est pas requalifiée en
succès. La suite SQL complète reste à exécuter après revue.

Régression locale : `python3 tests/security/check-contrat-v11-roles.py` utilise
le pglast déjà disponible, sans installation. Le contrôle AST échoue sur le
contexte ACL d'origine, passe sur la correction et compare la séquence des
appels métier/rôles à fd5be121 : appels préparation, signature, consultation et
anonymisation inchangés, seul le refus de consultation anonyme reste sous anon.
Ce test local structurel ne prétend pas remplacer l'exécution PostgreSQL.

## Deuxième pilote et identité de l'édition synthétique

Run `36757290961`, job `110030636079`, head `4009da54` : nouveau refus à
18:15:52.871 UTC, SQLSTATE `42501`, dans
`fn_protect_etablissement_storage_paths()` ligne 11. L'édition du nom du profil
suivait le négatif LECTURE_SEULE : `RESET ROLE` rétablit le rôle SQL mais conserve
les claims du membre, donc le trigger refuse correctement `profil_etab`.

Le test conserve désormais ce refus comme assertion explicite (code et message
attendus, nom inchangé), puis remet les deux claims sur l'identité propriétaire
`etab` avant l'édition. Il contrôle la permission et la nouvelle valeur. Aucun
override, effacement d'identité, GRANT ou changement de trigger n'est ajouté.
Le négatif immédiatement suivant vérifie également qu'une préparation reste
immuable avec les claims de son propriétaire.

Les 20 UPDATE/DELETE sont relus avec le couple rôle SQL/claims. Les éditions du
profil et négatifs préparation/signature utilisent l'identité `etab` ; les tests
Storage conservent `service_role` et cette identité, les hard-delete de fixture
restent sous postgres sans sub. Les deux modifications Auth sont des opérations
de fixture postgres ; le préflight continue d'interdire tout trigger Auth
INSERT/UPDATE métier. Tous les autres contextes sont comparés à `4009da54` par
AST, sans changement. Les RPC métier restent sous les acteurs précédents.

Validation locale de ce delta : 3 contrôles AST, 10 tests Node du runner,
17 garde-fous, `tsc -b`, syntaxe Node et parsing SQL/PLpgSQL verts. Le témoin
`4009da54` présente encore l'édition du nom sous claims lecture seule ; le
contrôle local le distingue du couple refus/édition corrigé. Seule l'empreinte
de la suite change dans le runner ; DDL draft, catalogue, attendu, workflow et
confinement restent identiques. Aucun frontend modifié ni simulation rejouée.

Le contrôle indépendant du runner est vert ; un SELECT distinct à
18:22:51.965926 UTC confirme le catalogue exact et les 26 compteurs à zéro,
objets draft absents et zéro cron. Staging est encore à `20260929163917` à cet
instant, après merge PR1000 mais avant installation visible de son schéma.
L'archive de ce deuxième échec reste dans
`/private/tmp/jolene-contrat-v11-sql-36757290961` (14 Ko). Une évolution ultérieure
du staging doit être examinée, jamais simplement ré-empreintée. La prochaine
exécution SQL réelle reste la validation déterminante ; aucun succès complet
n'est revendiqué et aucun workflow n'est relancé par ce correctif.

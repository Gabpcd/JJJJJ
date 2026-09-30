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
- Assemblage réel local 96 835 octets : pglast 49 instructions SQL, 14 corps
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

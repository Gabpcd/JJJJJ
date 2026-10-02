# Qualification isolée du replay PostgreSQL 17 — branche temporaire uniquement

Ce candidat est un banc de qualification, pas une migration de staging, pas une restauration prouvée et pas une livraison. Il doit rester sur une branche **sans PR** `ci/qualification-pg17-candidatures-20261002`, issue du produit exact `7bec1138ae79131ab940137369e1706ebf0ec860`. Il ne doit pas être fusionné tel quel : il spécialise temporairement le workflow déjà enregistré `restore-local-bootstrap.yml`. Main M et le candidat financier D restent inchangés.

## Source intégrale et refus fermés

Le driver exige le SHA Actions exact, l'événement manuel, le dépôt attendu, la branche dédiée, une ascendance contenant le SHA produit, un checkout propre et un delta limité à ses six fichiers de préparation. Le catalogue provient uniquement du dépôt : les **218** fichiers `supabase/migrations/*.sql`, baseline `00000000000000_baseline_prod.sql` incluse, triés par nom complet. Chacun est comparé octet par octet à `git show 7bec…:<chemin>`, puis fourni entier à `psql` par stdin, sans filtre ni modification, avec `-X -v ON_ERROR_STOP=1 --single-transaction -f -` pour chaque migration. Une erreur arrête le replay immédiatement ; aucune migration n'est sautée, aucun retry SQL, aucune déclaration de registre synthétique.

Le test `tests/security/candidatures-multi-etablissements.test.sql` reste identique au produit (SHA256 `76717f04219cc07aad5884c4f0ec95e503113bdc810b7c909a8b8415b6ed12f4`). Ses huit MD5 de helpers, son inventaire, ses policies, ACL, rôles, erreurs attendues et son `ROLLBACK` sont inchangés. Aucun helper factice, trigger désactivé ou sous-schéma de remplacement. Le replay ordonné a pour SHA256 de manifeste chemins/empreintes `589da3b77b876dfb5923dbca6890982ab1709722b25cebb8e2d803ca435b4835`.

## Infrastructure et arrêt des travaux automatiques

Les cinq digests existants restent inchangés, dont `supabase/postgres@sha256:432d12926b09e10eb3317b0e2e9672c9ce8ea6bccb359857a31ff9f90683161d` (17.6.1.063). Aucune mise à jour opportuniste d'extension ou d'image. Les deux piles, six volumes nommés et réseau Docker interne sans ports publics restent ceux du bootstrap. Les secrets ne sont que des valeurs aléatoires locales ; aucun secret GitHub métier n'est transmis. Les sous-processus Docker ne reçoivent que PATH/HOME.

Le mode explicite `plan-qualification` utilise `jolene_candidatures_pg17_test` dans les environnements PostgreSQL et URLs locales Auth/REST/Storage. Dès le tout premier démarrage de PostgreSQL : `cron.database_name=jolene_candidatures_pg17_test`, `cron.launch_active_jobs=off`, `max_worker_processes=0`. Ce dernier réglage empêche aussi les workers d'extensions, notamment pg_net ; toute incompatibilité native provoque un refus de démarrage, sans remplacement. Le plan et les arguments effectivement lancés sont contrôlés. Les commandes psql passent ensuite exclusivement par `/var/run/postgresql` dans le conteneur DB source exact.

Les images exécutent leurs propres migrations Auth/Storage ; les scripts vendoriés gardent leurs empreintes. Le [script migrate.sh officiel au commit de l'image](https://github.com/supabase/postgres/blob/a431c10a356be4c700d2e3f2af8551e2fec5e250/migrations/db/migrate.sh) exporte PGDATABASE depuis POSTGRES_DB et l'utilise pour les scripts init/migrations. Son ALTER DATABASE postgres concerne la propriété de la base système. Le jwt.sql vendorié règle encore l'expiration de la base système postgres ; il est conservé, et le test ne s'appuie pas sur ce paramètre. La prise en charge réelle de l'ensemble des scripts natifs dans la base nommée sera mesurée par la qualification ; elle n'est pas présumée acquise. Le [code pg_cron v1.6.4](https://github.com/citusdata/pg_cron/blob/v1.6.4/src/pg_cron.c) déclare les paramètres cron utilisés ; le contrôle live exige leurs valeurs.

Le bootstrap vérifie d'abord le cœur vide, les trois routes locales, l'absence de sortie HTTPS et la compatibilité des neuf extensions sur les deux piles. Puis le driver arrête les huit services Auth/REST/Storage/Kong des deux piles, vérifie qu'ils restent arrêtés et que seules les deux DB restent démarrées. Il contrôle le socket, PostgreSQL17, la base exacte, le rôle postgres, les paramètres et l'absence des workers cron/net avant le premier SQL applicatif. Les jobs créés par le replay ne peuvent donc pas démarrer. Après le replay, un `UPDATE cron.job SET active=false WHERE active` local explicite les désactive avant le test ; le nombre de jobs désactivés est rapporté. Aucun cron distant n'est modifié.

Les neuf versions/schémas d'extensions doivent ensuite être exactement installés. Toute divergence, corps de helper différent, personnalisation Auth/Storage absente, précondition historique inexécutable, donnée métier ou file HTTP inattendue arrête le banc. Les 14 comptages de quiescence sont exigés à zéro avant le test et après fermeture de sa transaction annulée. Une réussite ne prouverait que ce replay et ce test SQL sur cette image ; aucune équivalence universelle avec la plateforme Supabase, aucun paiement, remboursement, notification physique ni parcours frontend n'est impliqué.

## Exécution future et preuves

Après revue indépendante et validation du SHA de la branche, l'opérateur pourra demander explicitement :

```sh
gh workflow run restore-local-bootstrap.yml --repo Gabpcd/JJJJJ --ref ci/qualification-pg17-candidatures-20261002
```

Le workflow n'a ni événement push ni PR, ne référence aucun secret, n'appelle aucun autre workflow, n'installe aucun paquet npm et ne contacte aucune API Supabase/Stripe. Les commandes Docker de préparation lancent les ressources uniquement sur le runner Linux temporaire. Le job dispose de 35 minutes, le replay d'au plus 19 minutes ; les étapes de diagnostic filtré, double nettoyage des seules ressources nommées/étiquetées et constat indépendant d'absence sont en `always()`. En cas d'annulation forcée du runner, l'absence ne doit pas être revendiquée sans son artefact.

L'artefact de sept jours contient identité, versions, empreintes ordonnées, dernière migration tentée et statut, SQLSTATE/ligne/code CAND_MULTI éventuel, comptages, verdict du test, rollback et nettoyage. Jamais compose privé, mot de passe, JWT, log SQL brut, dump ou corps des données. Le rapport distingue import incomplet, test non passé et rollback non vérifié. Aucun mot de passe cloud n'est nécessaire.

## Effets d'un push de la branche — lecture statique

Au SHA produit : les cinq workflows comportant `push` (Validate PR, Deploy Supabase, Playwright, Android native simulation et Lighthouse) restreignent cet événement à main. Staging-comptes et Connect PG17 n'ont pas de trigger push ; deploy-staging est manuel. Schema snapshot dépend de Deploy Supabase/main ou de sa propre programmation ; mobile-delivery est exclusivement manuel/main. Ne pas ouvrir de PR : cela activerait d'autres contrôles, dont la synchronisation staging de Validate PR que cette qualification évite.

L'intégration Vercel est neutralisée pour cette seule branche par `vercel.json` : `git.deploymentEnabled["ci/qualification-pg17-candidatures-20261002"] = false`, suivant la [configuration officielle Vercel](https://vercel.com/docs/project-configuration/git-configuration). Le driver impose cette branche exacte et compare intégralement l'objet JSON à celui du SHA produit, avec cette seule propriété ajoutée ; toute autre modification (autre branche, commande, headers, rewrites, réglage global) refuse avant Docker. Aucune configuration de main, D ou d'une autre branche n'est modifiée. Avant le dispatch, confirmer que la branche publiée contient exactement ce candidat et qu'aucune preview n'a démarré ; le banc ne revendique pas une vérification live des réglages Vercel.

Les scripts versionnés de build ne mutent pas staging : `npm ci`, `prebuild` (écriture locale assetlinks), puis Vite ; le plugin PDF ne lit/émet que des fichiers locaux. Le plugin Sentry pourrait créer/finaliser une release et envoyer des sources si ses variables l'activent, d'où l'arrêt explicite de cette preview plutôt qu'une présomption sur les surcharges distantes Vercel. Le workflow PG17 n'exécute aucun de ces scripts.

## État de préparation

Tests en mémoire du driver et de ses gardes : exécutés hors checkout, sans Docker ni PostgreSQL ni réseau. Aucun import réel, aucune simulation frontend, aucun workflow, push, build, changement main/D/staging ni appel fournisseur effectué par cette préparation. L'import historique complet peut encore échouer : son échec doit identifier la première dépendance réelle à instruire, et non conduire à réduire les gardes du test.

## Premier run réel et préparation bornée de la propriété locale

Run `36989467458`, harness `7b076b2df866be92c3ebbe24009d70ccf45b540a` : les deux bases nommées ont démarré avec leurs services natifs, les contrôles d'isolation/socket/workers ont passé et les neuf versions d'extensions sont compatibles (pgjwt/pg_trgm encore seulement disponibles à ce stade). L'import a refusé la **première instruction**, baseline ligne1 `CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions`, SQLSTATE42501. pgcrypto1.3 était déjà présente. Aucune autre migration ni le test métier n'a été exécuté. Les deux nettoyages et le contrôle indépendant d'absence ont confirmé zéro conteneur, volume et réseau. Artefact filtré 8 360octets, digest `ad627f5343bc94fc1c807e48e7b354abfebe3b00196896916dc8aa3d80e5cb68`.

Le code42501 seul ne prouve pas encore la cause précise. Le script officiel `migrate.sh` cible le PGDATABASE demandé pour l'initialisation, mais son affectation du propriétaire reste littérale : `ALTER DATABASE postgres OWNER TO postgres`. La base nommée peut ainsi rester propriété de supabase_admin, contrairement à la base native postgres ; ce point n'était pas présent dans l'artefact du premier essai.

Le complément ne change aucune migration, extension, policy, ACL métier, helper, garde canonique ou rôle. Après arrêt des huit services applicatifs et avant le premier fichier, il relève un inventaire limité aux propriétaires connus et à des booléens : contexte local vide, rôle de session, droits CREATE/CONNECT/TEMP du rôle postgres sur les deux bases, statut SUPERUSER des rôles postgres et supabase_admin. Les valeurs imprévues ne sont pas publiées : seuls les noms attendus ou `other` sont projetés.

Une seule réparation est autorisée **si tous les éléments correspondent exactement** : base nommée détenue par supabase_admin avec CREATE absent pour postgres, base native détenue par postgres avec CREATE présent, CONNECT/TEMP présents des deux côtés, postgres non-superuser et supabase_admin superuser natif, socket local, base exacte, PostgreSQL17, workers0, cron arrêté, zéro compte/donnée/fichier/secret/file réseau/job/table applicative. Sinon le banc refuse, sans modifier les droits.

La réparation utilise une connexion locale dédiée supabase_admin, vérifie à nouveau ces préconditions dans sa transaction, puis exécute uniquement `ALTER DATABASE jolene_candidatures_pg17_test OWNER TO postgres`. Elle ne crée ni ne renforce de rôle et ne touche pas la base native postgres. Une seconde sonde exige les mêmes valeurs, à l'exception des deux changements attendus (propriétaire postgres et CREATE désormais présent), avant tout replay. Aucun `SUPERUSER`, `GRANT`, `SET ROLE`, suppression ou désactivation de trigger n'est ajouté. Le résultat futur du replay reste inconnu ; cette préparation n'autorise aucun retry ou dispatch implicite.


## Deuxième run réel et frontières transactionnelles du replay

Run `36990563362`, harness `fbed6809835fd8697782951611062a4efeb16857` : les sondes ont confirmé exactement l’écart prévu (base nommée propriétaire supabase_admin, CREATE absent pour postgres ; base native propriétaire postgres, CREATE présent). La réparation locale a changé ces seuls deux résultats attendus, sans ajouter SUPERUSER. **84 fichiers au total, baseline incluse, ont terminé ; le 85e a échoué** : `20260714090000_borner_creation_conversations.sql`, ligne739, SQLSTATE42P01. Cette migration crée une table temporaire `ON COMMIT DROP` aux lignes716–734, puis l’utilise à partir de739. Le transport psql en autocommit la supprimait avant son utilisation. Le test canonique n’a pas été exécuté. Double nettoyage et absence indépendante des conteneurs/volumes/réseaux confirmés ; artefact filtré digest `b646dc80f7925a455e5d039d2d0a4db0f0b7c0b17d3fb784f8f57f49cc1652b3`.

Le [transport officiel Supabase CLI 2.98.0, MigrationFile.ExecBatch](https://github.com/supabase/cli/blob/v2.98.0/pkg/migration/file.go#L71) envoie les instructions d’une migration dans un batch implicitement transactionnel. Le banc ajoute donc `--single-transaction` **aux seuls fichiers de migration**. Les octets, l’ordre, le nombre de fichiers, ON_ERROR_STOP et l’arrêt à la première erreur sont conservés. Aucun SQL n’est supprimé, découpé, réécrit ou ajouté au fichier. Le test canonique garde son propre BEGIN/ROLLBACK, sans cette option ; les sondes et la réparation fixe de propriété gardent également leur transport précédent.

La portée de cette correspondance a été vérifiée sur les 218 fichiers du SHA produit figé : 33 contiennent un BEGIN comme première instruction et un COMMIT comme dernière ; les 185 autres n’ont aucun contrôle transactionnel au niveau supérieur. Aucun fichier ne contient d’instruction après son COMMIT final, ni de CREATE INDEX CONCURRENTLY, VACUUM, CREATE/DROP DATABASE ou TABLESPACE, ALTER SYSTEM, REINDEX, DISCARD ALL ou CALL au niveau supérieur. Le relevé statique exclut commentaires, chaînes et corps dollar-quoted ; il complète la relecture des frontières explicites, sans se prétendre parseur PostgreSQL général.

Les BEGIN/COMMIT explicites sont conservés : PostgreSQL peut émettre les avertissements de transaction déjà ouverte/absente dus à l’enveloppe psql, mais aucune instruction métier ne suit leur COMMIT final dans ce catalogue. **Ce transport n’est pas une équivalence universelle à pgconn.Batch** : une migration future contenant un COMMIT intermédiaire, une commande hors transaction ou une dépendance entre sessions nécessiterait une nouvelle qualification. Le SHA produit et chaque fichier restent verrouillés ; aucune extension de cette conclusion à un autre catalogue. Une connexion psql neuve est créée pour chaque fichier, sans conserver l’état de session. Ce complément corrige uniquement le banc ; la réussite du replay complet et du test métier reste à démontrer lors d’une exécution distincte explicitement déclenchée.


## Troisième run : diagnostic de l’inventaire historique, sans assouplissement

Run `36992326152`, harness `708f8d6ebcde81a630ea95b6e7c674f938c7956a` : **132 fichiers ont terminé (baseline incluse)**, puis le133e `20260729121443_figer_inventaire_security_definer.sql` a refusé avec P0001. La table temporaire du premier blocage a donc été franchie. Le test canonique n’a pas tourné et les comptages de quiescence finaux n’ont pas été atteints. Double nettoyage et absence indépendante confirmés. Petit artefact digest `a95edc2a0c546d747a51a5c82019f889ae043c631db3001f82c477bdf0d2fc4d`.

Le filtre précédent sélectionnait le premier préfixe psql, y compris un WARNING de BEGIN déjà ouvert. La ligne7 de ce rapport ne permet donc pas de localiser l’ERROR. Le diagnostic prend désormais exclusivement le même enregistrement ERROR/FATAL que le SQLSTATE. Neuf messages précis du contrôle historique sont projetés vers neuf catégories fermées ; aucun texte de message, liste arbitraire de signatures, SQL ou valeur de données ne sort du processus.

Avant le fichier133 uniquement, une sonde `BEGIN READ ONLY` sur la même base/socket local compare les **422 signatures et MD5 littéraux** de cette migration (SHA256 `160626d9fab04c230e517f8774101a7644a52b014d6bf5c1e8f10f66e1c6aa6f`) à pg_proc après les132fichiers. Elle termine par ROLLBACK et ne lit aucune ligne métier. La projection ne publie que comptes bornés et différences des signatures déjà autorisées par cette source : signature, catégorie absence/non-definer ou empreinte différente, MD5 attendu et MD5 observé. Les fonctions exposées absentes du manifeste sont comptées sans publier leur nom. Aucun corps de fonction, détail Auth/Storage, secret ou identifiant utilisateur n’est publié. Une sortie inattendue refuse ; une divergence diagnostiquée n’autorise aucun contournement : le fichier133 inchangé est ensuite exécuté et garde tous ses contrôles.

Le diagnostic historique ne remplace ni l’inventaire422, ni le test canonique aux huit MD5, ni aucune policy/ACL. Il ne met à jour aucun hash et ne saute aucun fichier. Les écarts issus d’une simple dernière déclaration textuelle restent des hypothèses : des migrations antérieures modifient aussi des fonctions par DDL dynamique. L’état pg_proc réel doit être lu avant d’affirmer une cause particulière. Aucune nouvelle exécution n’est autorisée implicitement par ce complément.


## Quatrième run : défauts natifs de privilèges avant import

Run `36993491874`, harness `111ed4cac3c331fed4e7de0c90e95e8c1484c0f9` :132fichiers terminés, puis refus du133e à la vraie ligne525, catégorie HISTORICAL_MANIFEST_UNCLASSIFIED. La sonde en lecture seule confirme **422/422signatures et MD5 exacts**, zéro différence, mais106fonctions SECURITY DEFINER exposées supplémentaires absentes du manifeste. Artefact filtré17175octets, SHA256 `6eff05d59c04c84f494dd244ae11b8c3ccad33cd81cdce1413b1ca7bef058518`. Test canonique et quiescence finale non atteints ; double cleanup et absence indépendante0/0/0confirmés.

La baseline contient718REVOKE PUBLIC sur fonctions et des GRANT explicites : elle n’est pas sans ACL. Le [script natif initial-schema.sql au commit exact de l’image](https://github.com/supabase/postgres/blob/a431c10a356be4c700d2e3f2af8551e2fec5e250/migrations/db/init-scripts/00000000000000-initial-schema.sql) ajoute des DEFAULT PRIVILEGES versanon/authenticated sur tables/functions/sequences depublic ; [migrate.sh](https://github.com/supabase/postgres/blob/a431c10a356be4c700d2e3f2af8551e2fec5e250/migrations/db/migrate.sh) l’exécute avecpostgres. Ces grants directs se cumulent avec les droitsPUBLIC : le REVOKE PUBLIC du dump ne les retire pas. La préparation staging déjà versionnée depuis `c8897670574d9e3f0b0634d79df8d26d5f6911d8` retire précisément ces défauts avantimport, dans `.github/workflows/deploy-supabase-staging.yml`.

Le banc reprend **uniquement ces trois ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ... FROM anon, authenticated**, avant baseline. La sonde exige base/socket exacts, PostgreSQL17, workers arrêtés, aucun compte/donnée/secret/file réseau, aucun objet public/private (relations, routines, types), propriétairepostgres, sessionpostgres non-superuser. Elle exige exactement24grants natifs sans grantoption : deux rôles×(huit privilèges table, trois séquence, un EXECUTE). Tout grant global versces rôles provoque un refus plutôt qu’une révocation élargie. Les [privilèges PostgreSQL17](https://www.postgresql.org/docs/17/sql-grant.html) incluent MAINTAIN dans ALL TABLES.

L’alignement se déroule dans une transaction qui recontrôle les préconditions, applique les trois instructions fixes, puis exige la disparition des seuls24grants et la conservation du nombre et de l’empreinte de toutes les autres entrées de pg_default_acl. Toute divergence annule la transaction. Une seconde sonde indépendante vérifie encore ces résultats avant le premier fichier. La projection ne publie que noms natifs autorisés, types/privilèges fermés, booléens, comptes et empreinte ; aucune donnée métier ni rôle inattendu. PUBLIC, service_role, les autres rôles/schémas et les objets existants ne sont pas révoqués. Le [périmètre officiel ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html) concerne uniquement les objets futurs.

Aucun ajustement aprèsimport, aucune extension du manifeste422, aucun changement de sesMD5 ou des huitMD5 du test canonique, aucune migration sautée. Les218fichiers restent byte-identiques. L’explication des106expositions est cohérente avec les sources natives et les témoins historiques ; sa disparition et la réussite intégrale ne seront prouvées que par une nouvelle exécution explicitement demandée. Ce complément ne l’exécute pas.


### Diagnostic ciblé du préflight notation (v7)

Le run 36995195103 importe 202 fichiers puis reçoit P0001 à la fin du DO
notation (fichier203, ligne36). Cette ligne recouvre trois exceptions ; l'ordre
ACL n'est pas encore une cause établie. Avant ce seul fichier épinglé au SHA256
23f7ee94d48fa6c2f7ba48344c341a0db4411d467ec2861c4a0fa2a470abdbe3,
le banc lit les préconditions en READ ONLY sous le garde local existant.
La preuve contient uniquement booléens, MD5 de code/contraintes et ACL ordonnées
à rôles fermés (grantor, grantee, EXECUTE, grant option). Les sorties inattendues
sont refusées ; aucune définition SQL ni valeur métier n'est exportée.

Trois catégories fermées distinguent les exceptions d'audit, de définition/ACL
et d'inventaire. La sonde n'ajuste aucun droit : la migration originale s'exécute
ensuite intacte, une seule fois, et son refus arrête toujours le replay. Aucun
alignement d'ordre ni changement de comparaison n'est autorisé par ce diagnostic.

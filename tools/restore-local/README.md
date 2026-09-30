# Bootstrap local de restauration — premier essai CI en échec, cleanup prouvé

Le candidat produit deux piles Supabase **vides** : source et cible, cinq services chacune (PostgreSQL/Auth/REST/Storage/Kong), six volumes nommés, un réseau Docker interne unique. Aucun port publié, aucune connexion à un projet Supabase, aucun schéma Jolene importé, aucun compte/fichier créé. Ce lot n'est pas une preuve de restauration ni un test frontend.

## Fichiers et commandes

Entrée : `scripts/restore/bootstrap.mjs`, Node >=22, sans paquet npm. `plan` génère les clés locales distinctes source/cible et la configuration privée (permissions0600, dossier0700). Le manifeste et stdout ne contiennent ni JWT ni mot de passe. Les fichiers `*.private.json` restent hors artifacts.

```sh
node scripts/restore/bootstrap.mjs plan /tmp/restore-run-private jolene-restore-drill-ci-123
node scripts/restore/bootstrap.mjs preload /tmp/restore-run-private
node scripts/restore/bootstrap.mjs preflight /tmp/restore-run-private
# Seulement sur un runner Docker Linux amd64 dédié, après revue :
node scripts/restore/bootstrap.mjs up /tmp/restore-run-private
node scripts/restore/bootstrap.mjs inspect /tmp/restore-run-private
# En clôture/échec : seulement les ressources exactes portant le label du manifeste.
node scripts/restore/bootstrap.mjs down /tmp/restore-run-private
```

Le préchargement des cinq images par leur champ `reference` de `images.lock.json` est une étape distincte du runner, avant isolation. La commande `preload` télécharge uniquement ces cinq digests avant toute création de réseau/conteneur ; `up` **ne pull jamais**. Le bootstrap refuse image manquante, digest/architecture incorrects, contexte Docker distant, ressource homonyme préexistante, réseau secondaire, port, privilège, montage divergent, conteneur étranger ou volume externe. `down` contrôle tout l'inventaire avant ses suppressions, accepte un démarrage partiel connu et n'emploie aucun prune global. Si le réseau est absent et qu'aucun conteneur du run ne demeure, il peut reprendre le nettoyage des seuls volumes exacts étiquetés. Un conteneur restant sans réseau provoque un refus. Le nettoyage est idempotent et suivi d'une requête indépendante `absent`, qui rapproche noms exacts et labels (aucun prune).

Les seules URLs backend sont `http://<run>-source-api:8000` et `http://<run>-target-api:8000`, accessibles uniquement sur le réseau interne. Les trois refs connues prod/staging/historique sont refusées explicitement : flripxtsyegjshnhzjkz, mejpriaetwgtcstbgfid, wnepopwygokbhlqghydb. SMTP est dirigé sur loopback port1, inscriptions publiques et hooks désactivés, aucune configuration SMS/social. Les logs Docker sont désactivés. Depuis chaque Storage, trois sondes passent réellement par Kong (`/auth/v1/health`, `/rest/v1/`, `/storage/v1/status`, tous HTTP200), puis vérifient l'échec de sortie HTTPS ; le SQL exige une DB vide, zéro job/secret/queue/webhook et PostgreSQL17. Ce contrôle ne crée aucune fixture.

Le runner/browser/preview de la recette future devra être ajouté **explicitement** au manifeste d'isolation ; aujourd'hui tout conteneur supplémentaire est refusé. Realtime, Edge, Studio, imgproxy, analytics et pooler ne sont pas lancés. Les routes qui en dépendent ne sont pas prétendues opérationnelles.

## Versions, provenance, compatibilité

Sources officielles au commit `3fc8af387ec4dfb449510828a938e1f6e57a9575`, consultées le30septembre2026. Versions : postgres17.6.1.136, GoTrue2.196.0, PostgREST14.17, Storage1.74.0, Kong3.9.3. Le lock contient le digest d'index OCI **et** celui du manifest linux/amd64 ; les cinq index ont été lus au registre public et leur SHA256 comparé au contenu, sans couche téléchargée. Les scripts SQL d'initialisation vendoriés restent byte-identiques et sont contrôlés avant plan/démarrage. Licence Apache2 jointe.

La DB est major17, cohérente avec le catalogue Jolene PostgreSQL17.6. Cela ne prouve pas l'équivalence des extensions ou migrations Auth/Storage entre plateforme et image : elle reste à tester sur le runtime. Aucun import dans15/16, aucun filtrage d'instruction en échec. Cette phase vanille initialise seulement pgcrypto/pg_cron/pg_net/Vault pour les contrôles. `pgjwt`, présente dans le catalogue Jolene, est [dépréciée/retirée de PG17](https://supabase.com/docs/guides/database/extensions/pgjwt) : sa disponibilité reste un blocage à qualifier pour l'import complet. Les autres extensions Jolene ne sont pas prétendues restaurées. Aucun DDL applicatif n'est filtré ni importé pour ce premier essai.

Kong est l'option officielle de compatibilité choisie pour les trois routes locales ; Envoy est désormais le défaut officiel. Ce choix n'est pas une recommandation de migration production. Le gateway est une adaptation explicite et minimale des routes officielles Auth/REST/Storage, sans endpoint fournisseur ; sa compatibilité doit être vérifiée réellement avec les images épinglées. `API_EXTERNAL_URL` et l'issuer incluent `/auth/v1`, conformément au changement officiel de juillet2026.

Sources : [Docker officiel](https://supabase.com/docs/guides/self-hosting/docker), [compose épinglé](https://github.com/supabase/supabase/blob/3fc8af387ec4dfb449510828a938e1f6e57a9575/docker/docker-compose.yml), [option Kong officielle](https://github.com/supabase/supabase/blob/3fc8af387ec4dfb449510828a938e1f6e57a9575/docker/docker-compose.kong.yml), [restauration depuis plateforme](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

## Import Jolene : dépendances précises encore absentes

`schema-audit.py` parse réellement le snapshot b8 avec pglast7.10. Résultat : 3 333 841octets, 7 267statements, 996fonctions, 175tables, seulement `public`. La liste des **64 références privées** est dans `schema-inventory.json`, sous `lexical_references_not_dependency_closure.private`. Ce repérage lexical n'est pas une analyse exhaustive des corps PL/pgSQL/dépendances dynamiques.

Le SELECT catalogue a été exécuté séparément par l'agent principal à **2026-09-30T19:45:47.01886Z**. `catalogue-completeness.json` confirme69routines privées,16relations,14policies et8triggers gérés ; les64noms existent. Il recense aussi21objets privés supplémentaires, dont `security_definer_inventory` : importer seulement les64 serait incomplet. Les8triggers comprennent des protections Storage ; il faut distinguer leurs définitions gérées et les personnalisations Jolene, jamais les ignorer collectivement. `catalogue-required.sql` n'interroge que les catalogues, aucun mot de passe de rôle, contenu Vault ou ligne métier n'est exporté.

Bundle futur requis, produit par un **export officiel en lecture seule séparé**, avec provenance/versions/hashes avant transfert vers le runner sans secrets :

1. DDL complet `public,private` via `supabase db dump --schema public,private` (schéma seul par défaut), y compris owners/ACL/RLS/index/contraintes/fonctions/triggers. Ne pas reconstruire pg_dump depuis le JSON. Référence réutilisable : phase export de `deploy-supabase-staging.yml`, **jamais son reset/bootstrap/sync**.
2. DDL exact des personnalisations Auth/Storage et ACL. Les migrations historiques juillet + copie-bulletin septembre sont des pistes, pas une garantie d'équivalence à l'état courant. Export TOC/DDL officiel + sélection auditée des personnalisations, avec comparaison des14policies et8triggers ; ne pas réimporter aveuglément les internals gérés.
3. Schéma+contenu technique du registre `supabase_migrations` et de l'inventaire SECURITY DEFINER. Le SELECT a seulement prouvé leur présence, pas leur contenu. Vérifier séparément que les statements historiques ne contiennent aucun secret avant conservation.
4. Référentiels strictement autorisés et nécessaires aux parcours (modes d'exercice, spécialités, documents/paramètres de règles, templates/version applicables), obtenus depuis les sources versionnées ou un export explicitement borné. **Pas de dump global `parametres_systeme`, Vault, cron ni données métier.** La liste exacte reste à établir avant seed.
5. Import transactionnel réel sur les images locales et vérification d'équivalence. L'importeur/son manifeste complet n'est pas fourni tant que le bundle et ses contraintes de provenance manquent ; le présent audit retourne toujours `import_ready:false`, exit3, sans appeler une DB. Ne pas interpréter sa syntaxe SQL verte comme un import réussi.

## Validation réellement effectuée et suite

```sh
node --test scripts/restore/bootstrap.test.mjs scripts/restore/ci-guard.test.mjs
PYTHONDONTWRITEBYTECODE=1 python3 scripts/restore/schema-audit.test.py
python3 scripts/restore/schema-audit.py /chemin/supabase/schema/public.sql # exit3 attendu : incomplet
```

**38/38 tests Node** (33 initiaux et 5 de diagnostic), **5/5 tests Python**, `node --check` et parse des3SQL par pglast réussis. Ils couvrent génération réelle de fichiers privés, refus de destinations/egress/configurations dangereuses, inventaire de nettoyage, non-divulgation des credentials et refus de SQL hors dump. Les objets inspectés par les tests unitaires sont synthétiques : aucune prétention de test Docker.

Préflight réel local exécuté : `DOCKER_UNAVAILABLE`, exit1. Aucun moteur Docker installé, aucune image téléchargée ou conteneur créé. Pas d'exécution de `docker compose config`, migrations internes, AuthHTTP, Storage ou SQL runtime. Les échecs ENOSPC de préparation n'ont pas été comptés comme succès.

Prochaine action utile : revue du diagnostic fermé, puis un essai CI distinct autorisé pour localiser le service en échec avant toute correction de configuration ; acquisition séparée du bundle officiel complet. Ensuite seulement seed réel **4acteurs/5fichiers**, sauvegarde/restauration, checks Auth/Storage et cinqformats frontend sans mocks. Ces éléments restent non implémentés/non prouvés dans cette phase1.

## Workflow candidat pour la preuve d'infrastructure réelle

Le workflow `.github/workflows/restore-local-bootstrap.yml` et les scripts `tools/restore-local/` ont été publiés en PR1004 après application du candidat byte-identique. Le premier essai CI et son échec sont détaillés ci-dessous. Le complément diagnostique demeure local jusqu’à revue et publication par l’agent principal.

- Déclenchement manuel ou PR touchant exclusivement les chemins déclarés du workflow et de `tools/restore-local/**` (la restriction porte sur le déclenchement, pas sur tous les autres fichiers possibles de la PR). Aucun push, cron ou `pull_request_target`.
- Un seul runner GitHub standard Ubuntu24.04, sans matrice, timeout20minutes, verrou dédié avec `cancel-in-progress:false`. Aucun environnement Supabase, cloud payant additionnel, action de déploiement ou secret GitHub/Supabase référencé. Le jeton éphémère interne nécessaire au checkout privé reste `contents:read`, avec `persist-credentials:false`, et n'est jamais transmis à Docker.
- Actions officielles checkout/setup-node/upload-artifact épinglées à leurs SHA vérifiés ; Node24.14.0. Aucun npm install, Dockerlogin, export distant ni installation SupabaseCLI. Le seul téléchargement du script est celui des cinq images déjà épinglées, dans `preload` avant isolation.
- Garde du dépôt, de l'événement, du run/attempt et du SHA checkout. Puis tests Node, plan privé, preload, préflight, deux piles vides, SQL READ ONLY, six HTTP200 via gateway, deux refus d'egress. Une seconde commande `up` doit refuser exactement `RESOURCES_ALREADY_EXIST` ; une autre erreur ne compte pas comme succès du négatif.
- Deux `down` exécutés dans une étape `always()` prouvent nettoyage et idempotence ; une étape indépendante `always()` exige zéro conteneur/volume/réseau par noms et labels. Sans manifeste initial, elle vérifie directement l'absence. Aucun `continue-on-error` ou `|| true` ne masque un échec. Un arrêt forcé du runner peut empêcher la preuve finale : dans ce cas le run est incomplet/rouge, et la destruction du runner éphémère ne remplace pas l'assertion d'absence.
- Artifact limité au dossier de preuves : identités run/SHA, résultats enum/compteurs/statuts, tests locaux. Ni compose privé, clés, dossiers DB, logs bruts, dumps, JWT/sessions ni fichiers applicatifs. Rétention7jours. Une erreur Docker garde son code fermé, complété par une phase, un code de sortie, un signal autorisé et un booléen timeout. Avant cleanup, une inspection en lecture seule projette les dix services attendus : état, healthcheck, dernier code de healthcheck, compteur d'échecs, exitcode et OOM. Aucun Env, message libre, `State.Error` ni `Health.Log.Output` n'est conservé. Cette inspection est diagnostique et ne remplace aucune garde ; le cleanup et l'absence indépendante restent obligatoires. Aucun retry automatique.

Les manifests/configs OCI des cinq images ont été lus et leurs SHA256 recalculés, sans couche téléchargée localement : aucune image ne déclare de volume anonyme. La config Kong confirme USER kong ; les seules gateways utilisent explicitement `user:0:0` pour lire leurs binds0600 sans ouvrir les permissions. Cela ne donne aucun privilège host, socket, port publié ni bind sensible supplémentaire. L'inspection du réseau et des montages reste obligatoire.

Validation locale complémentaire : actionlint vert ; 38 tests Node (dont refus d’événements/identités/SHA, absence indépendante et non-divulgation diagnostique). Docker reste absent ici. La prochaine preuve attendue reste **l’infrastructure vanille**, pas une connexion utilisateur Auth ni l’exercice de restauration. Les déclenchements appartiennent à l’agent principal ; aucun rerun n’a été effectué par cet agent.

## Premier essai CI et complément d'observation

Run `36771145062`, PR1004 head `d8d77cd16f2f7003f9c85e2af51567b0c9f0ae54`, checkout de merge `81b1e020a1e011e4569061eba6cf11234e6debd5` (parents main `ed402c32` + head de PR). Le30septembre2026, preload et préflight ont réussi. Le démarrage a échoué entre20:14:50 et20:17:13UTC avec seulement `DOCKER_COMMAND_FAILED` conservé. Aucun service ni cause précise ne peut être déduit de cette durée. La seconde inspection et le négatif de redémarrage ont été sautés.

Les deux cleanup et le contrôle indépendant ont réussi : **0conteneur,0volume,0réseau**. L'artifact filtré (2693octets) est conservé dans `/private/tmp/jolene-restore-bootstrap-run-36771145062`. Le delta suivant ajoute uniquement l'observation ci-dessus ; configuration, images, réseau, healthchecks, seuils, opérations et cleanup sont inchangés. Aucune relance automatique ni correction spéculative de configuration. Les preuves runtime Auth/Storage/Jolene/restauration restent absentes.

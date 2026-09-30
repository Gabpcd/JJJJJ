# Export DDL en quarantaine et qualification des extensions

Candidat séparé du bootstrap vide. Aucun export distant ou import n’a été exécuté par ce lot. Le checkout PR1004 reste intact. La preuve runtime acquise (`36775840767`, renouvelée par le principal dans `36777772524`) porte seulement sur deux piles vides.

## Périmètre précis

Le collecteur reprend **uniquement la phase export schéma** de `deploy-supabase-staging.yml` (public/private), avec les outils officiels PostgreSQL17 `pg_dump` et `pg_restore` plutôt qu’un link/CLI Supabase. Le format custom permet une sélection officielle par TOC, sans reconstruire le DDL à partir de JSON. Owners, ACL, RLS, contraintes, index, fonctions et triggers applicatifs sont préservés.

- Source unique : production `flripxtsyegjshnhzjkz`, en lecture seule. Les refs staging courante/historique sont refusées. Connexion directe canonique ou Session Pooler Supabase sur5432 avec utilisateur contenant la ref exacte ; aucun endpoint libre, port6543 ou URL dans les arguments. SSL verify-full et CA système imposés.
- Une connexion à la fois, timeouts connexion10s/statement60s/lock5s/process180s. `default_transaction_read_only=on` est imposé et vérifié. Aucune DDL source, migration, sync, reset, AuthHTTP, StorageAPI, créationcloud ou appel fournisseur métier.
- `pg_dump --schema-only --format=custom --schema=public --schema=private --schema=auth --schema=storage`. Aucune donnée, valeur de séquence, grand objet, rôle global ou mot de passe de rôle. Commentaires, security labels, publications et subscriptions ne sont pas exportés : **ce n’est pas une sauvegarde exhaustive de la plateforme**.
- Le dump et le SQL complet restent privés en quarantaine. `pg_restore` produit seulement des fichiers, jamais de connexion destination. Une extraction conserve public/private ; une autre sélectionne exactement14policies de `storage.objects` et le trigger Auth `trg_auth_user_deleted_cleanup`. Les cinq policies RESTRICTIVE restent du DDL original, sans réécriture.
- Les sept triggers Storage recensés par `NOT tgisinternal` ne sont **pas** assimilés à des personnalisations : ils restent dans le DDL privé de comparaison native. Les ACL Auth/Storage sont extraites dans un fichier de revue distinct, pas appliquées. L’identification d’éventuelles autres personnalisations gérées exige encore une comparaison au catalogue du runtime neuf.
- Ne pas rejouer en bloc `20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql` : elle contient notamment des INSERT de buckets. Les six policies copies-bulletins plus récentes proviennent de la migration20260929163917 et sont déjà dans les14noms attendus.
- Pas d’export des lignes `schema_migrations.statements`, de `security_definer_inventory.justification`, de paramètres, templates, Vault, cron, comptes, documents ou données métier. Leur nécessité pour la recette synthétique reste à cadrer séparément ; le contenu historique pourrait contenir des valeurs sensibles.

L’empreinte du catalogue avant/après couvre schémas, fonctions, colonnes, contraintes, index, triggers, policies, vues, enums et ACL par défaut. Elle est une garde contre la dérive de ces éléments, **pas une preuve d’équivalence complète ni d’un futur import**. Elle ne couvre notamment pas les paramètres `pg_sequence` (incrément/min/max/start/cache/cycle), ni les définitions des domaines, collations ou règles : leur DDL peut changer sans modifier ce MD5. Le dump officiel les capture, mais ils nécessitent une revue distincte. Les neuf extensions,14policies et trigger Auth doivent correspondre au périmètre relu. Une dérive détectée par les éléments couverts, une table étrangère ou un motif de secret connu refuse avant dump. Une approbation locale bornée à60min contient la ref et le MD5 exact fraîchement relu ; aucune approbation n’est préremplie.

## Secret : contrôle automatique limité, aucune publication automatique

Les fichiers sont créés sous dossier0700/umask077, sans écrasement ; les sorties fournisseur ne sont ni affichées ni archivées. Le secret DB est seulement transmis dans l’environnement libpq fermé, pas en argument. Les erreurs publiques utilisent des codes et phases fermés. Le mot de passe source exact, JWT littéraux, clés API reconnaissables, clés privées PEM et URLs avec credentials provoquent un refus.

Le scanner pglast refuse instructions de données, DO/CALL/SELECT arbitraire, commandes psql non prévues et GUC non autorisés. Il ne compile pas les corps PL/pgSQL et **ne prouve pas l’absence de secret arbitrairement encodé ni d’effet dynamique**. Il ne supprime aucune instruction pour faire passer le fichier. Même succès : `DDL_QUARANTINED_ONLY`, `release_authorized:false`, `import_ready:false`. Aucun DDL ou dump clair n’est publié : le workflow séparé ne transmet qu’une enveloppe chiffrée après scan. Revue humaine des définitions/effets et autorisation du hash exact requises avant tout import dans le runner isolé. Les erreurs/exports partiels restent privés, jamais assimilés à un bundle validé.

## pgjwt et versions exactes

Catalogue source du30septembre2026 à19:45:47UTC : PostgreSQL17.6 ; `pg_cron1.6.4@pg_catalog`, `pg_net0.19.5@extensions`, `pg_stat_statements1.11@extensions`, `pg_trgm1.6@extensions`, `pgcrypto1.3@extensions`, **`pgjwt0.2.0@extensions`**, `plpgsql1.0@pg_catalog`, `supabase_vault0.3.1@vault`, `uuid-ossp1.1@extensions`. `scope.json` conserve ces valeurs exactes, sans option d’omission de pgjwt.

Le [guide Supabase](https://supabase.com/docs/guides/database/extensions/pgjwt) documente sa dépréciation/retrait ; cela **ne prouve pas son indisponibilité dans notre digest d’image précis**. Le bootstrap n’avait simplement pas créé pgjwt. La nouvelle commande locale `bootstrap.mjs extensions` (après inspection stricte des dix conteneurs) lit, pour chaque DB, `pg_extension` et `pg_available_extension_versions` : version/schéma installés, versions disponibles, attributs de contrôle et dépendances, avec compte/troncature explicite. Aucun CREATE/UPDATE d’extension. Une étape du workflow candidat conserve ce résultat lors de la prochaine exécution utile, sans déclenchement supplémentaire ici.

Deux SELECT catalogue production ont été exécutés **par le principal**, sans corps : premier21:04:46UTC,301candidats lexicaux tronqués à200 ; affinage21:07:00UTC,6membres,0dépendant enregistré,1065routines scannées,0candidat token-appel,9routines EXECUTE, aucune troncature. Les fichiers initiaux sont conservés. Les neuf identités/MD5 sont dans `pgjwt-preflight-v2-result.json`, notamment `private.fn_appeler_edge_critique(text,boolean)` ; ce relevé n’exclut pas les appels construits dynamiquement. **Aucune suppression pgjwt n’est autorisée ou inférée.**

`compareRequired` distingue extension disponible mais non installée, absence de version exacte, version/schéma installé divergent et inventaire tronqué. Même compatibilité déclarative positive ne prouve pas CREATE EXTENSION ni import. Une divergence impose une qualification explicite ; aucune réécriture silencieuse vers PG15/16, aucune exclusion pgjwt pour obtenir du vert.

## Commandes et prochaine action

Disponible immédiatement hors réseau :

```sh
node tools/restore-local/scripts/export/export-schema.mjs plan
node --test tools/restore-local/scripts/export/export-schema.test.mjs tools/restore-local/scripts/restore/extensions.test.mjs
PYTHONDONTWRITEBYTECODE=1 python3 tools/restore-local/scripts/export/audit-ddl.test.py
```

Exécution future **seulement après revue/autorisation du principal**, sur runner dédié avec clients officiels `psql`, `pg_dump`, `pg_restore`17 et pglast7.10. Le collecteur peut être lancé directement avec ces outils ; le workflow ci-dessous les fournit avant de recevoir la credential DB :

1. Lire `catalogue-export.sql` et confirmer son MD5, les schémas et tous les ensembles exacts. Aucune donnée de table lue. Préparer un JSON privé `{source_ref,catalogue_md5,expires_at}` (UTC, maximum60min).
2. Fournir dans l’environnement privé seulement `RESTORE_SCHEMA_SOURCE_REF`, `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGUSER`, `PGPASSWORD` ; le collecteur reconstruit ses autres paramètres, ignore les tokens Supabase/PGSERVICE/PGOPTIONS hérités, et n’affiche jamais ces valeurs.
3. `node tools/restore-local/scripts/export/export-schema.mjs collect /tmp/jolene-ddl-private-NOUVEAU /tmp/approval.private.json`.
4. Examiner le manifeste/DDL en quarantaine et comparer les personnalisations gérées à l’inventaire natif. Confirmer les versions d’extensions disponibles puis proposer un import distinct dans les piles isolées. Aucune restauration ni seed n’est incluse dans ce lot.

Clients PostgreSQL17 et Docker absents localement : aucun export réel ni TOC de dump réel n’a été testé. Les tests de commande/TOC utilisent des fixtures explicites ; les tests pglast analysent réellement le snapshot public versionné (7267statements, dont239COMMENT), sans le déclarer complet (private absent). Le premier refus de ce snapshot avant prise en charge COMMENT est conservé. Validation locale :73/73Node (dont11 nouveaux CI/chiffrement),6/6Python, parse SQL/syntaxe/actionlint/diff-check. Le chiffrement/déchiffrement authentifié a réellement tourné sur un DDL synthétique ; cela ne prouve pas un export source. Aucune simulationfrontend nouvelle : aucun parcours produit modifié, aucun scénario Auth/Storage synthétique prétendu validé.

Sources officielles : [pg_dump17](https://www.postgresql.org/docs/17/app-pgdump.html), [pg_restore17](https://www.postgresql.org/docs/17/app-pgrestore.html), [libpq17 SSL](https://www.postgresql.org/docs/17/libpq-connect.html). La commande native préserve la sélection du workflow existant sans réutiliser son reset ni ses exports de lignes techniques.

## Workflow exécutable : PR sans credential, export après merge sur main

`.github/workflows/restore-schema-export.yml` possède deux événements : `pull_request` limité à ses chemins, qui exécute uniquement les tests sans secret ; et `workflow_dispatch` sans input, qui peut exporter seulement depuis `refs/heads/main`. Aucun `pull_request_target`, push main automatique ou cron. Le premier modèle de gate dans le code d'une PR a été refusé en revue et abandonné : il ne constitue pas une frontière de confiance.

Ordre obligatoire : revue du candidat → CI locale/sans credential sur PR → merge autorisé → relecture du SHA main exact → configuration de l'approbation hors PR → dispatch unique sur main. Les jobs de validation et d'export comparent `github.sha`/HEAD au SHA approuvé et ne checkoutent aucune ref fournie par l'appelant. Le job d'export reçoit le seul secret `SUPABASE_DB_PASSWORD`, uniquement à l'étape collect ; `contents:read`, checkout sans credentials persistants, concurrence distincte et timeout20min. Rien n'est déclenché par ce candidat.

Variables de dépôt à fournir par le principal après revue (aucune valeur n'est préremplie) :

- `RESTORE_EXPORT_APPROVED_HEAD` : SHA40 de main revérifié ;
- `RESTORE_EXPORT_CATALOGUE_MD5` : empreinte fraîche de `catalogue-export.sql` ;
- `RESTORE_EXPORT_EXPIRES_AT` : UTC, au plus60min après préparation ;
- `RESTORE_EXPORT_PGHOST` : Session Pooler officiel de ce projet, port5432 ; l'utilisateur est fixé à `postgres.flripxtsyegjshnhzjkz` ;
- `RESTORE_EXPORT_RECIPIENT_PUBLIC_KEY` : clé publique RSA4096 SPKI ;
- `RESTORE_EXPORT_RECIPIENT_SHA256` : SHA256 du DER SPKI, vérifié indépendamment. La clé privée ne va jamais dans GitHub, Git ou l'artefact.

Les clients PG17 sont exécutés via le digest déjà épinglé `supabase/postgres@sha256:5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b`. **Aucun serveur PostgreSQL n'est démarré** par ce job. Le wrapper n'autorise que versions, SELECT catalogue exact, pg_dump schema-only exact et pg_restore vers fichiers exacts. Versions/pg_restore sont sans réseau ni DBenv ; seuls psql/pg_dump reçoivent la connexion TLS read-only. Les conteneurs sont sans capacités, filesystem root readonly, UID du runner, sans logs ni volume anonyme (config officielle relue), avec noms/labels de run. Le cleanup always refuse une ressource non conforme, supprime seulement les clients exacts et la quarantaine privée, puis vérifie zéro conteneur et dossier privé absent.

Ubuntu24.04 fournit PG16 dans son inventaire actuel : on ne s'appuie pas dessus. pglast7.10 est installé dans un venv CI à partir du wheel officiel CPython3.12 Linux x86_64, SHA256 `b89c6bf904b4043752431564ce5c6bacf5d54cb6d6bc487a175cab9a47f18436`, avec `--require-hashes --only-binary --no-deps` ; aucune installation locale n'a été faite. L'image client et le wheel sont acquis avant toute credential DB. Toute incompatibilité client/SSL/native refuse, sans basculer vers PG16 ni changer la destination.

Commande future, seulement après les étapes précédentes :

```sh
gh workflow run restore-schema-export.yml --repo Gabpcd/JJJJJ --ref main
```

## Récupération : enveloppe privée, puis revue du DDL avant import

Après les contrôles avant/après et les scans, le job vérifie de nouveau chaque hash puis chiffre les quatre SQL (`all`, `application`, `customizations`, `managed-acl-review`) et le manifeste avec une clé AES256-GCM aléatoire ; la clé AES est enveloppée par RSA-OAEP-SHA256 vers le destinataire exact. L'artefact `restore-ddl-quarantine-RUN-ATTEMPT` (rétention1jour) contient **uniquement** cette enveloppe chiffrée et les rapports fermés/hashs/compteurs. Ni l'archive pg_dump brute, ni le DDL clair, ni une erreur fournisseur brute, ni un environnement ne sont uploadés. Si le scan/refus échoue, il n'y a pas d'enveloppe. L'absence de données de tables vient du mode schema-only ; les scanners ne garantissent pas l'absence d'une valeur sensible littérale encodée dans un corps SQL, d'où le chiffrement et la revue supplémentaire.

Le principal récupère via son accès GitHub existant, vérifie le SHA256 d'enveloppe/recipient dans le manifeste, puis déchiffre hors ligne avec `open-quarantine.mjs` (clé privée mode0600, sortie neuve0700). Exemple avec valeurs relues, jamais inventées :

```sh
gh run download RUN --repo Gabpcd/JJJJJ --name restore-ddl-quarantine-RUN-ATTEMPT --dir /tmp/ddl-envelope-RUN
node tools/restore-local/scripts/export/open-quarantine.mjs /tmp/ddl-envelope-RUN/ddl-quarantine.encrypted.json /chemin/prive/recipient.pem SHA256_ENVELOPPE SHA256_RECIPIENT /tmp/ddl-review-RUN
```

Le déchiffrement vérifie l'authenticité AES-GCM, le destinataire, l'inventaire exact des fichiers et leurs hashes ; il ne lance aucun SQL. Son résultat reste `DECRYPTED_QUARANTINE_ONLY`, `release_authorized:false`, `import_ready:false`. Après inspection humaine des définitions, appels dynamiques et valeurs littérales, le principal pourra autoriser les hashes DDL précis pour le futur import isolé. Le présent job ne publie donc pas un bundle déclaré sans secrets ni prêt à restaurer.

ACL : les owners/GRANT applicatifs public/private sont conservés ; les ACL des schémas et objets Auth/Storage sont seulement proposées dans `managed-acl-review.private.sql`, à comparer aux rôles natifs locaux avant replay. Aucun GRANT supplémentaire, rôle global, mot de passe, catalogue de Vault ou ligne technique n'est extrait. Le DDL complet Auth/Storage chiffré permet la comparaison au natif ; cela n'autorise pas son replay global au-dessus des composants gérés.

Limites restantes après ce lot : prochain export réel non exécuté, disponibilité exacte des neuf extensions à lire au prochain bootstrap utile, comparaison gérée/native et revue DDL non faites, import réel non fait, références techniques nécessaires encore à définir sans lignes historiques, jeu synthétique Auth/Storage et parcours frontend non couverts. La preuve acquise reste celle des piles vides et des validations locales explicitement décrites.

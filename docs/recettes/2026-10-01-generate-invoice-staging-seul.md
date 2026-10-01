# Actualisation manuelle de generate-invoice en staging

Candidat séparé après la fusion1004 (`9ac91fa18c756208423c36d4276f33c3504cc988`), sans exécution distante. Il déploie uniquement le code de `generate-invoice` sur `mejpriaetwgtcstbgfid`, depuis un SHA exact de main relu. Aucun reset, migration, réglage de secret, webhook Stripe, nouvelle session Auth ou facture de test n'est inclus. Le workflow est exclusivement manuel ; ni push, PR, cron ni `pull_request_target` ne le déclenchent.

## Préconditions et garde d'authentification

Le workflow doit d'abord être revu, testé et intégré à main. Le job utilise `contents:read`, checkout de `github.sha` sans credentials persistants, le verrou partagé `jolene-supabase-staging-writes` et `cancel-in-progress:false`. Le SHA fourni doit égaler le SHA du run, le checkout propre et le main courant (GET public GitHub, vérifié avant les métadonnées puis immédiatement avant le déploiement). Tout mouvement de main, erreur API ou rate-limit interrompt le run ; il ne bascule pas vers une autre ref.

L'unique secret configuré pour le script est `STAGING_SUPABASE_ACCESS_TOKEN`, existant. Aucun token Stripe, mot de passe DB, anon/service-role ni contenu Vault n'est lu. Avant déploiement, Management doit montrer une fonction unique `generate-invoice` ACTIVE, **version15**, `verify_jwt:false`, `ezbr_sha256:1be7e9620e5f61af304b4bafc029c0a0f4a80c99dd50e22a9ba9b17d23a46c1d`. Cette observation a été fournie par l'agent principal ; elle sera relue au run. Le config local doit contenir uniquement `verify_jwt = false` dans sa section. Un mode distant différent bloque ; aucun droit n'est élargi pour faire passer le test. L'authentification applicative existante du handler est inchangée.

Le même token Management réalise une requête fixe `read_only:true` sur `/database/query` : uniquement nombres de crons actifs/en cours et d'éléments EN_ATTENTE/EN_COURS dans escrow_release_queue/stripe_refunds_queue. Les quatre compteurs doivent être exactement0. Cette garde ne désactive rien, ne purge rien et ne lit aucune ligne métier. Un refus de permission ou une réponse ambiguë bloque ; aucun secret DB supplémentaire n'est demandé. Le verrou sérialise les jobs CI qui le partagent, pas les appels HTTP externes : la quiescence observée n'est pas un coupe-circuit fournisseurs.

## Commande bornée et preuves

Supabase CLI2.98.0, installée via l'action officielle épinglée à `1dedf2c611547ede7232d26866dd3c56ab903bbb` (branche officielle v1 observée le1octobre2026), puis version binaire contrôlée. Une seule commande de déploiement, sans shell, sans héritage proxy/profil ou credentials de production :

```sh
supabase functions deploy generate-invoice --project-ref mejpriaetwgtcstbgfid --use-api --no-verify-jwt
```

Le nom cible et le projet sont constants, non paramétrables. `--use-api` compile côté serveur ; aucune VM Docker locale, `--prune`, `link`, `db push`, `secrets set` ou commande de fournisseur. Les stdout/stderr du CLI restent en mémoire privée et ne sont jamais joints aux artifacts. Un timeout ou résultat perdu est classé incertain, sans seconde commande ni rollback automatique. Le déploiement peut alors avoir eu lieu : le diagnostic suivant devra commencer en lecture seule.

Après succès de la commande, le catalogue doit montrer le même ID, ACTIVE, JWTfalse, version16 et un nouveau hash de bundle. Toutes les métadonnées des autres fonctions sont comparées intégralement en mémoire (empreintes canoniques non publiées) ; ajout/retrait/différence bloque. Le rapport publie uniquement le nombre des autres fonctions et le résultat de comparaison, jamais leur catalogue ni leur source. Si version ou hash n'a pas changé, aucune actualisation n'est revendiquée.

Deux requêtes sans Authorization, cookies, corps ni identifiant métier suivent : OPTIONS doit retourner200 et un corps vide ; GET doit retourner401 et exactement le contrat JSON `{"error":"Non autorisé"}`. La branche GET refuse avant lecture des variables Supabase et création du client DB ; seul son compteur de limitation mémoire peut changer. Les réponses sont comparées en mémoire et remplacées dans le rapport par statuts/booléens. Aucun corps, header, stack, log brut ou credential n'est archivé.

**Limites de preuve :** un succès distingue la publication cloud et une réponse du handler des tests Deno en CI. Il ne prouve pas que la sonde a atteint précisément la nouvelle version (aucune corrélation de deployment_id du runtime dans ce lot), ni que `chargerPolicesFacture()` a été appelée : cette fonction n'est pas exécutée sur OPTIONS/401. `cloud_font_rendering_verified:false` et `business_flow_verified:false` restent explicites. Génération PDF/XML, Storage, emails, paiements et frontend intégré restent hors périmètre ; les preuves Deno/IO fictives acquises ne deviennent pas une preuve cloud de facturation.

## Exécution ultérieure et validations

Seulement après revue indépendante, CI et intégration du workflow, depuis le main vérifié :

```sh
gh workflow run refresh-generate-invoice-staging.yml --ref main -f expected_sha=SHA_MAIN_RELU
```

Pas d'exécution depuis une branche de PR. Le préflight est volontairement figé à v15 : après un succès il refusera une seconde exécution. Ne pas actualiser ces attentes automatiquement. Timeout du job10min ; celui du script6min et commande de déploiement180s. Le rapport fermé `result.json` reste conservé7jours même en échec. Le dépôt étant public, ces artifacts sont à considérer comme publics ; aucune confidentialité ne repose sur ses ACL.

Tests locaux hors réseau :

```sh
node --test tests/node/refresh-generate-invoice-staging.node.mjs
node --check scripts/ci/refresh-generate-invoice-staging.mjs
actionlint .github/workflows/refresh-generate-invoice-staging.yml
```

Les réponses Management/runtime et le processus CLI des tests sont injectés : ils prouvent les refus, la commande exacte, les limites d'environnement, le résultat incertain sans reprise, la comparaison des autres fonctions et la non-divulgation. Aucun déploiement, sonde cloud, SQL distant ou frontend n'a été exécuté pendant cette préparation.

Sources primaires : [CLI deploy](https://supabase.com/docs/reference/cli/supabase-functions-deploy), [métadonnées Management](https://supabase.com/docs/reference/api/v1-list-all-functions), [implémentation CLI2.98.0](https://github.com/supabase/cli/blob/v2.98.0/internal/functions/deploy/deploy.go). Le chemin existant `deploy-supabase-staging.yml` impose un reset et `configure-stripe-webhooks-staging.yml` reconfigure Stripe : aucun de ces workflows n'est lancé ou détourné ici.

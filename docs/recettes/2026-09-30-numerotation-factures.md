# Numérotation des commissions — 30 septembre 2026

Le trigger `dec_num_facture`, sur `public.factures`, cherchait le dernier
`SD-YYYYMM-*` du mois puis convertissait systématiquement le troisième segment
du nouveau numéro en entier. En présence d'un tel SD, les numéros de commissions
`JOL-YYYY-H-*`, `HC-*` et `HR-*` échouaient avec SQLSTATE `22P02`.
Ce défaut est atteignable par les fonctions de préparation des commissions,
mais son déclenchement actuel n'est pas établi : les agrégats lus le 30 septembre
à 15:54:21 UTC en staging et 15:56:51 UTC en production comptent **zéro SD du mois**.
L'agrégat production compte aussi zéro segment SD invalide. Aucune émission
financière distante n'a été exécutée pour cette investigation.

Les corps staging/production sont identiques :

- `dec_verifier_numerotation_facture()` : md5(pg_get_functiondef)
  `977fb78fd9077c00d3d72073721c2ebe`, md5(prosrc)
  `8673036776b1bdc1e3647d688b507230`.
- `fn_preparer_facture_commission_periode(uuid)` : md5(pg_get_functiondef)
  `f26f4d29b77cb2be569c0db62c1fb4dc`.

Les copies catalogue utilisées sont
`/private/tmp/jolene-F1-catalogue-complement-20260930.json` et
`/private/tmp/jolene-F1-numerotation-production-agregats-20260930.json`.
La migration a été créée par Supabase CLI 2.95.4, à partir du corps LIVE.

## Changement borné

Le contrôle ne compare que les séries mensuelles numériques SD/JOL du mois
courant, déjà regroupées par `fn_generer_numero_facture()`. Il conserve le dernier
numéro par date de création, la comparaison séquentielle et le WARNING existant.
Le cast `numeric` accepte les suffixes numériques sans limite artificielle int32.
Les familles H/HC/HR, annuelle, AVC, FC et Stripe sont laissées à leurs propres
générateurs. Les numéros existants ne sont ni modifiés ni renumérotés.

Le trigger reste INVOKER, avec les mêmes ACL et attachement BEFORE INSERT.
La migration refuse une empreinte ou des métadonnées inattendues. Elle ne touche
pas l'inventaire SECURITY DEFINER, les générateurs, les contraintes UNIQUE,
les politiques, les calculs financiers, les statuts ou les droits.
Elle ne crée pas une nouvelle garantie de séquence concurrente ou de chronologie
stricte : le contrôle conservé est un avertissement, l'unicité reste assurée
par la contrainte de table.

`factures_honoraires` est une autre table ; ses séries et ses compteurs restent
inchangés. Une collision de fixture H/HC/HR partageant le même préfixe UUID reste
un `23505` attendu ; elle ne doit pas conduire à relâcher l'unicité.

## SQL et CI

`tests/security/factures-numerotation-series.test.sql` insère un établissement
synthétique privé/de test et dix factures BROUILLON : un SD du mois, sept familles
distinctes dont H/HC/HR, une suite mensuelle JOL puis un saut mensuel SD. Il vérifie
les insertions, montants/statuts inchangés, et un doublon refusé exactement par
`factures_numero_facture_key`. Aucun trigger ni policy n'est désactivé.

Un sous-bloc sentinelle annule les fixtures et vérifie l'absence de résidus Auth,
profil, préférences et factures. La suite est ajoutée à la liste SQL de
`validate-pr`, qui applique les migrations ajoutées et chaque suite sous
ROLLBACK/SAVEPOINT. Aucun appel d'émission, Stripe, HTTP, mission ou contrat
n'est nécessaire. Les branches de parrainage sortent immédiatement pour
BROUILLON ; les préférences de la fixture désactivent tous les canaux.
Le corps catalogue de `fn_trg_init_preferences_notifications()` fait
`ON CONFLICT (utilisateur_id) DO NOTHING` : le profil n'écrase donc pas les quatre
préférences false préinsérées. `fn_auto_code_parrainage_etab` et le classifieur
d'acquisition reçoivent des champs explicites. Les factures sans mission ni
honoraires ne déclenchent aucun workflow métier ; aucun passage à PAYEE n'a lieu.

La suite traverse le saut de séquence sans refus ni renumérotation. Le WARNING
est conservé dans le corps ; ses notices ne sont pas capturées par les assertions
SQL du client Management. **Le SQL réel reste à exécuter en CI** ; le parsing
SQL/PLpgSQL local ne vaut pas une exécution PostgreSQL.

## Frontend simulé

La nouvelle spec `e2e/recette-complete-numerotation-factures.spec.ts` utilise
les pages réelles Facturation établissement et Revenus/Factures soignant.
Elle couvre les trois numéros de commission, l'erreur de lecture injectée,
le bouton Réessayer, ouverture/fermeture de section, navigation d'onglets et
rechargement. L'erreur injectée de l'établissement est conservée et assertée
exactement dans la console ; aucun filtre de console ou pageerror n'est ajouté.

Auth/API/WebSocket, CSS de police et SDK Stripe sont simulés, ServiceWorker absent
explicitement. Le badge notifications peut demander une actualisation puisque
le WebSocket fictif est fermé. Aucune preuve de livraison push, d'émission SQL,
de paiement, de PDF serveur ou de fonctionnement fournisseur n'en découle.

Commandes de reproduction (aucune dépendance supplémentaire) :

```sh
VITE_SUPABASE_URL=http://127.0.0.1:18512 VITE_SUPABASE_PUBLISHABLE_KEY=simulation-public-key VITE_SENTRY_DSN= VITE_STRIPE_PUBLISHABLE_KEY=pk_test_simulation VITE_TURNSTILE_SITE_KEY= npm run build
npm run preview -- --host 127.0.0.1 --port 18512 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18512 RECETTE_RESULTS_DIR=/private/tmp/jolene-numerotation-ui-final npx playwright test --config e2e/playwright.recette-complete.config.ts e2e/recette-complete-numerotation-factures.spec.ts
npx tsc -b
npm run test:guards
npx vitest run --config vitest.invoicing.config.ts
actionlint .github/workflows/validate-pr.yml
```

Validation locale : build, TypeScript et 17 guards verts. Invoicing : 36 tests
passés, 46 tests d'intégration ignorés faute d'environnement distant ; ils ne
sont pas présentés comme validés. Parsing : deux statements/deux corps PLpgSQL
dans la migration, trois statements/un corps PLpgSQL dans la suite SQL.

Matrice finale : **10/10**, deux rôles × cinq formats, zéro retry/skip/flaky,
zéro pageerror et aucune erreur console imprévue. Les cinq erreurs de lecture
injectées sont présentes et vérifiées exactement. Rapport temporaire :
`/private/tmp/jolene-numerotation-ui-final/results.json`. Preuves durables :
`audits/2026-09-30-preparation-nationale/numerotation-factures/` dans le workspace
racine, avec manifeste SHA256 ; rapports initiaux conservés séparément.

## Correction d'affichage dans un deuxième commit

L'inspection visuelle de cette première matrice a révélé un montant rogné sur
iPhone pour les longs numéros H/HC/HR. Le contrôle de largeur globale ne détectait
pas le débordement masqué. Une nouvelle assertion de visibilité du texte complet
échoue sur l'ancienne compilation :
`/private/tmp/jolene-numerotation-montant-avant/results.json` (un échec attendu).

La carte commission autorise désormais le retour à la ligne de ses deux blocs
et du numéro. Le delta produit contient uniquement trois changements de classes
dans `FacturationEtablissement.tsx`, sans montant, tarif, règle, RPC ni payload
modifié. Les douze tests de périmètre financier existants et TypeScript passent.

Le test vérifie chaque montant TTC et chaque détail HT/TVA des trois factures
H/HC/HR avant et après rechargement : rectangle du texte via Range, limites des
ancêtres qui masquent le débordement, limites du viewport, et absence d'élément
superposé à son centre. Ces assertions ont passé la matrice de dix scénarios
sur cinq formats. Les captures pleine page repartent ensuite du haut afin que
les barres fixes ne soient pas dessinées au milieu de la capture composite.
Rapport final : `/private/tmp/jolene-numerotation-montant-verifie/results.json`.
Les limites d'intégration SQL et fournisseur décrites plus haut restent valables.

Aucun push, merge ou déploiement effectué par ce lot.

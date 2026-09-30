# Export établissement sans troncature silencieuse — 30 septembre 2026

La fonction `fn_exporter_rgpd_etablissement()` limitait silencieusement à 200 les
missions et contrats retournés. La définition LIVE a été relue avant la migration
(`md5(prosrc) = bb36c4ee8e9ed20c1a3a65752ce4840e`). Le frontend télécharge déjà
l'intégralité du JSON reçu ; aucune modification de son comportement n'est
nécessaire pour supprimer cette troncature.

## Périmètre

- Suppression des deux `LIMIT 200`, sans ajouter de champ ni modifier les projections
  `etablissement`, `missions`, `factures`, `contrats`, `export_date`.
- Ordre décroissant par date, puis identifiant pour départager les égalités.
- Filtrage par `mon_etablissement_id()` conservé, avec refus explicite si session
  absente ou compte inactif. Appel SQL anonyme interdit ; droits existants
  `authenticated` et `service_role` conservés.
- Empreinte de l'inventaire des fonctions `SECURITY DEFINER` actualisée.

La réponse reste un JSON unique. Aucun plafond silencieux de remplacement n'est
introduit. Un volume dépassant les capacités d'une requête pourrait produire une
erreur explicite ; ce correctif ne prouve pas les performances à toute volumétrie.
Une pagination cohérente nécessiterait un contrat d'API et une recette distincts.
Ce changement ne promet ni tous les jeux de données RGPD, ni les fichiers binaires,
ni une archive exhaustive : il restitue toutes les lignes des projections existantes.

## Vérifications locales

- `tsc -b` et build web local : verts.
- Tests téléchargement + inventaire : 8/8.
- Gardes de non-régression : 17/17.
- Simulation Playwright : 5/5, iPhone, Android, iPad portrait, iPad paysage,
  ordinateur. Pour chaque format : connexion établissement, onglet Sécurité & RGPD,
  fichier JSON réellement téléchargé et relu (201 missions + 201 contrats), refus
  métier, erreur HTTP 503 sans nouveau fichier/audit, reprise et rechargement.
  Le JSON téléchargé est comparé intégralement à la réponse attendue.
- Captures des cinq formats inspectées ; snapshots ARIA et messages d'erreur joints
  aux résultats. Preuves locales : `/private/tmp/jolene-export-etablissement-simulation`.

Commandes reproductibles depuis le checkout, avec les dépendances disponibles :

```sh
node node_modules/typescript/bin/tsc -b
node node_modules/vitest/vitest.mjs run src/lib/telechargement.test.ts tests/admin/security/security-definer-manifest.test.ts
bash tests/non-regression/guards.sh
VITE_SUPABASE_URL=http://127.0.0.1:8897 VITE_SUPABASE_PUBLISHABLE_KEY=cle-locale-de-simulation VITE_SENTRY_DSN= SENTRY_UPLOAD_ENABLED=false npm run build -- --outDir /private/tmp/jolene-export-etablissement-dist
node node_modules/vite/bin/vite.js preview --host 127.0.0.1 --port 8897 --strictPort --outDir /private/tmp/jolene-export-etablissement-dist
# Dans un second terminal :
RECETTE_RESULTS_DIR=/private/tmp/jolene-export-etablissement-simulation PLAYWRIGHT_BASE_URL=http://127.0.0.1:8897 node node_modules/@playwright/test/cli.js test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-export-etablissement.spec.ts
```

## SQL réel restant avant validation

`tests/security/export-etablissement-sans-troncature.test.sql` est ajouté à la suite
SQL transactionnelle de `validate-pr`. Il crée 201 missions/contrats pour un
établissement et une ligne pour un tiers, vérifie chaque position, la projection,
l'export du membre canonique, l'isolation, le refus sans établissement/sans
session/compte suspendu et les ACL. Les fixtures sont annulées par sous-transaction,
puis la transaction externe est annulée.

La revue de code séparée n'a identifié aucun P1/P2 ; **l'exécution SQL réelle reste
à obtenir en CI**. La PR SQL doit partir après intégration du correctif CI qui
prépare uniquement le schéma de la base et teste les migrations PR avec rollback.
Aucun DDL distant n'a été exécuté pour cette recette locale.

Les réponses backend de la simulation sont simulées. Elle ne prouve pas
l'intégration réelle de cette migration, le fonctionnement du partage natif
Capacitor sur appareils physiques ni une livraison en production. Aucun build de
livraison mobile, OTA ou soumission aux stores n'est lancé.

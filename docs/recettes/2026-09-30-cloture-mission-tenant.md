# Clôture mission : refus des identités sans tenant — 30/09/2026

## Défaut et portée

Le catalogue LIVE présentait le corps `fn_terminer_mission(uuid)` d'empreinte
`md5(prosrc)=1ea8780f088275804470e8211da98bfb`, identique à la migration
`20260903201000_securiser_cloture_anticipee_admin.sql`, déjà mergée dans main
(commit `83d9d3fac7603dd58ae68eef88b797b60d9f1d4d`). Ce n'est pas une altération
inexpliquée du serveur ; l'inventaire de juillet n'avait pas été actualisé.

La condition `NOT admin AND etablissement_id <> mon_etablissement_id()` ne
refusait pas un compte dont le tenant était NULL. La lecture du statut tiers
était atteignable par un compte authenticated connaissant l'UUID. La clôture
était conditionnelle aux règles métier : EN_COURS, planning complet, départ
enregistré, aucun segment ouvert, fin planifiée passée, absence d'arrêt maladie.
Le trigger RBAC retourne NEW si le rôle établissement est NULL ; la protection
soignant ne rétablit pas `statut`, et EN_COURS → TERMINEE est une transition
autorisée. Aucun appel d'exploitation ni lecture de mission réelle n'a été fait.
Le constat vient de la lecture statique des définitions LIVE et de leurs ACL.

Le correctif refuse une identité absente/inactive avant la lecture de mission.
Il préserve les admins validés par `est_admin()` et exige sinon le tenant
canonique et la permission `missions`. La requête filtre elle-même le tenant et
verrouille la mission pour sérialiser les clôtures. Une cible étrangère,
inexistante ou NULL donne le même refus. Les branches métier, notifications et
audit qui suivent sont conservés à l'identique du corps LIVE.

## Appelants et permissions

- Seul appel applicatif direct repéré : `src/pages/DetailMission.tsx`, utilisé
  par l'établissement et l'administrateur.
- Recherche des autres `pg_proc.prosrc` LIVE : aucun appel direct de cette RPC.
- Recherche de `cron.job.command` : aucun appel direct. Aucun appel Edge dans le
  dépôt. Les automatismes qui exécutent leurs propres fonctions sont inchangés.
- EXECUTE authenticated/service_role est conservé, sans nouvelle autorisation.
  Une clé service sans identité humaine ne donne plus accès à cette RPC. Aucun
  workflow interne dépendant de ce cas n'a été trouvé.
- La migration vérifie empreinte, propriétaire, SECURITY DEFINER, search_path et
  ACL avant de redéfinir la fonction. Elle ne recapture que son entrée
  d'inventaire, avec la garde corrigée. Les douze autres avertissements de
  l'audit ne sont pas effacés.

## Vérifications locales et CI

- Six tests Vitest : empreinte du corps d'origine, conservation exacte des
  branches métier, absence d'élargissement ACL et raccord SQL/CI ; régressions
  existantes de clôture admin.
- `tsc -b`, build de vérification ES2020, 17 guards et actionlint verts.
- Suite `tests/security/cloture-mission-tenant.test.sql` ajoutée à la validation
  transactionnelle de `validate-pr.yml` : vrais utilisateurs synthétiques,
  membres actifs/révoqués, propriétaire distinct du tenant et propriétaire
  historique, RH, lecture seule, pointage, tiers, soignants, comptes
  bannis/supprimés, faux admin et admin valide. Les assertions appellent la vraie
  RPC sous les vrais rôles SQL, sans remplacer de helper ni désactiver de
  trigger. Les branches départ absent, segment ouvert, clôture normale,
  répétition, fin future et arbitrage admin sont exercées avec assertions sur
  le statut, la notification et l'audit. Savepoints et ROLLBACK annulent fixtures
  et files ; aucune donnée persistante ni fournisseur à invoquer.
- Cette suite SQL n'a **pas été exécutée localement** : PostgreSQL local absent.
  Elle doit passer en CI avant validation du correctif. Une simulation de
  réponses RPC ne prouve ni les ACL PostgreSQL ni les effets des triggers.

Commandes locales (dépendances déjà présentes, aucune installation) :

```sh
node_modules/.bin/vitest run tests/admin/security/cloture-mission-tenant.test.ts tests/admin/mission-termination-admin-arbitration.test.ts
node_modules/.bin/tsc -b
npm run test:guards
actionlint .github/workflows/validate-pr.yml
VITE_SUPABASE_URL=http://127.0.0.1:8891 VITE_SUPABASE_PUBLISHABLE_KEY=simulation-publishable-key VITE_SENTRY_DSN= node_modules/.bin/vite build --target es2020
node_modules/.bin/vite preview --host 127.0.0.1 --port 8898 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:8898 RECETTE_RESULTS_DIR=/private/tmp/jolene-cloture-tenant-ui-valide node_modules/.bin/playwright test --config e2e/playwright.recette-complete.config.ts e2e/recette-complete-cloture-tenant.spec.ts
```

## Simulation frontend

La spec exerce les actions visibles dans le vrai build : établissement avec
refus uniforme, absence de faux succès, rechargement et nouvelle tentative
autorisée ; soignant sans commande de clôture avant/après rechargement ; admin
avec créneau futur, litige actif, confirmation de l'arbitrage et rechargement.
Formats : iPhone WebKit, Android Chromium, iPad portrait/paysage WebKit,
ordinateur Chromium. Les captures, ARIA et journaux sont conservés par scénario.
Résultat final : **15/15**, zéro skipped/flaky/unexpected, zéro erreur console
ou page, 35 relevés ARIA ; captures de refus et confirmations admin examinées
sur les cinq formats.

Sessions, REST/RPC et ressources tierces sont simulés. Les polices Google sont
remplacées par la police système et le script Stripe par un objet vide local
(aucun paiement dans ce parcours). Toute autre requête externe est bloquée et
fait échouer l'assertion. Toutes les erreurs console/page sont enregistrées,
sans filtre. Les dépendances de score public et d'identité messagerie, manquantes
dans la première fixture, ont été ajoutées explicitement ; leurs erreurs 501
initiales n'ont pas été masquées.

Preuves locales : `/private/tmp/jolene-cloture-tenant-ui-valide/results.json`
et `summary.json`. Le premier passage soignant/établissement est conservé dans
`/private/tmp/jolene-cloture-tenant-ui-final/` (10/10, zéro erreur console/page).
Les essais initiaux et leurs erreurs restent dans les dossiers `ui-initial`,
`ui-desktop` et `ui-admin-initial` ; le dernier corrige une identité de fixture
établissement incompatible avec la route admin. La passe `ui-15-final`
(12/15) conserve trois erreurs WebKit dues au rechargement qui annulait le
rafraîchissement en cours. La spec attend désormais les événements
`requestfinished`/`requestfailed` et 500 ms sans lecture avant rechargement ;
aucune erreur n'est retirée du journal ni de l'assertion.

Aucun déploiement, appel métier LIVE, push, livraison mobile ou fournisseur
réel. Appareils physiques, SQL réel et concurrence à deux connexions ne sont pas
validés par cette recette locale.

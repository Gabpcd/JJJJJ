# Ouverture des futures inscriptions publiques — 25 septembre 2026

Le trigger LIVE `private.fn_forcer_compte_test_prelaunch()` imposait `est_compte_test=true` lors de toute insertion ou modification du champ, sur les deux tables de profils. Les Edge `register-soignant` et `register-etablissement` omettent ce champ ; leurs droits et leurs contrôles restent inchangés.

La migration `20260925143334_activation_future_inscriptions_publiques.sql` pose un défaut `false`, mais maintient les nouvelles inscriptions en test tant que `inscriptions_publiques_actives` ne vaut pas exactement `1`. Aucun profil existant n’est reclassé. Toute mise à jour conserve la cohorte précédente, y compris un upsert backend ; une tentative de modification depuis le client est rejetée.

Une inscription reste test après ouverture si les métadonnées privées Auth contiennent un booléen `est_compte_test=true` ou `is_test_playwright=true`, si l’adresse Auth correspond aux comptes CI historiques `playwright-soignant`, `playwright-etab` ou `playwright-test-*` du domaine `jolene.app`, ou si le backend indique explicitement `true`. Les métadonnées éditables par l’utilisateur et les adresses envoyées dans le formulaire ne décident jamais de la cohorte.

L’ouverture initiale passe par la dernière étape du workflow production, après le déploiement Edge, la vérification Stripe et les sondes des crons. Cette étape refuse toute référence ou URL autre que la production attendue. La fonction privée verrouille les deux paramètres et consomme `activation_inscriptions_publiques_planifiee=1` une seule fois. Un redéploiement ultérieur respecte une fermeture `active=0,pending=0`. Le workflow staging n’appelle jamais cette activation. La protection d’environnement repose sur les contrôles du workflow ; la fonction privée valide une référence fournie par ce workflow, sans introspecter l’identité propre du projet.

## Preuves locales

- **46/46 tests unitaires verts** : 12 nouveaux cas exécutent le vrai shell du workflow avec `curl` remplacé localement (aucun réseau), plus 34 gardes existantes de résolution des comptes et effets externes email/SMS.
- **SQL diagnostique local vert**, sur un schéma minimal PGlite : double application de la migration, insertions des deux types de profils, booléens privés et usurpation par métadonnées publiques, CI, conservation du stock, séparation des cohortes, modification client refusée, ACL, activation idempotente et kill-switch. Transaction annulée ; paramètres revenus à `active=0,pending=1`.
- **TypeScript et ESLint verts**. Relecture indépendante de Banach : aucun P1/P2 démontré sur migration, droits, tests et ordre d’activation.
- Le test transactionnel `tests/security/activation-inscriptions-publiques.test.sql` est branché dans la validation SQL CI staging. Aucun service externe n’est appelé par ce test.

Logs locaux : `/private/tmp/jolene-activation-public-unites.log`, `/private/tmp/jolene-activation-public-sql-local.log`, `/private/tmp/jolene-activation-public-tsc.log`, `/private/tmp/jolene-activation-public-lint.log`.

## Limites et statut

Cette vérification locale ne remplace pas le schéma staging complet avec l’ensemble de ses triggers et policies. La nouvelle révision doit donc passer la CI SQL avant merge. Aucune migration ni activation de production n’a été exécutée dans cette recette. Le stock de comptes test, la vérification des établissements, leurs permissions de publication, les finances, les cohortes et les gardes des transports restent protégés ; l’ouverture de futures inscriptions ne valide aucun dossier professionnel automatiquement.

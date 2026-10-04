# Rotation des deux fixtures techniques Playwright

Cette maintenance vise exclusivement les deux identités fixes définies dans
`scripts/lib/playwright-fixtures.mjs`, avec rôles SOIGNANT et
ADMIN_ETABLISSEMENT, profils `est_compte_test=true`, aucune appartenance à
l'équipe plateforme et aucune appartenance active à un établissement réel.
Elle ne sélectionne jamais un compte par entrée libre de l'opérateur.

Le secret GitHub `PLAYWRIGHT_FIXTURE_PASSWORD` contient 32 octets aléatoires
encodés en 64 caractères hexadécimaux. Il n'est ni affiché, ni enregistré dans
un fichier de recette. Le workflow le transmet à ses seuls jobs réels, sous
les noms internes `E2E_TEST_PASSWORD` et `PLAYWRIGHT_TEST_PASSWORD`.
Les secrets administrateur, REVIEW_* et le secret historique des load-tests
staging ne sont pas modifiés.

## Ordre de confinement

1. Ne plus démarrer ni relancer un ancien SHA du workflow Playwright : son
   setup peut rétablir l'ancien mot de passe public de l'établissement.
   Vérifier qu'aucun ancien job réel n'est actif ou en attente.
2. Configurer le nouveau secret privé et publier la branche corrigée sans
   ouvrir sa PR. Relire/revoir ce SHA exact avant toute maintenance.
3. Déclencher le workflow existant `playwright-e2e.yml` sur ce SHA, avec
   `rotate_fixture_credentials=true` et la confirmation exacte
   `ROTATE_ONLY_PLAYWRIGHT_FIXTURES`, et `expected_sha` égal au SHA complet relu.
   La branche doit être `main` ou `fix/identifiants-recette-prives-20261004` ;
   le HEAD checkout, `GITHUB_SHA` et le SHA saisi doivent être identiques. Ce mode n'exécute aucun navigateur,
   test fournisseur, build ou livraison. Son job conserve le verrou
   `jolene-playwright-shared-database` jusqu'au reçu final.
4. Exiger le reçu `completed=true`, `rotatedCount=2`, zéro session et zéro
   refresh non révoqué. Un succès partiel reste un échec ; corriger sa cause
   puis relancer uniquement le nouveau SHA. Aucun rollback vers le secret
   public. Une nouvelle lecture bornée indépendante doit confirmer l'état.
5. Ouvrir la PR, exécuter ses recettes habituelles avec le nouveau secret,
   faire relire et fusionner seulement après les contrôles requis. Le setup
   ultérieur utilise le secret privé et refuse l'ancien format public.

La révocation emploie la fonction existante
`fn_test_nettoyer_sessions_playwright('0 seconds')`, réservée au service role,
limitée à ces deux comptes et à 1 000 sessions par appel, au plus dix appels.
Une lecture fermée des catalogues Auth vérifie ensuite le résultat, y compris
les refresh orphelins éventuels ; leur présence empêche de conclure au succès.
Le mot de passe est modifié via l'API Auth Admin et non en écrivant ses hashes.

Les JWT d'accès déjà délivrés peuvent rester acceptés jusqu'à leur échéance
sur les chemins qui ne revérifient pas l'existence de la session. L'absence
de session ne prouve ni absence de connexion passée, ni absence d'utilisation
par un tiers. La rotation n'efface pas d'éventuelles copies historiques.

Au contrôle du 4 octobre, aucune version Apple n'était en revue. L'identité
des comptes fournis à Apple n'est pas démontrée distincte des fixtures.
Vérifier et, si nécessaire, actualiser les identifiants App Review avant la
prochaine livraison mobile manuelle ; les smoke tests CI avec fallback ne
prouvent pas cette configuration externe.

## Contrôles avant exécution

- `node --test tests/node/rotate-playwright-fixtures.node.mjs`
- `node scripts/check-admin-password-fixtures.mjs`
- Recette habituelle après rotation ; ces tests purs ne valident pas le parcours UI.

Le Management API utilise le secret existant `SUPABASE_ACCESS_TOKEN` pour
résoudre la clé de maintenance en mémoire et effectuer une lecture SQL bornée.
Aucun secret, jeton, email, identifiant de compte ou diagnostic distant n'est
inclus dans le reçu public. Les journaux de maintenance sont des constantes
ou des compteurs fermés.

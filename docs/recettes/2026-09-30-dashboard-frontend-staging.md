# Pilote frontend E10 — deux identités staging

Le mode manuel `dashboard_fixture_only=true`, avec le scénario
`05-dashboard-concurrent`, construit le frontend avec les seules clés publiques
staging, prépare les dix membres E10 puis ouvre deux contextes WebKit distincts
(iPhone et iPad). Pour chaque membre : connexion par formulaire, réponse dashboard
de sa propre identité, écran visible et rechargement conservant la session.
Le job n'installe ni ne lance k6. Il partage le verrou staging existant.

## Données et effets attendus

Les dix identités minimales restent celles du manifeste E10. Les secrets passent
par `GITHUB_ENV` privé ; seuls les slots 0 et 1 sont utilisés par le navigateur.
Ni service role ni jeton Management ne sont injectés dans le build. Les contextes
sont éphémères : pas de storageState, vidéo, trace, HAR ou export de réponse Auth.
Les erreurs publiées sont contrôlées, sans corps fournisseur ni pile Playwright.

Chaque connexion doit produire exactement un audit `CONNEXION` et modifier
uniquement `soignants.derniere_activite_le`. Le rechargement n'ajoute aucun audit.
Les lectures SQL avant/après comparent l'empreinte du reste du profil, les
comptes, préférences, sessions, identités, notifications et présences. Les
préférences restent toutes désactivées ; notifications et présences restent à
zéro. Les captures ne couvrent que le `main`, après vérification de l'identité et
des tableaux et gains vides. Aucun écran de connexion n'est enregistré.

Le routage refuse toute origine hors preview locale et staging, les écritures
métier, Edge Functions, Storage, signup, refresh et appels hors liste. La RPC de
création d'un jeton calendrier est notamment interdite. Le realtime est fermé ;
ce pilote ne valide donc pas la messagerie ni les notifications en temps réel.

Le nettoyage E10 est inchangé : il refuse toute dépendance hors de son allowlist
Auth/préférences existante, poursuit les autres membres sûrs et conserve les
manifests partiels. **Les deux journaux CONNEXION sont immuables et conservés**,
jamais supprimés pour obtenir un cleanup vert. Une dernière lecture exige zéro
Auth, profil, préférence, session et identité pour les deux slots, et confirme
exactement un audit conforme par slot. Les dix membres restent contrôlés par
le cleanup E10. Toute anomalie laisse le job en échec.

Les preuves filtrées sont dans `tests/load/results/dashboard-ui/` : `avant.json`,
`apres.json`, `cleanup.json`, `resultat.json` et quatre captures. Elles ne
contiennent ni IP, navigateur d'audit, identifiant de session, mot de passe ou
JWT. Le workflow conserve ces preuves et les manifests sept jours.

## Préflight et vérifications réalisées

Le contrat versionne les corps, propriétaires, search paths et droits definer de
douze fonctions, ainsi que dix triggers susceptibles de réagir aux deux
écritures UI. Un cron actif, une FK de journal vers Auth/profil ou une dérive du
catalogue bloque le pilote avant sa première connexion. Ne pas actualiser une
empreinte uniquement pour faire passer ce contrôle : examiner la définition et
ses effets, puis faire revoir le contrat.

Le 30 septembre 2026 vers 08:00 UTC, le préflight catalogue a été exécuté **en
lecture seule sur staging**, via le connecteur Supabase. Les douze fonctions et
dix triggers correspondent exactement au contrat local, zéro cron est actif et
aucune FK audit ne cible Auth/profil. Preuve locale non sensible :
`/private/tmp/jolene-dashboard-staging-catalogue-20260930.json`.
Ce contrôle ne crée aucun compte et ne prouve pas encore le parcours connecté.

Vérifications locales du complément : 95/95 tests Node du banc, 10/10 parcours
frontend **à réponses entièrement simulées** (deux identités × iPhone, Android,
iPad portrait/paysage et ordinateur), TypeScript, ESLint ciblé et actionlint.
La simulation utilise le même parcours navigateur et valide chaque requête
observée contre la liste autorisée du pilote réel.

Résultats : `/private/tmp/jolene-dashboard-staging-pilote-node.txt` et
`/private/tmp/jolene-dashboard-staging-pilote-ui-final/results.json`. Le produit n'est
pas modifié ; le build local vérifié E10 a servi ces simulations. Le build
connecté staging sera produit dans le job, avant toute création de fixture.

## Exécution restant à autoriser et à prouver

Aucune création, connexion UI, navigation réelle ni charge staging n'a été
exécutée pour ce complément. Après revue et validation du responsable, lancer
le workflow manuel E avec `dashboard_fixture_only=true`, puis examiner les deux
audits conservés, les preuves UI et tous les zéros de cleanup avant une campagne
de charge distincte. Le nominal ajoute au cycle préparation/nettoyage E10 deux
logins UI, quatre appels dashboard, quatre écritures RPC et quatre lectures SQL
de contrôle ; les autres lectures frontend sont consignées par chemin seulement.

Ce pilote ne navigue pas pendant k6 et ne valide aucun appareil physique. Même
vert, il ne mesure ni charge métier mixte, ni comptes avec historique, ni capacité
nationale. Les scénarios D/F restent suspendus.

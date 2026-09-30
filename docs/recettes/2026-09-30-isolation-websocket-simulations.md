# Isolation des WebSockets des sessions E2E fictives

Base auditée : `a215788777d94a1f6225e9b46a8795d273763e24`. Lot séparé de #1000.

## Défaut établi dans le code

`src/integrations/supabase/client.ts` (lignes 6–7 et 16) crée le client à partir de
`VITE_SUPABASE_URL`, avec un repli vers le projet production. Aucun appel manuel à
`realtime.setAuth` n'existe dans le code applicatif inspecté. Le SDK verrouillé en
version 2.99.2 dérive l'URL WebSocket de la même URL Supabase, puis transmet la
session Auth à Realtime lors de `SIGNED_IN`/`TOKEN_REFRESHED`. Ses fichiers locaux
`SupabaseClient.ts` (287–288, 565–586) et `RealtimeClient.ts` (858–904) montrent ce
chemin. Les hooks messages et notifications s'abonnent lorsqu'un utilisateur existe.

Le workflow `.github/workflows/playwright-e2e.yml` distingue deux circuits :

- `simulation-interfaces` construit avec Supabase sur `127.0.0.1:8890` (59–69),
  utilise la configuration `recette-complete` et ses helpers ferment les WS.
- Les jobs E2E PR et main construisent avec `E2E_SUPABASE_URL`, qui désigne le
  projet production (30, 191–195, 341–345), puis exécutent la configuration
  générale (221, 363). Son glob `**/*.spec.ts` exclut les `recette-complete`, mais
  inclut encore les simulations historiques ci-dessous. L'origine HTTP locale du
  frontend ne change pas l'URL Supabase compilée dans son client.

Les quatre specs `inscription-navigation`, `etablissement-exploration`,
`soignant-public-exploration`, `detail-mission-lisibilite`, ainsi que le helper
`exploration-simulee` utilisé par `fluidite-navigation`, renvoyaient une session
avec token factice via les routes HTTP Auth, sans route WebSocket. Le routage HTTP
Playwright et son routage WebSocket sont distincts. Une souscription Realtime de
ces sessions pouvait donc prendre le transport production malgré les mocks HTTP.
L'inventaire a été recoupé en lecture seule par un autre agent.

## Limite d'attribution

Le diagnostic agrégé transmis par l'agent `revue_export_201` compte 2 775 erreurs
`MalformedJWT` entre le 29 septembre 2026 à 10:32:44 UTC et le 30 septembre à
10:32:44 UTC, dans 3 053 lignes Realtime. Les erreurs se rapportent au format ;
aucune attribution à une session ou à un test n'est disponible. Aucun marqueur
explicite de recette n'a été trouvé dans les messages. Le profil horaire ne suffit
pas à attribuer ces erreurs aux tests. Le défaut d'isolation est établi par le
code ; l'origine des 2 775 erreurs reste non prouvée. Aucun changement Auth ou SDK
produit et aucun filtrage des logs de production ne découlent de cette hypothèse.

## Correction ciblée

Les cinq specs fictives importent une fixture de test dédiée. Chaque constructeur
de session installe l'interception WS de page avant sa première navigation.
Le handler ferme le socket localement, sans `connectToServer`. Un garde-fou au
niveau contexte ferme aussi tout socket oublié et fait échouer le test si cela
arrive. Le journal joint ne contient que protocole, hôte et chemin, jamais la
query ni un token. Les ressources HTTP extérieures non simulées sont également
bloquées dans ces seules specs ; leurs routes Auth/REST de page restent prioritaires.

Les assertions métier, la collecte des erreurs JavaScript et les autres listeners
existants restent inchangés. Les parcours Auth/backend réels n'importent pas cette
fixture et conservent leur transport. Les workflows existants ne changent pas.

La configuration locale autonome `e2e/playwright.simulations-historiques.config.ts`
sélectionne exactement les cinq specs et la preuve de transport, sur cinq formats,
sans globalSetup/globalTeardown distant, sans secrets, sans réessai. Le frontend
de recette utilise Supabase en loopback. La preuve de destination extérieure
utilise exclusivement `supabase-simulation.invalid`, intercepté avant transport ;
elle ne tente aucune connexion vers un projet Supabase réel.

## Recette

Simulations locales du 30 septembre 2026, avec réponses Auth/REST fictives et
Playwright 1.58.2 :

| Configuration | Première exécution des 26 scénarios | Isolation WS |
| --- | --- | --- |
| Ordinateur Chromium | 26 réussis | 26 journaux, aucune échappée |
| Android Chromium | 26 réussis | 26 journaux, aucune échappée |
| iPad portrait WebKit | 25 réussis, 1 navigation concurrente du brouillon | 26 journaux, aucune échappée |
| iPad paysage WebKit | 25 réussis, même scénario | 26 journaux, aucune échappée |
| iPhone WebKit | 25 réussis, même scénario | 26 journaux, aucune échappée |

La sentinelle `.invalid` réussit dans les cinq configurations. Les 130 journaux
comptent 473 tentatives Realtime loopback, 830 sockets HMR Vite et 5 sentinelles,
toutes fermées avant connexion serveur. Aucun journal ne contient une échappée.
L'absence de transport extérieur repose sur les handlers sans `connectToServer`,
le garde-fou de contexte et leurs preuves ; ces chiffres ne mesurent pas la
production. Les assertions existantes d'erreurs JS, de reprise, de permissions,
de navigation, de détails et d'affichage restent actives. Plusieurs scénarios
historiques imposent eux-mêmes les largeurs 390/1440 : la matrice couvre cinq
configurations de navigateur/appareil, sans prétendre que chaque capture utilise
la largeur native du projet. Les écrans d'erreur documents ont été inspectés.

Le scénario rouge modifie le rôle simulé dès l'URL `/inscription/completer`, avant
que `ParcoursInscription` ait fini son chargement et affiché son enfant. La trace
iPhone indique explicitement que le `goto` vers la création de mission est
interrompu par une navigation vers `/inscription/completer`. Les traces iPad
montrent la même concurrence. Cela ne démontre pas un défaut produit ni sa cause
profonde WebKit. Un commit séparé ajoute l'attente du titre visible exact
« Identifier votre établissement », avant la mutation du rôle simulé et le `goto`.
Les cinq exécutions ciblées après cette modification réussissent au premier essai
(23,6 secondes), avec erreurs JS et mutations vides, aucune échappée WS, et titre,
dates et horaires du brouillon préservés. Aucun sleep, retry ou filtre ajouté.
Les cinq captures finales ont été inspectées. La couverture finale est donc de
130 scénarios distincts avec dernière exécution réussie ; cela ne transforme pas
la première matrice en 130 réussites au premier essai.
Les échecs initiaux et leurs traces sont conservés ; aucun réessai automatique.

La recette ciblée est conservée dans
`/private/tmp/jolene-isolation-websocket-brouillon-apres-attente-20260930`.
La commande Playwright ci-dessous, sans `--project` et avec
`--grep 'brouillon établissement : titre'`, couvre les cinq formats.
`validation-finale.json` et `manifest-complet-sha256.json` complètent le dossier
de preuves (877 fichiers, SHA256 du manifeste complet
`8408c86ef44904fb9dadfd15c3159bc39e591f6fec744215cac7498c200680f3`).
Les deux typechecks et `git diff --check` sont de nouveau verts. La relecture
croisée confirme que le delta du second commit est limité à cette assertion et
à cette documentation ; toutes les autres assertions et captures sont préservées.

`tsc -b`, le typecheck isolé des six specs, des deux helpers et de la configuration,
ainsi que `git diff --check`, passent. Relectures croisées du périmètre : aucun
blocage relevé ; elles ne constituent pas la revue fraîche B8 avant merge.

Preuves : `/private/tmp/jolene-isolation-websocket-preuves-20260930/` contient
`validation-initiale.json` et `manifest-initial-sha256.json` (859 fichiers indexés,
SHA256 du manifeste `cbd47443e9cc0fa0882bbe084c340db4fece081c938191705936e3b29ade1496`).
Les résultats, captures et traces restent sous les dossiers
`/private/tmp/jolene-isolation-websocket-{ordinateur,ipad-portrait,ipad-paysage}-20260930`
et `...-{android,iphone}-{parcours,etablissement390,etablissement1440}-20260930`.
Android/iPhone sont découpés en trois sélections disjointes (24 + 1 + 1) pour
limiter l'espace temporaire. Des PNG identiques ont été reliés physiquement après
vérification SHA256, sans perdre de chemin, de contenu, de résultat ou de trace.
Les pauses pour espace disque et les incidents ENOSPC de recettes antérieures
restent distincts des trois échecs de navigation de cette matrice.

Reproduction locale, sans configuration générale ni secrets :

```sh
VITE_NATIVE_BUILD=true VITE_SUPABASE_URL=http://127.0.0.1:18460 VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_simulation_websocket node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 18460 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18460 RECETTE_RESULTS_DIR=/private/tmp/jolene-isolation-websocket-reproduction node node_modules/@playwright/test/cli.js test --config=e2e/playwright.simulations-historiques.config.ts --project=ordinateur
```

Changer le projet pour chacun des autres formats. Pour les sélections fractionnées,
utiliser successivement `--grep-invert 'compte établissement minimal'`,
`--grep 'compte établissement minimal.*390'` et `--grep 'compte établissement minimal.*1440'`,
avec un dossier de sortie distinct à chaque fois. Cette recette n'est ni une
intégration distante ni un essai sur appareils physiques.

La garde de contexte a également fait l'objet d'un contrôle négatif séparé,
entièrement local : `/private/tmp/jolene-isolation-websocket-garde-negative-20260930`.
Une spec temporaire omet volontairement l'installation de la garde de page puis
crée un socket vers le domaine `.invalid`. Le socket est fermé au contexte et le
runner échoue sur l'assertion dédiée « WebSocket sans interception de page ».
Le journal contient cette seule destination, sans paramètres. Ce résultat rouge
est attendu et sa trace reste conservée ; il n'est pas masqué par un `test.fail`
ou un réessai dans la suite versionnée.

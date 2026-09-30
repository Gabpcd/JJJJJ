# Notifications : rattrapage après reconnexion — 30 septembre 2026

## Périmètre

Correctif frontend isolé depuis `58fda7df`. Le refus ponctuel de handshake
Realtime observé dans la CI de la PR #995 a révélé un défaut distinct : après
reconnexion, les nouveaux événements étaient traités, mais ceux manqués pendant
la coupure n'étaient récupérés qu'en rouvrant le panneau. La page commissions
charge ses données par HTTP ; ce correctif ne résout ni ne masque un HTTP 502 du
fournisseur.

Le badge et le panneau relisent la liste (50 dernières notifications) et le
compteur exact après chaque souscription, y compris la première, puis après un
INSERT, une mutation ou l'ouverture du panneau. Une nouvelle lecture rend les
réponses antérieures inopérantes. Le composant est recréé par identité ; les
callbacks de l'ancien compte deviennent inactifs. Les événements déjà connus ne
produisent pas de doublon et les lectures de rattrapage ne déclenchent pas de
toast, de son ou de notification système. Les deux en-têtes responsive ont des
canaux distincts ; seul le badge visible peut émettre une alerte.

Une lecture de liste **ou** de compteur en erreur conserve les dernières données,
signale « actualisation nécessaire » sur le badge et affiche une erreur avec
« Réessayer » dans le panneau. Le compteur ne se limite plus aux 50 lignes du
panneau. Les mutations ciblent explicitement le destinataire.

## Reproduction avant correction

Composant React réel, client Supabase simulé, sans transport réseau :
`/private/tmp/jolene-realtime-reprise-investigation/evidence.json`.
Après reprise simulée, le panneau conservait zéro notification ; l'INSERT suivant
apparaissait et le compteur affichait 1 au lieu de 2. La réouverture récupérait
les deux. Cette preuve ne démontre pas qu'un événement a été perdu pendant le
run CI initial.

## Vérification locale

Commandes dans le checkout `/private/tmp/jolene-notifications-reconnexion-20260930` :

```sh
./node_modules/.bin/tsc -b
./node_modules/.bin/vitest run src/components/PanneauNotifications.reconnexion.test.tsx src/components/BarreNavigation.test.tsx
VITE_SUPABASE_URL=http://127.0.0.1:8891 VITE_SUPABASE_PUBLISHABLE_KEY=simulation-local VITE_SENTRY_DSN= ./node_modules/.bin/vite build
./node_modules/.bin/vite preview --host 127.0.0.1 --port 8897 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:8897 RECETTE_RESULTS_DIR=/private/tmp/jolene-notifications-reconnexion-final ./node_modules/.bin/playwright test -c e2e/playwright.recette-complete.config.ts e2e/recette-complete-notifications-reconnexion.spec.ts
```

Tests ciblés : rattrapage initial et après coupure, absence de toast rétroactif,
doublons, panne liste/compteur puis réessai, réponse tardive, changement de compte,
mutation tardive/en échec, compteur de 60 éléments avec panneau limité à 50,
coexistence des deux en-têtes.

Recette navigateur : soignant et établissement × iPhone WebKit, Android,
iPad portrait, iPad paysage, ordinateur. Le frontend complet et le SDK Supabase
installé sont utilisés. Un **bridge Phoenix/WebSocket simulé** intercepte toutes
les connexions : fermeture, nouvelle connexion, `phx_join`/`phx_reply` et INSERT.
Les réponses HTTP et les identités sont fictives ; aucune connexion à Supabase,
aucun compte créé et aucun fournisseur de notifications contacté. La feuille de
police externe est remplacée localement par une réponse vide.

Le scénario clique la cloche, garde le panneau ouvert pendant deux coupures,
crée une notification absente du flux, constate son rattrapage puis un nouvel
INSERT sans doublon, provoque des réponses HTTP 503 de lecture, vérifie les
dernières données conservées, clique « Réessayer », ferme puis recharge la page
et rouvre le panneau. Les erreurs console des 503 provoqués sont **toutes
conservées**, comptées contre les réponses 503 et vérifiées ; les pageerrors
restent bloquantes. Aucun filtre console/pageerror ni seuil CI existant n'est
modifié.

Preuves : `/private/tmp/jolene-notifications-reconnexion-final/results.json`,
ARIA et captures avant coupure, après rattrapage, pendant l'erreur et après
rechargement, journal `reconnexion-simulation` (protocole sans jeton ni trame
brute). Ces preuves ne valent ni transport Supabase réel, ni production, ni
appareil physique. Elles ne prouvent pas la disparition des 502 du fournisseur.

Résultats : TypeScript et build réussis, **26 tests unitaires ciblés**, garde-fous
`tests/non-regression/guards.sh` réussis, syntaxe ES2020 vérifiée sur les 498
fichiers JavaScript compilés. Matrice navigateur finale : **10/10**, aucun skip,
flaky ou unexpected. Chaque scénario conserve les quatre erreurs console
correspondant exactement aux quatre réponses 503 provoquées ; zéro pageerror,
appel inconnu ou appel externe. ARIA et captures examinées sur les cinq formats.
Les tests sont découverts par les jobs existants : `npm test` de Validate PR et
`recette-complete-*.spec.ts` du workflow Playwright. Aucun workflow n'est modifié.

## Complément : lecture et changement de format

La relecture indépendante a identifié deux écarts supplémentaires, reproduits
par trois tests rouges avant correction : le badge caché conservait son ancien
compteur après lecture, et « Tout marquer comme lu » ne ciblait que les 50 lignes
affichées (ou restait désactivé si elles étaient déjà lues).

Après une mutation réussie, un registre local de callbacks, séparé par identité,
fait relire tous les badges montés du même compte. Il ne conserve aucune donnée
de notification et les callbacks sont retirés au démontage. L'action « Tout
marquer comme lu » cible désormais toutes les notifications non lues du
destinataire ; son activation dépend du compteur exact, pas des 50 lignes.

La recette complète précédente est prolongée par une lecture individuelle,
fermeture du panneau puis changement de breakpoint mobile/desktop sans
rechargement : le nouveau badge doit afficher 3 non lues. Puis 60 notifications
sont chargées, toutes sont marquées lues, le format initial est restauré sans
rechargement et le compteur doit rester nul. Une notification d'un autre compte
reste non lue. Le serveur HTTP simulé applique les filtres du PATCH : une
mutation limitée à 50 IDs laisserait réellement 10 non lues et ferait échouer
la recette.

Commande identique, avec
`RECETTE_RESULTS_DIR=/private/tmp/jolene-notifications-delta-final`.
Les tests unitaires ciblés passent désormais **29/29**, dont la variante où les
50 premières notifications sont déjà lues alors que 10 plus anciennes ne le
sont pas. TypeScript et le build sont également vérifiés. Les preuves de ce
complément sont conservées séparément de la première matrice.

Matrice du complément : **10/10**, aucun skip/flaky/unexpected. Les dix ARIA
confirment le compteur 3 après lecture puis resize, et zéro après tout-lu puis
resize retour. Les quatre 503 provoqués et leurs quatre erreurs console restent
conservés par scénario ; zéro pageerror, appel inconnu ou externe. Résumé lisible :
`/private/tmp/jolene-notifications-delta-final/summary.json`.

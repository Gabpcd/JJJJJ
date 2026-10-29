# Pointage natif — scénario préparé, non exécuté

Cette préparation ajoute un scénario indépendant `presence`. Au 29 octobre,
le typecheck, 357 tests purs et les exports de contrôle iOS/Android ont passé ;
après relecture, les deux corrections ont également passé le typecheck, les 45
tests ciblés de transport et le témoin PostgreSQL 17. Aucune simulation native,
intégration STAGING de pointage ou livraison n'a encore été exécutée pour ce lot.
Le parcours à l'écran reste à vérifier.

## Exécution prévue

Le workflow `.github/workflows/native-presence.yml` prévoit quatre jobs frais :
iPhone portrait, Android portrait, iPad portrait et iPad paysage. Il sélectionne
`NATIVE_PILOT_SCENARIO=presence`, `EXPO_PUBLIC_JOLENE_MODE=demo` et
`EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO=1`. Documents et Contrats sont désactivés
pour cette simulation. Les autres scénarios et leurs manifests restent inchangés.

- iOS : XCTest `testPresenceIphonePortrait`, `testPresenceIpadPortrait`,
  `testPresenceIpadLandscape` ; une méthode par job, budget 600 s.
- Android : `maestro/presence-run.yaml` prépare une installation Expo Go fraîche,
  puis `presence-demo.yaml` exécute les actions. Budget 600 s.
- Le runner reste limité aux runners GitHub Actions. Il exige un succès réel du
  rapport XCTest/JUnit et les treize captures dans l’orientation attendue. Les
  screenshots sont les pixels bruts du système ; aucune retouche.
- Les cas purs ajoutés au manifeste peuvent être lancés par le parent depuis
  `mobile-native` avec `node --test scripts/native-scenarios.node.test.mjs`.
  Ils ne prouvent pas le parcours frontend.

## Assertions communes aux quatre formats

1. Entrer comme soignant fictif, ouvrir Présences puis la mission A : zéro scan.
2. Saisir `000000` : refus d’authentification fictif, sans reçu incertain ni
   enregistrement. La saisie reste disponible. Depuis A, saisir ensuite le code `654321` de B. La première réponse est explicitement
   incertaine ; le bouton de pointage reste bloqué.
3. Changer d’onglet, revenir, passer réellement à l’arrière-plan puis reprendre.
   Le reçu reste en attente ; aucun succès n’est fabriqué et aucun scan n’est
   envoyé automatiquement.
4. Relire le reçu : arrivée de **B**, pas A, à 11:00 heure de Paris. Ouvrir B :
   présence ouverte et exactement un scan. La relecture n’ajoute pas de scan.
5. Saisir l’ancien code `654321` : refus explicite. Saisir le nouveau `100001` :
   départ de B à 11:03 ; exactement deux scans et un créneau effectif fermé.
6. Se déconnecter puis entrer dans l’établissement fictif. A conserve zéro scan
   et son code `123456`. B conserve deux scans et expose `100002`. L’établissement
   ne dispose pas du formulaire de pointage soignant.
7. Revenir par geste natif iOS ou retour système Android : B reste visible dans
   la liste. Se déconnecter : écran/code/liste authentifiés disparaissent.

Treize captures par format, déclarées dans `PRESENCE_CAPTURES` : liste, A avant
saisie, refus d’authentification, confirmation incertaine, reprise, arrivée relue, présence ouverte, code
obsolète refusé, départ relu, présence clôturée, code initial, code renouvelé et retour
établissement. XCTest conserve aussi l’arbre d’accessibilité pour chaque capture ;
Maestro conserve son rapport et les commandes effectives.

## Limites explicites

Le `DemoPresenceGateway` conserve un monde synthétique partagé pour les deux
rôles et utilise une horloge déterministe au 27 octobre 2026. Le retour serveur
incertain, la rotation et les preuves sont des données **en mémoire**, distinctes
du backend STAGING. Il n’y a aucun appel RPC de pointage ni fournisseur réel.

La saisie est manuelle. La caméra QR, les permissions caméra/GPS, l’acquisition
GPS, un appareil physique et la persistance après arrêt du processus ne sont pas
validés par ce scénario. La reprise vérifiée est celle d’une navigation et d’un
passage Home/foreground conservant le même processus. Une réussite de cette CI
ne remplace aucune de ces preuves d’intégration ou matérielles.

Les valeurs de date et de code attendues viennent de la fixture actuelle ; tout
changement de fixture doit mettre à jour les assertions avec les mêmes preuves
métier, sans supprimer celles qui échouent. Les sélecteurs et la lisibilité réelle
des treize captures restent à vérifier après la première exécution.

## Fichiers à intégrer par fusion ciblée

Ajouts :

- `.github/workflows/native-presence.yml`
- `mobile-native/maestro/presence-run.yaml`
- `mobile-native/maestro/presence-demo.yaml`
- `mobile-native/PRESENCE-SCENARIO-PREPARATION.md`

Modifications partagées à fusionner avec la branche courante, sans écraser ses
changements plus récents :

- `mobile-native/scripts/native-scenarios.mjs` : sélection `presence`, treize noms,
  choix des méthodes XCTest et refus des injections simultanées.
- `mobile-native/scripts/native-scenarios.node.test.mjs` : trois cas purs ajoutés
  (quatre formats, refus, conservation exacte des trois manifests existants).
- `mobile-native/scripts/run-pilot-ci.mjs` : une ligne ajoutée pour injecter le
  flag Pointage choisi, sinon `0`.
- `mobile-native/ios-ui-tests/NativePilotUITests/NativePilotTests.swift` : trois
  méthodes de test, `runPresence` et `enterPresenceCode` ; aucun changement du
  comportement des scénarios existants.

Cette préparation a été reportée par ajouts ciblés sur
`30e1ce1de07ce9439d2e3ab80342aaea1d0bab6b`. iOS conserve le client Debug
compilé depuis les sources et le correctif TextInput React Native courant.
Android conserve le lancement Expo Go du pilote, y compris le traitement borné
du seul ANR Pixel Launcher. Les scénarios antérieurs et leurs assertions restent
présents ; la nouvelle vérification QR décode les pixels des deux captures de codes.

Documents garde neuf captures et Contrats huit, avec le cas avant enregistrement
et les deux signatures. Consultation garde seize captures. Leurs flows Maestro
et workflows ne sont pas remplacés. Les versions de modules Expo et plugins sont
verrouillées dans le lockfile ; la simulation reste à exécuter.

## Corrections issues de la revue du 29 octobre

- La lecture accepte le marqueur `est_etab: null` réellement retourné à un soignant
  affecté sans établissement. Les autres valeurs inattendues et tout code renvoyé
  au soignant restent refusés.
- Le rôle `POINTAGE_ONLY` utilise un nouveau prédicat SQL en lecture seule qui
  retourne uniquement l'existence d'un contrat entièrement signé entre les parties
  courantes de sa mission. Il conserve l'interdiction de lire le contrat. Le témoin
  PG17 utilise les helpers d'autorisation LIVE et reproduit cette RLS ; les autres
  tables et triggers de production ne sont pas reconstitués. Aucune signature,
  donnée de production ou opération financière n'est modifiée par ce témoin.
- La revue indépendante a clos ces deux constats. La validation/contestation
  établissement, les intégrations et les essais physiques ne sont pas couverts
  par ce lot d'arrivée/départ et restent à réaliser.

Préparation du 29 octobre : QR natif rendu en Views, marge blanche de quatre modules et décodeur indépendant des pixels des captures. Cette préparation n’est pas encore une simulation réussie ni une preuve de caméra physique. Le workflow iOS utilise le client Debug source avec le correctif RN verrouillé.

Le refus PostgREST avant exécution (`PGRST202`, `PGRST300` à `PGRST303`) est conservé comme résultat définitif dans le journal. Une reconnexion et une reprise peuvent le clôturer sans renvoyer la demande. Les erreurs réseau et codes inconnus restent incertains. Les 362 tests de logique passent après cet ajout ; la treizième étape native est préparée mais reste à exécuter. Source : https://docs.postgrest.org/en/stable/references/errors.html#postgrest-error-codes.

# Simulation native Android

Le workflow `android-native-recette.yml` exerce deux variantes réelles du SHA :
**debug** et **recetteOptimized** (configuration R8 de release, non debuggable,
signature debug éphémère). Les deux utilisent l'identifiant séparé `app.jolene.recette`, puis le lance sur
un émulateur Android 15 / Pixel 7 distant. Aucun SDK ou image système volumineux
n'est installé sur le poste local. Aucun secret, compte réel ou store n'est utilisé.
Firebase reçoit uniquement des ressources debug fictives du projet
`demo-jolene-native-recette`, avec création automatique du token FCM désactivée.
Cela permet au vrai plugin natif de se désinscrire à la déconnexion sans faire
planter Android faute d'instance Firebase. Les appels externes restent bloqués.

La WebView est pilotée avec l'[API Android de Playwright](https://playwright.dev/docs/api/class-android).
Le clavier et le bouton retour sont ceux de l'émulateur : l'état de l'IME Android
est interrogé et les événements retour passent par `adb input keyevent`.

Couverture : création de deux comptes fictifs, cinq onglets pour chaque rôle,
déconnexion puis connexion réelle au mock avec les mêmes identifiants, cinq
onglets à nouveau (20 contrôles), fermeture du détail de mission par le bouton
Retour Android avec URL Explorer inchangée, champ de mission
visible au-dessus du clavier, conservation de la saisie au premier retour, retour
Android vers l'écran précédent. Chaque contrôle produit un dump ARIA et une
capture native. Aucun titre vide ou simple rendu du conteneur ne vaut validation.

Isolation : API en mémoire sur `127.0.0.1:8904` via `adb reverse`, opérations
inconnues rejetées avec 501, CSP locale, sonde OTA native redirigée vers le mock,
et pare-feu IPv4/IPv6 par UID bloquant toute autre destination de l'APK. Les
assertions finales imposent zéro opération inconnue, zéro erreur JavaScript/CSP,
zéro paquet natif rejeté, deux comptes, deux inscriptions et deux connexions.
L'émulateur disparaît après le job. Les captures ne contiennent que des données
fictives `@example.invalid`.

La prédiction distante des formulaires de Chromium est désactivée uniquement dans
le WebView debug (`--disable-features=AutofillServerCommunication`), comme dans les
[tests officiels Android WebView](https://github.com/chromium/chromium/blob/380c6e427a89f57838159b045af13ea32e4f3251/android_webview/javatests/src/org/chromium/android_webview/test/AwAutofillTest.java).
Le run `36327000422` avait validé les 20 onglets mais échoué sur le garde réseau :
NetLog identifiait 46 requêtes de ce système vers `content-autofill.googleapis.com`,
toutes rejetées. Le clavier Android et les actions du produit restent exercés ;
le rejet réseau n'est pas assoupli. NetLog reste joint aux preuves.

L'attachement du pilote attend le processus exact de l'application et son socket
`webview_devtools_remote_<PID>`, puis vérifie `/proc/<PID>/cmdline` avant et après
connexion. La sélection utilise ce socket observé, sans dépendre de l'heuristique
de nom de package de Playwright. Le run `36331414022` s'était arrêté avant toute
assertion car le sélecteur package ne trouvait pas la WebView, alors que la capture
montrait Connexion. La cause interne précise n'est pas affirmée sans preuve.
`webview-attachment.json`, `android-processes.txt` et `android-unix-sockets.txt`
conservent les métadonnées de diagnostic. L'attente initiale est bornée ; aucune
action métier, aucun échec d'attachement CDP ou scénario n'est rejoué.

Le run `36332871114` a ensuite attaché cette WebView en 8,884 secondes, mais le
premier contrôle de clavier a échoué : la capture montrait une fenêtre « Pixel
Launcher isn't responding » devant Jolene. Logcat date cet ANR à `16:25:22.304`,
avant même le lancement du script de recette à `16:25:23.196` et l'installation
de l'APK terminée à `16:25:29.402`. Aucun onglet ni compte n'a
été validé dans ce run. Le préflight vérifie désormais, **avant installation**,
que l'application de recette est absente et que le launcher garde le focus dix
secondes consécutives. Il archive chaque observation. Seulement si le processus
exact `com.google.android.apps.nexuslauncher` présente cet ANR, il archive aussi
`dumpsys activity lastanr` puis redémarre ce launcher une seule fois. Tout autre
ANR, toute erreur d'application, toute récidive ou absence de stabilisation fait
échouer le job. La détection utilise le
[titre de fenêtre système AOSP](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-15.0.0_r1/services/core/java/com/android/server/am/AppNotRespondingDialog.java),
et non le texte traduit du bouton. `emulator-preflight.json` conserve cette phase ;
les dumps système et une capture finale restent joints même en échec. Après
attachement, avant tout geste, Jolene doit posséder le focus natif sans fenêtre
d'erreur. Aucun ANR après installation n'est fermé, aucun parcours n'est rejoué,
et les assertions clavier ainsi que le pare-feu restent inchangés.

Les seules adaptations du build de recette sont son identifiant, l'origine locale
HTTP pour l'API, l'activation du débogage WebView, l'isolation réseau et la sonde OTA.
Les pages React, le bridge, les plugins et `MainActivity` sont ceux du produit.
Le script refuse un checkout contenant une configuration Firebase réelle ou une
clé release. Aucun `google-services.json` n'est ajouté.

Cette recette **ne prouve pas** le backend réel, les permissions professionnelles,
la livraison push/SMS, les paiements, la signature store ou les performances d'un
téléphone physique. Le succès est établi seulement par le run CI et ses artefacts ;
la présence de ce harnais dans le dépôt n'est pas une preuve d'exécution.

Vérifications locales sans émulateur :

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/native/android -p 'test_*.py'
node --check scripts/native/prepare-android-recette.mjs
node --check tests/native/android/navigation.mjs
node --test tests/native/android/*.test.mjs
bash -n scripts/native/run-android-recette.sh
```


## Qualification R8

La variante `recetteOptimized` est ajoutée uniquement par le préparateur dans le
checkout CI éphémère. `initWith release` conserve les règles et optimisations de
release ; `matchingFallbacks = ['release']` sélectionne les plugins release.
Le manifeste et les ressources Firebase fictives debug sont réutilisés. Aucun
secret release, Play, compte réel ou distribution n'intervient. Le débogage CDP
de la WebView reste explicitement activé dans cette seule configuration fictive,
indépendamment du drapeau Android `debuggable`, vérifié faux sur l'APK optimisé.

Le contrôle avant installation lit le DEX réellement présent dans cet APK, les
noms des plugins attendus après `cap sync`, le mapping et la configuration R8.
Il refuse les interrupteurs globaux d'optimisation, l'absence de renommage ou un
plugin retiré/renommé. Les empreintes et comptes sont conservés, pas l'APK ni le
mapping complet. Ce contrôle n'est pas le calcul de pourcentage Google Play.

Les deux variantes imposent les mêmes vingt contrôles d'onglets, clavier et
retour natifs. Elles vérifient aussi les dix-huit plugins enregistrés par le
bridge natif et des vrais appels locaux App, Preferences et Filesystem (écriture,
lecture, suppression dans le cache de l'application fictive). Camera, code-barres,
biométrie matérielle, partage externe et notification physique ne sont pas
qualifiés par ces appels ; aucun message ou changement de store/OTA n'est tenté.

Pour le binaire non debuggable, la collecte NetLog utilise l'adb root déjà requis
sur l'émulateur au lieu de `run-as`, exclusivement sous `app.jolene.recette`.
L'isolation UID et les assertions de zéro trafic sortant restent obligatoires.
Un refus CDP, permission, réflexion ou réseau reste un échec sans nouvelle tentative.

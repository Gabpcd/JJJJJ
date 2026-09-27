# Simulation native Android

Le workflow `android-native-recette.yml` construit un **APK debug Capacitor réel**
du SHA de la PR, sous l'identifiant séparé `app.jolene.recette`, puis le lance sur
un émulateur Android 15 / Pixel 7 distant. Aucun SDK ou image système volumineux
n'est installé sur le poste local. Aucun secret, compte réel ou store n'est utilisé.

La WebView est pilotée avec l'[API Android de Playwright](https://playwright.dev/docs/api/class-android).
Le clavier et le bouton retour sont ceux de l'émulateur : l'état de l'IME Android
est interrogé et les événements retour passent par `adb input keyevent`.

Couverture : création de deux comptes fictifs, cinq onglets pour chaque rôle,
déconnexion puis connexion réelle au mock avec les mêmes identifiants, cinq
onglets à nouveau (20 contrôles), détail/fermeture de mission, champ de mission
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

Les seules adaptations du build de recette sont son identifiant, l'origine locale
HTTP pour l'API, l'activation du débogage WebView, l'isolation réseau et la sonde OTA.
Les pages React, le bridge, les plugins et `MainActivity` sont ceux du produit.
Le script refuse un checkout contenant la configuration Firebase ou une clé release.

Cette recette **ne prouve pas** le backend réel, les permissions professionnelles,
la livraison push/SMS, les paiements, la signature store ou les performances d'un
téléphone physique. Le succès est établi seulement par le run CI et ses artefacts ;
la présence de ce harnais dans le dépôt n'est pas une preuve d'exécution.

Vérifications locales sans émulateur :

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/native/android -p 'test_*.py'
node --check scripts/native/prepare-android-recette.mjs
node --check tests/native/android/navigation.mjs
bash -n scripts/native/run-android-recette.sh
```

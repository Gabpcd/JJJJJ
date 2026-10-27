# Pilote natif Jolene

Les consignes de Gabrielle et du dépôt parent s'appliquent ici.

- Client React Native séparé : connexion d'un soignant existant, consultation des missions et détail.
- Navigation avec React Navigation native-stack et composants natifs, sans WebView.
- Mode démonstration par défaut, explicitement affiché ; intégration uniquement sur STAGING avec clé publique et JWT utilisateur. Aucun accès privilégié ou repli production.
- Aucun build de livraison, OTA, EAS Build/Submit/Update ou soumission store automatique. Les exports et simulations de vérification sont autorisés.
- Une seule campagne locale de simulation à la fois et au moins 5 Gio libres sur le volume Data.
- Les preuves doivent distinguer interface native sur simulateur, données fictives, intégration STAGING et appareil physique.
- Lire les docs de la version Expo verrouillée avant de changer les API natives. Garder les versions et le lockfile synchronisés.
- Les dossiers ios/android sont générés par Expo ; les paramètres natifs sont définis dans app.json.

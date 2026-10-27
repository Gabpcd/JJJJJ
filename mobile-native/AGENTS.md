# Migration native Jolene

Les consignes de Gabrielle et du dépôt parent s'appliquent ici.

- Client React Native séparé : migration progressive des parcours soignant et établissement, en conservant les contrats métier serveur existants.
- Navigation avec React Navigation native-stack et composants natifs, sans WebView.
- Mode démonstration par défaut, explicitement affiché ; intégration uniquement sur STAGING avec clé publique et JWT utilisateur. Aucun accès privilégié ou repli production.
- Aucun build de livraison, OTA, EAS Build/Submit/Update ou soumission store automatique. Les exports et simulations de vérification sont autorisés.
- Une seule campagne locale de simulation à la fois et au moins 5 Gio libres sur le volume Data.
- Les preuves doivent distinguer interface native sur simulateur, données fictives, intégration STAGING et appareil physique.
- Aucune réponse fictive ne remplace une erreur serveur. Aucun bouton de mutation ne doit annoncer un succès sans réponse serveur vérifiée et relecture de l'objet.
- Les écrans d'un établissement utilisent l'identifiant et les permissions retournés par le serveur, jamais user.id par défaut. Les identités vérifiées et contrats signés restent protégés.
- Lire les docs de la version Expo verrouillée avant de changer les API natives. Garder les versions et le lockfile synchronisés.
- Les dossiers ios/android sont générés par Expo ; les paramètres natifs sont définis dans app.json.

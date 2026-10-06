# Simulation iOS ciblée de 1.0.7 (24)

Le workflow `ios-version-soumise.yml` charge les outils de la branche de recette
et compile séparément le produit figé à `bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84`.
Les versions Xcode doivent déjà être 1.0.7/24 et sont vérifiées à nouveau dans
le `.app` réellement compilé, avec empreinte du Mach-O et SDK simulateur.

La cible XCTest réutilise les gestes/captures du Swift historique du 23 septembre
et les assertions/fixtures de la recette Android du commit livré. L'API existante
`tests/native/android/api.py` reste inchangée : elle est en mémoire sur 8904,
rejette les opérations inconnues et n'appelle aucun fournisseur. Les identités
sont fictives. Le runner macOS lance un iPhone puis un iPad de son runtime installé,
sans parallélisme ni répétition d'un test échoué. Les deux rôles passent les cinq
onglets, redémarrent l'application avec conservation de session, puis se
déconnectent/reconnectent. L'iPad est testé en portrait et paysage. Chaque écran
asserté fournit une capture et un arbre d'accessibilité XCTest. Le rapport API
exige deux inscriptions, deux reconnexions et zéro erreur/opération inconnue.

Les adaptations sont limitées au checkout CI jetable : identifiant
`app.jolene.recette`, signature désactivée, entitlements retirés, HTTP autorisé
pour l'API locale, frontend dirigé vers loopback, CSP locale, télémétrie coupée,
sonde OTA redirigée vers le mock qui retourne 404. Les plugins et les réglages
de clavier/safe-area du produit sont conservés. Aucun secret de distribution,
livraison, soumission ou changement de store n'est utilisé.

Il s'agit d'un **nouveau binaire simulateur du code 1.0.7/24**, pas de l'IPA signé
destiné aux appareils physiques. La CSP ne remplace pas un pare-feu natif par
processus ; le plugin AppUpdate peut consulter les métadonnées publiques Apple
en lecture seule (`nativeUpdateLookupMayContactApple: true` dans le manifeste).
La recette ne prétend pas mesurer l'absence exhaustive de trafic natif.
Elle ne prouve pas les sept cycles métier intégrés, les OTP/push reçus,
la caméra/GPS physiques, Stripe TEST ou la production. Une compilation réussie
sans XCTest/rapports verts ne vaut pas validation. Les échecs et leur `.xcresult`
sont conservés. Les fichiers présents sont un banc, pas une preuve d'exécution.

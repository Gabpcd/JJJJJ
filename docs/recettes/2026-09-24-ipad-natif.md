# Complément natif iPad — 24 septembre 2026

Deux tests XCTest ont réussi dans le simulateur iPadOS 18.6, application Capacitor locale isolée `app.jolene.recette`, viewport 1032×1376 en portrait et 1376×1032 en paysage. Il s’agit du frontend de cette branche compilé en mode natif, avec API HTTP locale et identités fictives `example.invalid`. Ce n’est ni l’application de production ni le binaire store22.

## Parcours vérifiés

1. Depuis l’écran de connexion : création d’un compte soignant minimal, sélecteur de profession natif, champs et cases du formulaire ; arrivée dans Explorer et navigation Accueil/Revenus/Mon compte dans les deux orientations. Déconnexion et reconnexion du même compte. Création d’un compte établissement minimal, accès Accueil/Missions/Publier/Messagerie en portrait et paysage ; saisie d’un intitulé avec le clavier natif en paysage.
2. Déconnexion et reconnexion établissement ; passage de l’invitation aux notifications via « Plus tard » ; navigation dans les deux orientations. Reconnexion soignant et mesure de la carte de mission corrigée : trois actions visibles et accessibles au toucher, portrait et paysage.

Résultats conservés localement : `/private/tmp/jolene-ipad-native-final-20260924.xcresult` (succès07:14:47 Paris) et `/private/tmp/jolene-ipad-native-review-v2-20260924.xcresult` (succès07:30:57 Paris). Captures et arbres d’accessibilité extraits. Les premières reprises du deuxième test ont corrigé ses sélecteurs de navigation et son attente de la modale facultative ; elles ne sont pas comptées comme validations réussies.

## Défaut visuel découvert au-delà des assertions fonctionnelles

Sur le grand iPad portrait, le deck Swipe s’étirait sur toute la hauteur disponible : carte **448×1069 points**, grand vide intérieur et actions très éloignées du contenu. Le conteneur est maintenant borné à720px dès768px, tout en restant réductible en paysage. La carte native mesurée fait **448×600 points** dans les deux orientations ; ses trois boutons sont entièrement visibles. La présentation mobile garde ses règles existantes.

- [Avant : carte trop haute](assets/2026-09-24-ipad-natif/swipe-portrait-avant.png)
- [Après : portrait](assets/2026-09-24-ipad-natif/swipe-portrait-apres.png)
- [Après : paysage](assets/2026-09-24-ipad-natif/swipe-paysage-apres.png)
- [Formulaire établissement et clavier en paysage](assets/2026-09-24-ipad-natif/mission-clavier-paysage.png)
- [Arbre d’accessibilité portrait](assets/2026-09-24-ipad-natif/swipe-portrait-aria.txt)
- [Arbre d’accessibilité paysage](assets/2026-09-24-ipad-natif/swipe-paysage-aria.txt)

## Limites

Le serveur en mémoire du complément natif couvre les comptes minimaux et propose des états vides par défaut. Il sert au contrôle de l’enveloppe Capacitor, du clavier, de l’orientation et de la navigation ; la matrice navigateur stricte est la preuve détaillée des pages et actions métier. Le CSP du banc natif est limité aux services locaux ; les hints DNS/TLS externes ont été retirés du dernier bundle de test. Le premier écran d’erreur natif provenait du WebSocket local refusé par ce CSP, corrigé dans le banc sans changement produit.

Aucun appel à la production, activation de notifications, envoi réel, signature contractuelle, paiement ou publication de mission. Aucune mesure de fluidité sur appareil physique n’est déduite de ces tests. Le simulateur a été arrêté après conservation des résultats.

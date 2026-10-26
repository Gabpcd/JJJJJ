# Défilement et clavier des formulaires — 26 octobre 2026

Le retour depuis les CGU perdait la position du formulaire : le gestionnaire global mémorisait seulement `window.scrollY`, alors que `AuthLayout` possède son propre conteneur, remis à zéro au montage. Le correctif mémorise ce conteneur et attend son montage lazy, tout en gardant la remise en haut lors d'un changement d'étape. Un changement de paramètres dans la même page conserve sa position.

La remise en vue d'un champ natif utilise désormais les limites réelles du conteneur sous le header. La référence de hauteur suit les rotations et reste conservée pendant la réduction du WebView et une réouverture rapide du clavier, pour éviter de soustraire deux fois sa hauteur.

## Vérification

- 35 tests unitaires ciblés : retour liste/détail/onglets, paramètres de page, conteneur du formulaire, changement d'étape et navigation clavier ; champ sous le header, limites visibles, rotation, ordre des événements natifs et nettoyage après installation partielle.
- `npx tsc -b` et compilation web avec URL Supabase locale : réussis.
- 10 simulations frontend ciblées réussies, sans reprise ni cas ignoré : 2 scénarios sur iPhone, Android, iPad portrait/paysage et ordinateur. Voir `resultats.json`, arbres d'accessibilité par format et captures iPhone.
- 10 simulations supplémentaires réussies : formulaire établissement (erreur, sauvegarde partielle et reprise) et navigation des cinq onglets/sous-onglets soignant, sur les mêmes cinq formats. Voir `resultats-roles.json`.
- Revue indépendante à contexte vierge : CLÔTURABLE. Un défaut de conservation de hauteur lors d'une réouverture immédiate a été corrigé avant cette campagne.

Commande des scénarios ciblés :

```sh
RECETTE_START_SERVER=1 npx playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-navigation-defilement.spec.ts
```

## Nature des preuves et limites

Interface React réelle servie en local ; toutes les API et les événements du bridge Capacitor sont simulés. Le défilement programmatique vérifie la géométrie et la restauration, pas l'inertie tactile. Les captures clavier représentent une fenêtre réduite simulée, pas un clavier iOS photographié. Aucun compte distant, paiement, document ou contrat n'a été modifié.

Cette correction conserve l'architecture React DOM dans Capacitor. Elle ne transforme pas les écrans en contrôles natifs. Aucune livraison mobile, OTA ni soumission store n'a été lancée ; le comportement sur téléphone physique n'est pas validé par cette campagne.

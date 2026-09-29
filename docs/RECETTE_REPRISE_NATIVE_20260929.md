# Reprise de session, notifications et mises à jour — 29 septembre 2026

## Comportement

- Après au moins 30 minutes d'absence, retour au tableau de bord du compte connecté. Une absence courte conserve la page ; une saisie en cours, un dialogue, une signature, un paiement ou un lien de notification garde la priorité.
- La session d'authentification est conservée. Les comptes soignants et établissements encore incomplets gardent l'accès à leur interface.
- L'avis de mise à jour provient de la disponibilité signalée par le store. Il se ferme sans bloquer l'app ; un bouton dans Mon compte relance la vérification. Une panne réseau ne signifie jamais « à jour ».
- L'autorisation du téléphone et l'enregistrement du token côté serveur sont vérifiés séparément. Un échec serveur permet un réessai ; la reprise de l'app vérifie aussi une permission changée dans les réglages.
- Les messages temporaires restent au-dessus de l'avis de mise à jour, sans masquer son bouton.

## Vérification effectuée

30 scénarios frontend dans Chromium/WebKit : soignant et établissement après connexion ou inscription, reprise courte et longue, session conservée, notification ouvrant la messagerie, rechargement après absence, avis du store et réessai après panne du registre push. Formats : iPhone, Android, iPad portrait, iPad paysage, ordinateur.

Après correction du chevauchement, le scénario de mise à jour a été rejoué sur les cinq formats avec une assertion géométrique : le bas du message de connexion reste au-dessus du haut de l'avis. Les deux captures suivantes complètent ces assertions :

- [iPhone](recette-native-20260929/mise-a-jour-iphone.png)
- [iPad paysage](recette-native-20260929/mise-a-jour-ipad.png)

Extraits des états vérifiés dans l'interface :

```text
Avant le réessai :
Autorisation du téléphone
Les notifications sont autorisées, mais cet appareil n’a pas pu être enregistré.
Vérifiez votre connexion puis réessayez.
Activer sur cet appareil

Après le réessai :
Autorisation du téléphone
Les notifications sont autorisées sur cet appareil.

Store avec version disponible :
Une mise à jour est disponible
Installez la dernière version de Jolene pour profiter des améliorations.
Mettre à jour
Me le rappeler plus tard
```

28 tests ciblés couvrent aussi les formulaires non enregistrés, liens profonds, permissions refusées, session changée, rotation du token échouée et disponibilité inconnue du store. TypeScript et les 17 garde-fous passent.

## Limites et livraison

Le pont Capacitor et les réponses réseau de cette recette sont simulés. Ces tests ne prouvent ni la réception APNs/FCM sur téléphone verrouillé, ni une installation depuis un store. Ces vérifications restent distinctes et doivent être faites sur les applications natives.

Le nouveau plugin AppUpdate exige un prochain build natif. La version reste volontairement 1.0.6 (23) pendant les corrections ; aucun build de livraison, aucune publication OTA et aucune soumission aux stores ne doivent être déclenchés par le merge. La prochaine livraison est une action manuelle séparée, après les corrections et validations.

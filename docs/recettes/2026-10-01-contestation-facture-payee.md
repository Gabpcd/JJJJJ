# Contestation d’une facture payée — recette du 1er octobre 2026

L’établissement peut ouvrir une demande de revue depuis une facture de son historique de paiements, avec la référence exacte de cette facture. Les anciens paiements sans référence de facture ne proposent pas cette action. Cette demande ne déclenche aucun remboursement.

Le formulaire partagé avec le soignant attend une lecture complète et cohérente des factures. Une erreur, une réponse partielle ou une facture absente bloque la progression et propose de réessayer. Les listes sont paginées avec vérification du total et des doublons. Un changement de mission invalide immédiatement l’ancienne sélection, dans le récapitulatif comme dans la requête envoyée.

Un succès n’est affiché que si le serveur confirme la création avec un identifiant de litige. Un refus métier, une session expirée, une panne réseau ou une réponse ambiguë conserve le formulaire. Le serveur garde ses contrôles de droits, de périmètre et de délai ; aucune migration ni fonction serveur n’est modifiée par ce lot.

## Vérifications

- 19 tests unitaires : lecture paginée, résultats incomplets, incohérences, annulation, erreurs et reprise du formulaire, absence de double envoi, changement de mission.
- 17 tests de contrat de facturation, vérification TypeScript et compilation web de contrôle.
- Simulation du formulaire des deux rôles sur iPhone, Android, iPad portrait, iPad paysage et ordinateur : 10 scénarios sans relance automatique. Lecture indisponible, reprise, référence exacte, réponse de création ambiguë, refus serveur, confirmation et rechargement sont exercés dans l’interface.
- Une campagne complémentaire des formulaires préexistants a passé 20 scénarios sur les mêmes cinq formats avant les dernières corrections ciblées du récapitulatif et du texte.

Les réponses réseau de cette recette frontend sont simulées. Elle ne prouve pas un remboursement Stripe TEST, un envoi push, ni le comportement d’un appareil physique. La recette financière intégrée reste distincte. Aucun build de livraison mobile ni envoi aux stores n’a été lancé.

Les captures, rapports Playwright et journaux locaux sont conservés dans `/private/tmp/jolene-contestation-preuves-20261001/`. La validation CI et le déploiement sont à vérifier sur le commit de la PR avant fusion.

# Suivi des paiements et remboursements Connect — candidat frontend

Ce lot ne déclenche aucun remboursement. Il expose la lecture autorisée de la facture et de sa Session Checkout exacte par `fn_suivi_remboursements_connect_facture`. Son déploiement dépend de la RPC et du moteur Connect avant transfert associés ; ils doivent être composés et vérifiés avant publication.

Le retour Checkout ne déduit plus une réussite de la dernière trace d’une facture. Sans Session identifiée, après une lecture refusée ou incomplète, ou après un statut historique ambigu, aucune réussite n’est annoncée. L’erreur qui affirmait qu’aucun paiement n’avait été enregistré est retirée : un échec de remboursement ne prouve pas l’absence du paiement initial.

Le dialogue traite les sept états du moteur. Un incident plus récent prime sur une ancienne confirmation. Les commissions et le montant total établissement sont absents de la réponse destinée au soignant. La lecture est annulée lors du changement de compte ou de facture ; un réessai ou un rechargement ne crée aucune opération financière. Le bouton est accessible depuis les factures du soignant et de l’établissement ainsi que depuis le détail de mission des trois rôles concernés.

Le refus HTTP 409 `CONNECT_REFUND_RECONCILIATION_REQUIRED` affiche une explication française précise. Le backend associé refuse de préparer un nouveau paiement tant que ce remboursement doit être rapproché. La simulation prouve le message et l’absence d’ouverture du Checkout ; elle ne prétend pas avoir empêché une deuxième charge réelle chez Stripe.

Les refus HTTP 503 `CONNECT_RELEASE_CLOSED` et `CONNECT_CLIENT_VERSION_REQUIRED` expliquent respectivement l’indisponibilité pendant la mise à jour et la nécessité de recharger Facturation. Aucun nouveau Checkout n’est ouvert, aucun paiement n’est annoncé comme confirmé, et le rechargement ne répète pas l’appel de paiement. Ces réponses explicites nécessitent le nouveau handler ; les anciennes versions encore en cours d’exécution pendant la bascule peuvent conserver leur erreur générique.

## Vérifications locales

- 101 tests unitaires ciblés réussis : validation stricte des réponses, état courant, masque des commissions, changement de compte/facture et erreurs métier.
- 30 scénarios de suivi réussis sur iPhone, Android, iPad portrait, iPad paysage et ordinateur : deux rôles pour les sept états et la reprise ; retour exact ou ancien lien ; entrée depuis le détail de mission pour trois rôles.
- 35 scénarios de facturation réussis sur les mêmes cinq formats, dont les refus HTTP 409 et 503, l’absence de Checkout et le rechargement sans nouvel appel de paiement.
- Compilation de simulation et vérification TypeScript réussies. Revue indépendante favorable du produit et des trois refus explicites.

Les réponses API sont contrôlées et les appels fournisseurs neutralisés. Aucun compte réel, paiement, remboursement, email ni SMS n’a été créé par ces simulations. Ces preuves ne remplacent ni les contrôles SQL/RLS ni le circuit Stripe TEST intégré.

## Échecs conservés et corrections

La première matrice élargie a réussi 25 cas sur 30 ; les cinq entrées soignant échouaient parce que le banc ne simulait pas le score public et la résolution de l’interlocuteur établissement. Le banc réutilise maintenant le helper strict existant ; aucune erreur n’est masquée.

Le nouveau refus 409 a ensuite échoué sur les cinq formats : le message était remplacé par une erreur générique. Un test unitaire a reproduit cet échec avant l’ajout du mapping explicite. Le même scénario HTTP 409 est désormais réussi sur les cinq formats. Seule son erreur console réseau 409 exacte est attendue.

Un témoin unitaire a également reproduit les deux messages de maintenance remplacés par l’erreur générique : deux échecs et 40 réussites avant correction. Les mappings précis et leurs simulations 503 passent maintenant sur les cinq formats. Chaque scénario attend uniquement sa propre erreur console HTTP exacte ; les autres erreurs restent bloquantes.

Preuves locales : `/private/tmp/jolene-suivi-connect-preuves-20261001/`. Le manifeste conserve les empreintes des sources, du build et des résultats. Le remboursement Connect après transfert, l’intégration Stripe TEST et la vérification sur appareil physique restent hors de ces preuves.
